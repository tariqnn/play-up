export type PricingInput = {
  basePriceMinor: number;
  durationMinutes: number;
  discountType?: "percentage" | "fixed";
  discountValue?: number;
};

export function canPublishPublicProfile(data: Record<string, unknown> | undefined): boolean {
  if (!data || data.role !== "player" || data.isTest === true || data.isDemo === true ||
      data.isGuest === true || data.suspended === true || data.publicProfile === false) {
    return false;
  }
  const privacy = data.privacyPreferences;
  if (privacy && typeof privacy === "object" && !Array.isArray(privacy) &&
      (privacy as Record<string, unknown>).publicProfile === false) {
    return false;
  }
  const displayName = typeof data.displayName === "string" ? data.displayName.trim() : "";
  const normalizedName = displayName.toLowerCase();
  if (!displayName || ["player", "guest player"].includes(normalizedName) ||
      /\b(uat|demo|test|sample|dummy|placeholder)\b/i.test(displayName)) {
    return false;
  }
  const email = typeof data.email === "string" ? data.email.trim().toLowerCase() : "";
  return !/@(uat\.invalid|playup\.test|playup-demo\.test)$/.test(email) &&
    !/\b(uat|demo|test|sample)\b/.test(email);
}

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

export function calculateSettlement(totalMinor: number, commissionBps: number): {
  grossMinor: number;
  platformCommissionBps: number;
  platformCommissionMinor: number;
  academyNetMinor: number;
} {
  if (!Number.isInteger(totalMinor) || totalMinor < 0) {
    throw new Error("Invalid settlement total");
  }
  if (!Number.isInteger(commissionBps) || commissionBps < 0 || commissionBps > 10_000) {
    throw new Error("Invalid commission rate");
  }
  const platformCommissionMinor = Math.round(totalMinor * commissionBps / 10_000);
  return {
    grossMinor: totalMinor,
    platformCommissionBps: commissionBps,
    platformCommissionMinor,
    academyNetMinor: totalMinor - platformCommissionMinor,
  };
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

export type PeakPricingConfig = {
  peakHourStart?: number;
  peakHourEnd?: number;
  peakPriceMinor?: number;
};

export function calculateEffectiveHourlyRate(
  basePriceMinor: number,
  start: Date,
  config?: PeakPricingConfig,
): { hourlyRateMinor: number; isPeak: boolean } {
  if (
    config &&
    typeof config.peakHourStart === "number" &&
    typeof config.peakHourEnd === "number" &&
    typeof config.peakPriceMinor === "number" &&
    config.peakPriceMinor > 0
  ) {
    const hour = start.getHours();
    const isPeak = hour >= config.peakHourStart && hour < config.peakHourEnd;
    if (isPeak) {
      return { hourlyRateMinor: config.peakPriceMinor, isPeak: true };
    }
  }
  return { hourlyRateMinor: basePriceMinor, isPeak: false };
}

export function calculateRatingDelta(
  teamARating: number,
  teamBRating: number,
  teamAWon: boolean,
): { aDelta: number; bDelta: number } {
  const effectiveA = teamARating > 0 ? teamARating : 2.5;
  const effectiveB = teamBRating > 0 ? teamBRating : 2.5;
  const diff = (effectiveB - effectiveA) * 100;
  const expectedA = 1 / (1 + Math.pow(10, diff / 400));
  const actualA = teamAWon ? 1 : 0;
  const rawDelta = 0.3 * (actualA - expectedA);
  const aDelta = Number(rawDelta.toFixed(2));
  const bDelta = Number((-rawDelta).toFixed(2));
  return { aDelta, bDelta };
}

export function calculateNextReliability(
  current: number,
  action: "completed" | "lateCancel" | "noShow",
): number {
  if (action === "completed") return Math.min(100, Math.round(current + 2));
  if (action === "lateCancel") return Math.max(0, Math.round(current - 15));
  if (action === "noShow") return Math.max(0, Math.round(current - 25));
  return current;
}
