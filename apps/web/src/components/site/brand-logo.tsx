import { cn } from "@/lib/utils";

// BRIXTA Keydrop text-based brand, replacing the upstream Keydrop SVG.
// No data, authentication, or campaign behaviour is changed here.
export function BrandWordmark({ label, className }: { label: string; className?: string }) {
  return (
    <span aria-label={label} className={cn("inline-flex items-baseline gap-1.5 whitespace-nowrap font-bold tracking-tight text-current", className)}>
      <span className="text-[1.15rem]">BRIXTA</span>
      <span className="text-[0.95rem] font-semibold text-muted-foreground">Keydrop</span>
    </span>
  );
}

export function BrandMark({ className, label }: { className?: string; label?: string }) {
  return (
    <span
      {...(label ? { role: "img", "aria-label": label } : { "aria-hidden": true })}
      className={cn("inline-flex size-7 shrink-0 items-center justify-center rounded-lg bg-primary text-sm font-black text-primary-foreground", className)}
    >
      B
    </span>
  );
}
