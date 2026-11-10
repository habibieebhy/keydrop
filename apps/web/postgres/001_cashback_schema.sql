-- PostgreSQL-only cashback module. Does not change Supabase public/auth/storage tables.
CREATE SCHEMA IF NOT EXISTS keydrop;

CREATE TABLE IF NOT EXISTS keydrop.cashback_campaigns (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    slug text NOT NULL UNIQUE,
    title text NOT NULL,
    amount_paise integer NOT NULL DEFAULT 1000 CHECK (amount_paise > 0),
    total_rewards integer NOT NULL CHECK (total_rewards > 0),
    claimed_rewards integer NOT NULL DEFAULT 0 CHECK (claimed_rewards >= 0 AND claimed_rewards <= total_rewards),
    status text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','active','paused','closed')),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS keydrop.cashback_claims (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    campaign_id uuid NOT NULL REFERENCES keydrop.cashback_campaigns(id),
    -- Server-generated HMAC of a VERIFIED phone number. No raw phone numbers here.
    verified_phone_hash text NOT NULL,
    amount_paise integer NOT NULL CHECK (amount_paise > 0),
    status text NOT NULL DEFAULT 'reserved' CHECK (status IN ('reserved','payout_pending','paid','failed','cancelled')),
    claimed_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT one_claim_per_verified_phone_per_campaign UNIQUE (campaign_id, verified_phone_hash)
);
CREATE INDEX IF NOT EXISTS cashback_claims_status_idx ON keydrop.cashback_claims(status, claimed_at);

CREATE TABLE IF NOT EXISTS keydrop.cashback_payouts (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    claim_id uuid NOT NULL UNIQUE REFERENCES keydrop.cashback_claims(id),
    -- Preserve the same transfer ID across retries to avoid double payouts.
    transfer_id text NOT NULL UNIQUE,
    cashfree_reference text,
    amount_paise integer NOT NULL CHECK (amount_paise > 0),
    status text NOT NULL DEFAULT 'created' CHECK (status IN ('created','submitted','processing','paid','failed','unknown')),
    attempt_count integer NOT NULL DEFAULT 0 CHECK (attempt_count >= 0),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

-- Transactional allocation helper. Caller MUST verify OTP before calling and use
-- a server-only PostgreSQL role. Do not expose this function as a public endpoint.
CREATE OR REPLACE FUNCTION keydrop.allocate_cashback_reward(
    p_campaign_slug text,
    p_verified_phone_hash text
)
RETURNS TABLE (claim_id uuid, amount_paise integer, already_claimed boolean)
LANGUAGE plpgsql
AS $function$
DECLARE
    c keydrop.cashback_campaigns%ROWTYPE;
    old_claim keydrop.cashback_claims%ROWTYPE;
    new_id uuid;
BEGIN
    IF p_verified_phone_hash IS NULL OR length(p_verified_phone_hash) < 32 THEN
        RAISE EXCEPTION 'INVALID_VERIFIED_IDENTITY';
    END IF;
    -- Serialize claims for a campaign. Unique constraint also enforces one per phone.
    SELECT * INTO c FROM keydrop.cashback_campaigns
    WHERE slug = p_campaign_slug FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'CAMPAIGN_NOT_FOUND'; END IF;

    SELECT * INTO old_claim FROM keydrop.cashback_claims
    WHERE campaign_id = c.id AND verified_phone_hash = p_verified_phone_hash;
    IF FOUND THEN
        RETURN QUERY SELECT old_claim.id, old_claim.amount_paise, true;
        RETURN;
    END IF;
    IF c.status <> 'active' THEN RAISE EXCEPTION 'CAMPAIGN_UNAVAILABLE'; END IF;
    IF c.claimed_rewards >= c.total_rewards THEN RAISE EXCEPTION 'OUT_OF_REWARDS'; END IF;

    INSERT INTO keydrop.cashback_claims (campaign_id, verified_phone_hash, amount_paise)
    VALUES (c.id, p_verified_phone_hash, c.amount_paise)
    RETURNING id INTO new_id;
    UPDATE keydrop.cashback_campaigns
    SET claimed_rewards = claimed_rewards + 1, updated_at = now()
    WHERE id = c.id;
    RETURN QUERY SELECT new_id, c.amount_paise, false;
END;
$function$;
