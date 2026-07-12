export type PricingInput = {
  basePriceMinor: number;
  durationMinutes: number;
  discountType?: "percentage" | "fixed";
  discountValue?: number;
};

export function calculateTotal(input: PricingInput): {
  subtotalMinor: number;
  discountMinor: number;
  totalMinor: number;
} {
  if (!Number.isInteger(input.basePriceMinor) || input.basePriceMinor < 0) {
    throw new Error("Invalid base price");
  }
  if (!Number.isInteger(input.durationMinutes) || input.durationMinutes <= 0 || input.durationMinutes > 480) {
    throw new Error("Invalid duration");
  }
  const subtotalMinor = Math.round(input.basePriceMinor * input.durationMinutes / 60);
  let discountMinor = 0;
  if (input.discountType === "percentage") {
    const value = input.discountValue ?? 0;
    if (value < 0 || value > 100) throw new Error("Invalid percentage discount");
    discountMinor = Math.round(subtotalMinor * value / 100);
  } else if (input.discountType === "fixed") {
    const value = input.discountValue ?? 0;
    if (value < 0) throw new Error("Invalid fixed discount");
    discountMinor = Math.min(subtotalMinor, Math.round(value));
  }
  return {subtotalMinor, discountMinor, totalMinor: subtotalMinor - discountMinor};
}

export function overlaps(aStart: Date, aEnd: Date, bStart: Date, bEnd: Date): boolean {
  return aStart < bEnd && aEnd > bStart;
}

export function assertTransition(from: string, to: string): void {
  const allowed: Record<string, string[]> = {
    pending: ["confirmed", "cancelled"],
    confirmed: ["checkedIn", "cancelled"],
    checkedIn: ["completed"],
    completed: [],
    cancelled: [],
  };
  if (!allowed[from]?.includes(to)) throw new Error(`Invalid booking transition: ${from} -> ${to}`);
}
