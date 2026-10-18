import {initializeApp} from "firebase-admin/app";
import {FieldValue, Timestamp, getFirestore} from "firebase-admin/firestore";
import {getAuth} from "firebase-admin/auth";
import {getMessaging} from "firebase-admin/messaging";
import {HttpsError, onCall} from "firebase-functions/v2/https";
import {onDocumentCreated, onDocumentWritten} from "firebase-functions/v2/firestore";
import {onSchedule} from "firebase-functions/v2/scheduler";
import {setGlobalOptions} from "firebase-functions/v2/options";
import {assertTransition, calculateEffectiveHourlyRate, calculateNextReliability, calculateRatingDelta, calculateSettlement, calculateTotal, canPublishPublicProfile, overlaps} from "./domain";
import {randomBytes} from "node:crypto";

initializeApp();
setGlobalOptions({region: "me-central1", maxInstances: 20});
const db = getFirestore();
const callableOptions = {
  enforceAppCheck: process.env.FUNCTIONS_EMULATOR !== "true",
};

export const syncPublicProfile = onDocumentWritten("users/{userId}", async (event) => {
  const data = event.data?.after.data();
  const ref = db.collection("publicProfiles").doc(event.params.userId);
  if (!data || !canPublishPublicProfile(data)) {
    await ref.delete().catch(() => undefined);
    return;
  }
  await ref.set({
    displayName: data.displayName ?? "Player",
    city: data.city ?? "Location not set",
    level: data.level ?? 1,
    rankTitle: data.rankTitle ?? "Rookie",
    xp: data.xp ?? 0,
    rating: data.rating ?? 0,
    sports: data.sports ?? [],
    updatedAt: FieldValue.serverTimestamp(),
  }, {merge: true});
});

type AuthenticatedRequest = {
  auth?: {uid: string; token?: Record<string, unknown>} | null;
};

function requireAnyAuth(request: AuthenticatedRequest): string {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign in is required.");
  return request.auth.uid;
}

function requireAuth(request: AuthenticatedRequest): string {
  const uid = requireAnyAuth(request);
  const token = request.auth?.token ?? {};
  const firebase = token.firebase as {sign_in_provider?: string} | undefined;
  if (firebase?.sign_in_provider !== "anonymous" && token.email_verified !== true) {
    throw new HttpsError("failed-precondition", "Verify your email before using this feature.");
  }
  return uid;
}

async function profile(uid: string, allowDuringMaintenance = false) {
  const snap = await db.collection("users").doc(uid).get();
  const data = snap.data();
  if (!data || data.suspended === true) throw new HttpsError("permission-denied", "Account is unavailable.");
  if (!allowDuringMaintenance && !["superAdmin", "platformAdmin"].includes(data.role)) {
    const platform = (await db.collection("platformConfig").doc("general").get()).data();
    if (platform?.maintenanceMode === true) {
      throw new HttpsError("unavailable", platform.maintenanceMessage ?? "PlayUp is temporarily unavailable for maintenance.");
    }
  }
  return data;
}

function managesBooking(
  user: FirebaseFirestore.DocumentData,
  booking: FirebaseFirestore.DocumentData,
): boolean {
  if (user.role === "academyOwner" || user.role === "academyStaff") {
    return user.academyId === booking.academyId;
  }
  if (user.role === "courtOwner") {
    return user.academyId === booking.academyId
      && Array.isArray(user.courtIds)
      && user.courtIds.includes(booking.courtId);
  }
  return false;
}

function text(value: unknown, name: string): string {
  if (typeof value !== "string" || !value.trim()) throw new HttpsError("invalid-argument", `${name} is required.`);
  return value.trim();
}

function date(value: unknown, name: string): Date {
  const parsed = typeof value === "string" ? new Date(value) : new Date(NaN);
  if (Number.isNaN(parsed.valueOf())) throw new HttpsError("invalid-argument", `${name} is invalid.`);
  return parsed;
}

function bookingDuration(start: Date, end: Date): number {
  const durationMs = end.valueOf() - start.valueOf();
  if (start <= new Date() || end <= start) {
    throw new HttpsError("invalid-argument", "Choose a future time range.");
  }
  if (start.valueOf() % (30 * 60_000) !== 0
    || end.valueOf() % (30 * 60_000) !== 0) {
    throw new HttpsError("invalid-argument", "Booking times must use 30-minute boundaries.");
  }
  const durationMinutes = durationMs / 60_000;
  if (!Number.isInteger(durationMinutes)
    || durationMinutes < 30
    || durationMinutes > 240
    || durationMinutes % 30 !== 0) {
    throw new HttpsError("invalid-argument", "Booking duration must be 30-240 minutes in 30-minute increments.");
  }
  return durationMinutes;
}

function bookingTotal(
  court: FirebaseFirestore.DocumentData,
  durationMinutes: number,
  promotion?: FirebaseFirestore.DocumentData,
  start?: Date,
) {
  try {
    const effective = start
      ? calculateEffectiveHourlyRate(Number(court.basePriceMinor), start, {
          peakHourStart: court.peakHourStart != null ? Number(court.peakHourStart) : undefined,
          peakHourEnd: court.peakHourEnd != null ? Number(court.peakHourEnd) : undefined,
          peakPriceMinor: court.peakPriceMinor != null ? Number(court.peakPriceMinor) : undefined,
        })
      : { hourlyRateMinor: Number(court.basePriceMinor), isPeak: false };
    const total = calculateTotal({
      basePriceMinor: effective.hourlyRateMinor,
      durationMinutes,
      discountType: promotion?.discountType,
      discountValue: promotion?.discountValue,
    });
    return {
      ...total,
      isPeak: effective.isPeak,
      effectiveHourlyRateMinor: effective.hourlyRateMinor,
    };
  } catch {
    throw new HttpsError("failed-precondition", "Court pricing or promotion configuration is invalid.");
  }
}

function requireActiveAcademy(snapshot: FirebaseFirestore.DocumentSnapshot): FirebaseFirestore.DocumentData {
  const academy = snapshot.data();
  if (!academy || academy.status !== "active") {
    throw new HttpsError("failed-precondition", "The academy is not accepting bookings.");
  }
  return academy;
}

function zonedParts(value: Date, timeZone: string): {day: string; minutes: number} {
  const values = Object.fromEntries(
    new Intl.DateTimeFormat("en-CA", {
      timeZone,
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
      hour: "2-digit",
      minute: "2-digit",
      hourCycle: "h23",
    }).formatToParts(value).map(part => [part.type, part.value]),
  );
  return {
    day: `${values.year}-${values.month}-${values.day}`,
    minutes: Number(values.hour) * 60 + Number(values.minute),
  };
}

function validateCourtHours(
  court: FirebaseFirestore.DocumentData,
  start: Date,
  end: Date,
): void {
  const openingHour = Number(court.openingHour ?? 0);
  const closingHour = Number(court.closingHour ?? 24);
  const timeZone = String(court.timezone ?? "Asia/Amman");
  if (!Number.isFinite(openingHour) || !Number.isFinite(closingHour)
    || openingHour < 0 || openingHour > 23 || closingHour <= 0 || closingHour > 24
    || openingHour >= closingHour) {
    throw new HttpsError("failed-precondition", "The court opening hours are not configured correctly.");
  }
  let localStart: ReturnType<typeof zonedParts>;
  let localEnd: ReturnType<typeof zonedParts>;
  try {
    localStart = zonedParts(start, timeZone);
    localEnd = zonedParts(end, timeZone);
  } catch {
    throw new HttpsError("failed-precondition", "The court timezone is not configured correctly.");
  }
  const opensRoundTheClock = closingHour === 24;
  if (localStart.minutes < openingHour * 60
    || (!opensRoundTheClock && (localStart.day !== localEnd.day || localEnd.minutes > closingHour * 60))) {
    throw new HttpsError("failed-precondition", "Court is closed at this time.");
  }
}

function validateCourtBlocks(
  court: FirebaseFirestore.DocumentData,
  start: Date,
  end: Date,
): void {
  for (const period of [...(court.blockedPeriods ?? []), ...(court.maintenancePeriods ?? [])]) {
    const periodStart = period.start?.toDate?.();
    const periodEnd = period.end?.toDate?.();
    if (periodStart instanceof Date && periodEnd instanceof Date
      && overlaps(start, end, periodStart, periodEnd)) {
      throw new HttpsError("failed-precondition", "This period is blocked or under maintenance.");
    }
  }
}

function validatePromotion(
  promotion: FirebaseFirestore.DocumentData,
  court: FirebaseFirestore.DocumentData,
  courtId: string,
  subtotalMinor: number,
): void {
  if (promotion.active !== true) {
    throw new HttpsError("failed-precondition", "Promotion is inactive.");
  }
  const now = new Date();
  const startsAt = promotion.startsAt?.toDate?.();
  const endsAt = promotion.endsAt?.toDate?.();
  if ((startsAt instanceof Date && startsAt > now) || (endsAt instanceof Date && endsAt < now)) {
    throw new HttpsError("failed-precondition", "Promotion is outside its valid dates.");
  }
  if (promotion.academyId && promotion.academyId !== court.academyId) {
    throw new HttpsError("failed-precondition", "Promotion does not apply to this academy.");
  }
  if (promotion.courtId && promotion.courtId !== courtId) {
    throw new HttpsError("failed-precondition", "Promotion does not apply to this court.");
  }
  const usageLimit = Number(promotion.usageLimit ?? 0);
  const usageCount = Number(promotion.usageCount ?? 0);
  if (usageLimit > 0 && usageCount >= usageLimit) {
    throw new HttpsError("resource-exhausted", "Promotion usage limit has been reached.");
  }
  const minimumSpendMinor = Number(promotion.minimumSpendMinor ?? 0);
  if (minimumSpendMinor > 0 && subtotalMinor < minimumSpendMinor) {
    throw new HttpsError("failed-precondition", "This booking does not meet the promotion minimum spend.");
  }
  const perUserLimit = Number(promotion.perUserLimit ?? 0);
  if (!Number.isInteger(perUserLimit) || perUserLimit < 0) {
    throw new HttpsError("failed-precondition", "Promotion usage rules are configured incorrectly.");
  }
}

function commissionBpsFor(
  court: FirebaseFirestore.DocumentData,
  academy: FirebaseFirestore.DocumentData,
  platform: FirebaseFirestore.DocumentData,
): number {
  for (const source of [court, academy, platform]) {
    if (source && Object.prototype.hasOwnProperty.call(source, "platformCommissionBps")) {
      const bps = Number(source.platformCommissionBps);
      if (!Number.isInteger(bps) || bps < 0 || bps > 10_000) {
        throw new HttpsError("failed-precondition", "The platform commission is configured incorrectly.");
      }
      return bps;
    }
    if (source && Object.prototype.hasOwnProperty.call(source, "platformCommissionPercent")) {
      const percent = Number(source.platformCommissionPercent);
      const bps = Math.round(percent * 100);
      if (!Number.isFinite(percent) || bps < 0 || bps > 10_000) {
        throw new HttpsError("failed-precondition", "The platform commission is configured incorrectly.");
      }
      return bps;
    }
  }
  throw new HttpsError("failed-precondition", "The platform commission is not configured for this court, academy, or platform.");
}

function bookingIsActive(booking: FirebaseFirestore.DocumentData): boolean {
  return ["pending", "confirmed", "checkedIn"].includes(String(booking.status));
}

function requireUatProject(): void {
  const projectId = process.env.GCLOUD_PROJECT ?? "";
  if (process.env.FUNCTIONS_EMULATOR !== "true" && !projectId.toLowerCase().includes("uat")) {
    throw new HttpsError("failed-precondition", "UAT tools are disabled in this project.");
  }
}

export const quoteBooking = onCall(callableOptions, async (request) => {
  const uid = requireAuth(request);
  await profile(uid);
  const courtId = text(request.data?.courtId, "courtId");
  const start = date(request.data?.startUtc, "startUtc");
  const end = date(request.data?.endUtc, "endUtc");
  const durationMinutes = bookingDuration(start, end);
  const court = (await db.collection("courts").doc(courtId).get()).data();
  if (!court || court.active === false) throw new HttpsError("not-found", "Court is unavailable.");
  if (court.bookable === false) throw new HttpsError("failed-precondition", "Online booking is not available for this court yet. Contact the venue for pricing and availability.");
  const academy = await db.collection("academies").doc(String(court.academyId)).get();
  requireActiveAcademy(academy);
  validateCourtBlocks(court, start, end);
  validateCourtHours(court, start, end);
  const basePrice = bookingTotal(court, durationMinutes, undefined, start);
  let promotion: FirebaseFirestore.DocumentData | undefined;
  let promotionId: string | undefined;
  const promotionCode = typeof request.data?.promotionCode === "string" ? request.data.promotionCode.trim().toUpperCase() : "";
  if (promotionCode) {
    const result = await db.collection("promotions").where("code", "==", promotionCode).limit(1).get();
    const promotionDoc = result.docs[0];
    promotion = promotionDoc?.data();
    promotionId = promotionDoc?.id;
    if (!promotion) throw new HttpsError("failed-precondition", "Promotion is invalid or inactive.");
    validatePromotion(promotion, court, courtId, basePrice.subtotalMinor);
    const perUserLimit = Number(promotion.perUserLimit ?? 0);
    if (perUserLimit > 0) {
      const uses = await db.collection("promotionUses")
        .where("promotionId", "==", promotionDoc.id)
        .where("userId", "==", uid)
        .limit(perUserLimit)
        .get();
      if (uses.size >= perUserLimit) {
        throw new HttpsError("resource-exhausted", "You already used this promotion.");
      }
    }
  }
  return {
    currency: court.currency ?? "JOD",
    promotionId: promotionId ?? null,
    promotionCode: promotion ? promotionCode : null,
    ...bookingTotal(court, durationMinutes, promotion, start),
  };
});

export const createBooking = onCall(callableOptions, async (request) => {
  const uid = requireAuth(request);
  const callerProfile = await profile(uid);
  if (typeof callerProfile.reliability === "number" && callerProfile.reliability < 60) {
    throw new HttpsError("failed-precondition", "Your reliability score is below 60% due to recent cancellations. Contact the venue directly to book.");
  }
  const courtId = text(request.data?.courtId, "courtId");
  const start = date(request.data?.startUtc, "startUtc");
  const end = date(request.data?.endUtc, "endUtc");
  const durationMinutes = bookingDuration(start, end);
  const courtRef = db.collection("courts").doc(courtId);
  const bookingRef = db.collection("bookings").doc();
  const slotStarts = Array.from(
    {length: Math.ceil(durationMinutes / 30)},
    (_, index) => new Date(start.valueOf() + index * 30 * 60_000),
  );
  const lockRefs = slotStarts.map(slot =>
    db.collection("bookingLocks").doc(`${courtId}_${slot.valueOf()}`),
  );
  const playerCapacity = Number(request.data?.playerCapacity ?? 20);
  if (!Number.isInteger(playerCapacity) || playerCapacity < 1 || playerCapacity > 30) {
    throw new HttpsError("invalid-argument", "Player capacity must be 1-30.");
  }
  const promotionCode = typeof request.data?.promotionCode === "string"
    ? request.data.promotionCode.trim().toUpperCase()
    : "";
  return db.runTransaction(async (tx) => {
    const courtSnap = await tx.get(courtRef);
    const court = courtSnap.data();
    if (!court || court.active === false) throw new HttpsError("not-found", "Court is unavailable.");
    if (court.bookable === false) throw new HttpsError("failed-precondition", "Online booking is not available for this court yet. Contact the venue for pricing and availability.");
    const promotionQuery = promotionCode
      ? db.collection("promotions").where("code", "==", promotionCode).limit(1)
      : null;
    const [academySnap, platformSnap, playerBookings, promotionSnapshot, ...lockSnaps] = await Promise.all([
      tx.get(db.collection("academies").doc(String(court.academyId))),
      tx.get(db.collection("platformConfig").doc("general")),
      tx.get(db.collection("bookings")
        .where("participants", "array-contains", uid)
        .where("startUtc", ">=", Timestamp.fromDate(new Date(start.valueOf() - 4 * 60 * 60_000)))
        .where("startUtc", "<", Timestamp.fromDate(end))),
      promotionQuery ? tx.get(promotionQuery) : Promise.resolve(null),
      ...lockRefs.map(ref => tx.get(ref)),
    ]);
    const academy = requireActiveAcademy(academySnap);
    if (lockSnaps.some(lock => lock.exists)) throw new HttpsError("already-exists", "This time overlaps another booking.");
    const conflictingBooking = playerBookings.docs.some(document => {
      const booking = document.data();
      const bookingStart = booking.startUtc?.toDate?.();
      const bookingEnd = booking.endUtc?.toDate?.();
      return bookingIsActive(booking)
        && bookingStart instanceof Date
        && bookingEnd instanceof Date
        && overlaps(start, end, bookingStart, bookingEnd);
    });
    if (conflictingBooking) {
      throw new HttpsError("already-exists", "You already have another booking or match at this time.");
    }
    validateCourtBlocks(court, start, end);
    validateCourtHours(court, start, end);
    const basePrice = bookingTotal(court, durationMinutes, undefined, start);
    const promotionDoc = promotionSnapshot?.docs[0];
    const promotion = promotionDoc?.data();
    if (promotionCode && !promotion) {
      throw new HttpsError("failed-precondition", "Promotion is invalid or inactive.");
    }
    if (promotion) {
      validatePromotion(promotion, court, courtId, basePrice.subtotalMinor);
      const perUserLimit = Number(promotion.perUserLimit ?? 0);
      if (perUserLimit > 0) {
        const uses = await tx.get(db.collection("promotionUses")
          .where("promotionId", "==", promotionDoc!.id)
          .where("userId", "==", uid)
          .limit(perUserLimit));
        if (uses.size >= perUserLimit) {
          throw new HttpsError("resource-exhausted", "You already used this promotion.");
        }
      }
    }
    const price = bookingTotal(court, durationMinutes, promotion, start);
    const settlement = calculateSettlement(
      price.totalMinor,
      commissionBpsFor(court, academy, platformSnap.data() ?? {}),
    );
    const record = {
      userId: uid, academyId: court.academyId, courtId, courtName: court.name,
      sport: court.sport, startUtc: Timestamp.fromDate(start), endUtc: Timestamp.fromDate(end),
      status: "pending", currency: court.currency ?? "JOD", ...price,
      paymentMethod: "cash", paymentStatus: "pending",
      cashPaidPlayers: [uid],
      ...settlement, settlementStatus: "notCollected",
      matchmaking: request.data?.matchmaking === true, playerCapacity, participants: [uid],
      promotionId: promotionDoc?.id ?? null, promotionCode: promotion ? promotionCode : null,
      durationMinutes, lockIds: lockRefs.map(ref => ref.id),
      createdAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp(),
    };
    lockRefs.forEach((lockRef, index) => {
      const slotStart = slotStarts[index];
      tx.create(lockRef, {
        bookingId: bookingRef.id,
        userId: uid,
        courtId,
        startUtc: Timestamp.fromDate(slotStart),
        endUtc: Timestamp.fromDate(new Date(slotStart.valueOf() + 30 * 60_000)),
        expiresAt: Timestamp.fromDate(end),
        createdAt: FieldValue.serverTimestamp(),
      });
    });
    if (promotionDoc) {
      tx.update(promotionDoc.ref, {
        usageCount: FieldValue.increment(1),
        updatedAt: FieldValue.serverTimestamp(),
      });
      tx.create(db.collection("promotionUses").doc(bookingRef.id), {
        promotionId: promotionDoc.id,
        promotionCode,
        bookingId: bookingRef.id,
        userId: uid,
        discountMinor: price.discountMinor,
        createdAt: FieldValue.serverTimestamp(),
      });
    }
    tx.create(bookingRef, record);
    tx.create(db.collection("auditLogs").doc(), {actorId: uid, action: "booking.create", entity: "booking", entityId: bookingRef.id, academyId: court.academyId, createdAt: FieldValue.serverTimestamp()});
    return {bookingId: bookingRef.id, ...price, ...settlement, currency: record.currency};
  });
});

export const createBookingInvite = onCall(callableOptions, async (request) => {
  const uid = requireAuth(request);
  await profile(uid);
  const bookingId = text(request.data?.bookingId, "bookingId");
  const ref = db.collection("bookings").doc(bookingId);
  const inviteRef = db.collection("bookingInvites").doc();
  const token = randomBytes(18).toString("base64url");
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const booking = snap.data();
    if (!booking || booking.userId !== uid) throw new HttpsError("permission-denied", "Only the booking owner can invite players.");
    if (!["pending", "confirmed"].includes(String(booking.status))
      || booking.startUtc?.toDate?.() <= new Date()) {
      throw new HttpsError("failed-precondition", "This booking no longer accepts players.");
    }
    const capacity = Number(booking.playerCapacity ?? 1);
    const participantCount = (booking.participants ?? [booking.userId]).length;
    if (!Number.isInteger(capacity) || capacity <= participantCount) {
      throw new HttpsError("failed-precondition", "This booking has no available player places.");
    }
    tx.create(inviteRef, {token, bookingId, createdBy: uid, academyId: booking.academyId, active: true, uses: 0, maxUses: capacity - participantCount, expiresAt: booking.startUtc, createdAt: FieldValue.serverTimestamp()});
  });
  return {token, bookingId, url: `https://play-up.fit/join/booking/${token}`};
});

export const joinBookingInvite = onCall(callableOptions, async (request) => {
  const uid = requireAuth(request);
  const user = await profile(uid);
  const token = text(request.data?.token, "token");
  const query = await db.collection("bookingInvites").where("token", "==", token).limit(1).get();
  if (query.empty) throw new HttpsError("not-found", "Invite link is invalid.");
  const inviteRef = query.docs[0].ref;
  await db.runTransaction(async (tx) => {
    const inviteSnap = await tx.get(inviteRef);
    const invite = inviteSnap.data();
    if (!invite?.active || invite.expiresAt.toDate() <= new Date()) throw new HttpsError("failed-precondition", "Invite link has expired.");
    const bookingRef = db.collection("bookings").doc(invite.bookingId);
    const bookingSnap = await tx.get(bookingRef);
    const booking = bookingSnap.data();
    if (!booking || !["pending", "confirmed"].includes(booking.status)
      || booking.startUtc?.toDate?.() <= new Date()) {
      throw new HttpsError("failed-precondition", "Booking is unavailable.");
    }
    const participants: string[] = booking.participants ?? [booking.userId];
    if (participants.includes(uid)) throw new HttpsError("already-exists", "You already joined this booking.");
    if (Number(invite.uses ?? 0) >= Number(invite.maxUses ?? 0)
      || participants.length >= Number(booking.playerCapacity ?? 1)) {
      throw new HttpsError("resource-exhausted", "Booking is full.");
    }
    const start = booking.startUtc.toDate() as Date;
    const end = booking.endUtc.toDate() as Date;
    const userBookings = await tx.get(db.collection("bookings")
      .where("participants", "array-contains", uid)
      .where("startUtc", ">=", Timestamp.fromDate(new Date(start.valueOf() - 4 * 60 * 60_000)))
      .where("startUtc", "<", Timestamp.fromDate(end)));
    const conflict = userBookings.docs.some(document => {
      const candidate = document.data();
      const candidateStart = candidate.startUtc?.toDate?.();
      const candidateEnd = candidate.endUtc?.toDate?.();
      return bookingIsActive(candidate)
        && candidateStart instanceof Date
        && candidateEnd instanceof Date
        && overlaps(start, end, candidateStart, candidateEnd);
    });
    if (conflict) {
      throw new HttpsError("already-exists", "You already have another booking or match at this time.");
    }
    if (booking.matchId) {
      const matchRef = db.collection("matches").doc(String(booking.matchId));
      const matchSnap = await tx.get(matchRef);
      const match = matchSnap.data();
      if (!match || !["open", "full"].includes(String(match.status))) {
        throw new HttpsError("failed-precondition", "The linked match is unavailable.");
      }
      const players: string[] = match.players ?? [];
      const playerNames: string[] = match.playerNames ?? [];
      if (!players.includes(uid)) {
        if (players.length >= Number(match.capacity ?? 0)) {
          throw new HttpsError("resource-exhausted", "The linked match is full.");
        }
        const nextCount = players.length + 1;
        tx.update(matchRef, {
          players: [...players, uid],
          playerNames: [...playerNames, user.displayName ?? "Player"],
          neededPlayers: Math.max(0, Number(match.capacity ?? 0) - nextCount),
          status: nextCount >= Number(match.capacity ?? 0) ? "full" : "open",
          updatedAt: FieldValue.serverTimestamp(),
        });
      }
    }
    tx.update(bookingRef, {participants: FieldValue.arrayUnion(uid), updatedAt: FieldValue.serverTimestamp()});
    tx.update(inviteRef, {uses: FieldValue.increment(1), updatedAt: FieldValue.serverTimestamp()});
    tx.create(db.collection("notifications").doc(), {userId: booking.userId, type: "bookingJoined", title: "A player joined your booking", bookingId: invite.bookingId, read: false, createdAt: FieldValue.serverTimestamp()});
  });
  return {bookingId: query.docs[0].data().bookingId};
});

export const redeemOffer = onCall(callableOptions, async (request) => {
  const uid = requireAuth(request);
  await profile(uid);
  const offerId = text(request.data?.offerId, "offerId");
  const offerRef = db.collection("offers").doc(offerId);
  const userRef = db.collection("users").doc(uid);
  const redemptionRef = db.collection("redemptions").doc();
  return db.runTransaction(async (tx) => {
    const [offerSnap, userSnap] = await Promise.all([tx.get(offerRef), tx.get(userRef)]);
    const offer = offerSnap.data(); const user = userSnap.data();
    if (!offer || offer.active === false) throw new HttpsError("not-found", "Offer is unavailable.");
    const cost = Number(offer.pointsCost ?? offer.points);
    if (!Number.isInteger(cost) || cost <= 0) throw new HttpsError("failed-precondition", "Offer has an invalid points cost.");
    const balance = Number(user?.points ?? 0);
    if (balance < cost) throw new HttpsError("failed-precondition", `You need ${cost - balance} more points.`);
    const duplicate = await tx.get(db.collection("redemptions").where("userId", "==", uid).where("offerId", "==", offerId).limit(1));
    if (!duplicate.empty) throw new HttpsError("already-exists", "You already redeemed this offer.");
    const code = `PU-${randomBytes(5).toString("hex").toUpperCase()}`;
    tx.update(userRef, {points: FieldValue.increment(-cost), updatedAt: FieldValue.serverTimestamp()});
    tx.create(redemptionRef, {userId: uid, offerId, title: offer.title ?? "Reward", partner: offer.partner ?? "PlayUp partner", academyId: offer.academyId ?? null, points: cost, code, status: "issued", createdAt: FieldValue.serverTimestamp()});
    tx.create(userRef.collection("pointsLedger").doc(), {type: "redemption", description: offer.title ?? "Reward redeemed", delta: -cost, balanceAfter: balance - cost, redemptionId: redemptionRef.id, createdAt: FieldValue.serverTimestamp()});
    return {redemptionId: redemptionRef.id, code, balance: balance - cost};
  });
});

export const transitionBooking = onCall(callableOptions, async (request) => {
  const uid = requireAuth(request);
  const user = await profile(uid);
  const bookingId = text(request.data?.bookingId, "bookingId");
  const next = text(request.data?.status, "status");
  const requestedReason = typeof request.data?.reason === "string"
    ? request.data.reason.trim().slice(0, 120)
    : "";
  const ref = db.collection("bookings").doc(bookingId);
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const booking = snap.data();
    if (!booking) throw new HttpsError("not-found", "Booking not found.");
    const permissions: string[] = user.permissions ?? [];
    const platform = user.role === "superAdmin" || permissions.includes("bookings.manage");
    const academy = managesBooking(user, booking)
      && (["academyOwner", "courtOwner"].includes(user.role)
        || permissions.includes("academy.bookings.manage")
        || (next === "checkedIn" && permissions.includes("academy.bookings.checkin")));
    const playerCancel = booking.userId === uid && next === "cancelled";
    if (!platform && !academy && !playerCancel) throw new HttpsError("permission-denied", "You cannot change this booking.");
    if (playerCancel && !requestedReason) throw new HttpsError("invalid-argument", "A cancellation reason is required.");
    const bookingStart = booking.startUtc?.toDate?.() as Date | undefined;
    if (playerCancel && bookingStart && bookingStart <= new Date()) {
      throw new HttpsError("failed-precondition", "A booking cannot be cancelled after it has started. Contact the venue.");
    }
    if (next === "confirmed" && bookingStart && bookingStart <= new Date()) {
      throw new HttpsError("failed-precondition", "An expired booking cannot be confirmed.");
    }
    if (next === "completed" && Number(booking.totalMinor ?? 0) > 0
      && booking.paymentStatus !== "collected") {
      throw new HttpsError("failed-precondition", "Record the cash received before completing the booking.");
    }
    try { assertTransition(booking.status, next); } catch (error) { throw new HttpsError("failed-precondition", (error as Error).message); }
    const update: FirebaseFirestore.UpdateData<FirebaseFirestore.DocumentData> = {
      status: next,
      updatedAt: FieldValue.serverTimestamp(),
      [`${next}At`]: FieldValue.serverTimestamp(),
    };
    if (next === "completed") {
      const hostRef = db.collection("users").doc(booking.userId);
      const hostSnap = await tx.get(hostRef);
      const hostData = hostSnap.data();
      if (hostData) {
        const nextRel = calculateNextReliability(Number(hostData.reliability ?? 100), "completed");
        tx.update(hostRef, {
          reliability: nextRel,
          matches: FieldValue.increment(1),
          updatedAt: FieldValue.serverTimestamp(),
        });
      }
    }
    if (next === "cancelled") {
      const isLatePlayerCancellation = playerCancel
        && bookingStart != null
        && bookingStart.valueOf() - Date.now() < 6 * 60 * 60_000;
      if (isLatePlayerCancellation) {
        const hostRef = db.collection("users").doc(booking.userId);
        const hostSnap = await tx.get(hostRef);
        const hostData = hostSnap.data();
        if (hostData) {
          const nextRel = calculateNextReliability(Number(hostData.reliability ?? 100), "lateCancel");
          tx.update(hostRef, {
            reliability: nextRel,
            updatedAt: FieldValue.serverTimestamp(),
          });
        }
      }
      const feeMinor = isLatePlayerCancellation
        ? Math.round(Number(booking.totalMinor ?? 0) * 0.5)
        : 0;
      const cancelledSettlement = calculateSettlement(
        feeMinor,
        Number(booking.platformCommissionBps ?? 0),
      );
      update.cancellationReason = requestedReason
        || (platform && !academy ? "Cancelled by platform administrator" : "Cancelled by venue");
      update.cancelledBy = uid;
      update.cancellationFeeMinor = feeMinor;
      update.paymentStatus = feeMinor > 0 ? "pending" : "notRequired";
      update.grossMinor = cancelledSettlement.grossMinor;
      update.platformCommissionMinor = cancelledSettlement.platformCommissionMinor;
      update.academyNetMinor = cancelledSettlement.academyNetMinor;
      update.settlementStatus = feeMinor > 0 ? "notCollected" : "void";
      const lockIds: string[] = booking.lockIds ?? [`${booking.courtId}_${booking.startUtc.toDate().valueOf()}`];
      lockIds.forEach(lockId => tx.delete(db.collection("bookingLocks").doc(lockId)));
      if (booking.matchId) {
        tx.update(db.collection("matches").doc(booking.matchId), {
          status: "cancelled",
          updatedAt: FieldValue.serverTimestamp(),
          cancelledAt: FieldValue.serverTimestamp(),
        });
      }
      const participants: string[] = booking.participants ?? [booking.userId];
      for (const playerId of [...new Set(participants)]) {
        if (playerId === uid) continue;
        tx.create(db.collection("notifications").doc(), {
          userId: playerId,
          type: booking.matchId ? "matchCancelled" : "bookingCancelled",
          title: booking.matchId ? "Your match was cancelled" : "Your booking was cancelled",
          bookingId,
          matchId: booking.matchId ?? null,
          read: false,
          createdAt: FieldValue.serverTimestamp(),
        });
      }
    }
    if (next === "completed") {
      const participants: string[] = booking.participants ?? [booking.userId];
      for (const playerId of [...new Set(participants)]) {
        const playerRef = db.collection("users").doc(playerId);
        tx.update(playerRef, {points: FieldValue.increment(40), xp: FieldValue.increment(150), updatedAt: FieldValue.serverTimestamp()});
        tx.create(playerRef.collection("pointsLedger").doc(), {type: "bookingCompleted", description: `Completed booking at ${booking.courtName}`, delta: 40, bookingId, createdAt: FieldValue.serverTimestamp()});
      }
      if (booking.matchId) {
        tx.update(db.collection("matches").doc(booking.matchId), {
          status: "completed",
          completedAt: FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
        });
      }
    }
    tx.update(ref, update);
    tx.create(db.collection("auditLogs").doc(), {actorId: uid, action: `booking.${next}`, entity: "booking", entityId: bookingId, academyId: booking.academyId, createdAt: FieldValue.serverTimestamp()});
  });
  return {ok: true};
});

export const joinMatch = onCall(callableOptions, async (request) => {
  const uid = requireAuth(request);
  const user = await profile(uid);
  const matchId = text(request.data?.matchId, "matchId");
  const ref = db.collection("matches").doc(matchId);
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const match = snap.data();
    if (!match || match.status !== "open") throw new HttpsError("failed-precondition", "Match is not open.");
    const bookingId = typeof match.bookingId === "string" ? match.bookingId.trim() : "";
    if (!bookingId) throw new HttpsError("failed-precondition", "This match listing has expired. Refresh the match list and choose an available match.");
    const bookingRef = db.collection("bookings").doc(bookingId);
    const bookingSnap = await tx.get(bookingRef);
    const booking = bookingSnap.data();
    const start = booking?.startUtc?.toDate?.();
    const end = booking?.endUtc?.toDate?.();
    if (!booking || booking.matchId !== matchId || !["pending", "confirmed"].includes(String(booking.status))
      || !(start instanceof Date) || !(end instanceof Date) || start <= new Date()) {
      throw new HttpsError("failed-precondition", "The match booking is no longer available.");
    }
    const userBookings = await tx.get(db.collection("bookings")
      .where("participants", "array-contains", uid)
      .where("startUtc", ">=", Timestamp.fromDate(new Date(start.valueOf() - 4 * 60 * 60_000)))
      .where("startUtc", "<", Timestamp.fromDate(end)));
    const players: string[] = match.players ?? [];
    if (players.includes(uid)) throw new HttpsError("already-exists", "You already joined this match.");
    const capacity = Number(match.capacity ?? 0);
    if (!Number.isInteger(capacity) || capacity < 2 || players.length >= capacity) {
      throw new HttpsError("resource-exhausted", "Match is full.");
    }
    const bookingParticipants: string[] = booking.participants ?? [booking.userId];
    if (bookingParticipants.includes(uid)) {
      throw new HttpsError("already-exists", "You already joined this match.");
    }
    const conflict = userBookings.docs.some(document => {
      if (document.id === bookingId) return false;
      const candidate = document.data();
      const candidateStart = candidate.startUtc?.toDate?.();
      const candidateEnd = candidate.endUtc?.toDate?.();
      return bookingIsActive(candidate)
        && candidateStart instanceof Date
        && candidateEnd instanceof Date
        && overlaps(start, end, candidateStart, candidateEnd);
    });
    if (conflict) {
      throw new HttpsError("already-exists", "This match conflicts with another booking or match.");
    }
    const nextPlayers = [...players, uid];
    const playerNames: string[] = match.playerNames ?? [];
    tx.update(ref, {
      players: nextPlayers,
      playerNames: [...playerNames, user.displayName ?? "Player"],
      neededPlayers: Math.max(0, capacity - nextPlayers.length),
      status: nextPlayers.length >= capacity ? "full" : "open",
      updatedAt: FieldValue.serverTimestamp(),
    });
    tx.update(bookingRef, {
      participants: FieldValue.arrayUnion(uid),
      updatedAt: FieldValue.serverTimestamp(),
    });
    tx.create(db.collection("notifications").doc(), {userId: match.hostId, type: "matchJoined", title: "A player joined your match", matchId, read: false, createdAt: FieldValue.serverTimestamp()});
  });
  return {ok: true};
});

export const sendFriendRequest = onCall(callableOptions, async (request) => {
  const uid = requireAuth(request);
  const sender = await profile(uid);
  const playerId = text(request.data?.playerId, "playerId");
  if (playerId === uid) throw new HttpsError("invalid-argument", "You cannot add yourself.");
  const recipientSnapshot = await db.collection("users").doc(playerId).get();
  const recipient = recipientSnapshot.data();
  if (!recipientSnapshot.exists || !recipient || recipient.suspended === true) {
    throw new HttpsError("not-found", "Player not found.");
  }
  if (recipient.privacyPreferences?.allowInvites === false) {
    throw new HttpsError("failed-precondition", "This player is not accepting invitations.");
  }
  const friendshipId = [uid, playerId].sort().join("_");
  const ref = db.collection("friendships").doc(friendshipId);
  await db.runTransaction(async tx => {
    if ((await tx.get(ref)).exists) {
      throw new HttpsError("already-exists", "A friend connection already exists.");
    }
    tx.create(ref, {
      members: [uid, playerId],
      requestedBy: uid,
      requestedTo: playerId,
      requesterName: sender.displayName ?? "Player",
      status: "pending",
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    tx.create(db.collection("notifications").doc(), {
      userId: playerId,
      type: "friendRequest",
      title: `${sender.displayName ?? "A player"} sent you a friend request`,
      friendshipId,
      read: false,
      createdAt: FieldValue.serverTimestamp(),
    });
  });
  return {friendshipId};
});

export const respondFriendRequest = onCall(callableOptions, async (request) => {
  const uid = requireAuth(request);
  await profile(uid);
  const friendshipId = text(request.data?.friendshipId, "friendshipId");
  const accept = request.data?.accept === true;
  const ref = db.collection("friendships").doc(friendshipId);
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const friendship = snap.data();
    if (!friendship || friendship.status !== "pending" || friendship.requestedTo !== uid) {
      throw new HttpsError("failed-precondition", "This request is no longer available.");
    }
    tx.update(ref, {
      status: accept ? "accepted" : "declined",
      respondedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
  });
  return {accepted: accept};
});

export const leaveMatch = onCall(callableOptions, async (request) => {
  const uid = requireAuth(request); await profile(uid);
  const matchId = text(request.data?.matchId, "matchId"); const ref = db.collection("matches").doc(matchId);
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref); const match = snap.data();
    if (!match || !["open", "full"].includes(String(match.status))) throw new HttpsError("failed-precondition", "Match cannot be left now.");
    if (match.hostId === uid) throw new HttpsError("failed-precondition", "The host must cancel the match instead.");
    const players: string[] = match.players ?? [];
    const index = players.indexOf(uid);
    if (index < 0) throw new HttpsError("failed-precondition", "You are not in this match.");
    const bookingId = text(match.bookingId, "bookingId");
    const bookingRef = db.collection("bookings").doc(bookingId);
    const booking = (await tx.get(bookingRef)).data();
    if (!booking || !["pending", "confirmed"].includes(String(booking.status))
      || booking.startUtc?.toDate?.() <= new Date()) {
      throw new HttpsError("failed-precondition", "The match can no longer be left.");
    }
    const nextPlayers = players.filter(playerId => playerId !== uid);
    const playerNames: string[] = match.playerNames ?? [];
    tx.update(ref, {
      players: nextPlayers,
      playerNames: playerNames.filter((_, playerIndex) => playerIndex !== index),
      neededPlayers: Math.max(0, Number(match.capacity ?? 0) - nextPlayers.length),
      status: "open",
      updatedAt: FieldValue.serverTimestamp(),
    });
    tx.update(bookingRef, {
      participants: FieldValue.arrayRemove(uid),
      updatedAt: FieldValue.serverTimestamp(),
    });
    tx.create(db.collection("notifications").doc(), {
      userId: match.hostId,
      type: "matchLeft",
      title: `${match.playerNames?.[index] ?? "A player"} left your match`,
      matchId,
      read: false,
      createdAt: FieldValue.serverTimestamp(),
    });
  }); return {ok: true};
});

export const sendMatchMessage = onCall(callableOptions, async (request) => {
  const uid = requireAuth(request); const user = await profile(uid);
  const matchId = text(request.data?.matchId, "matchId"); const body = text(request.data?.body, "message");
  if (body.length > 1000) throw new HttpsError("invalid-argument", "Message is too long.");
  const match = (await db.collection("matches").doc(matchId).get()).data();
  if (!match || !(match.players ?? []).includes(uid)) throw new HttpsError("permission-denied", "Join this match before chatting.");
  const ref = db.collection("matches").doc(matchId).collection("messages").doc();
  await ref.set({userId: uid, displayName: user.displayName ?? "Player", body, createdAt: FieldValue.serverTimestamp()});
  return {messageId: ref.id};
});

export const recordCashPayment = onCall(callableOptions, async (request) => {
  const uid = requireAuth(request); const user = await profile(uid);
  const bookingId = text(request.data?.bookingId, "bookingId"); const ref = db.collection("bookings").doc(bookingId);
  await db.runTransaction(async (tx) => { const snap = await tx.get(ref); const booking = snap.data();
    if (!booking) throw new HttpsError("not-found", "Booking not found.");
    const permissions: string[] = user.permissions ?? [];
    const academyAllowed = managesBooking(user, booking)
      && (["academyOwner", "courtOwner"].includes(user.role)
        || permissions.includes("academy.bookings.manage"));
    const allowed = user.role === "superAdmin"
      || permissions.includes("bookings.manage")
      || academyAllowed;
    if (!allowed) throw new HttpsError("permission-denied", "You cannot record this payment.");
    if (booking.paymentStatus === "collected") throw new HttpsError("already-exists", "Cash payment is already recorded.");
    const collectableMinor = booking.status === "cancelled"
      ? Number(booking.cancellationFeeMinor ?? 0)
      : Number(booking.totalMinor ?? 0);
    if (!Number.isInteger(collectableMinor) || collectableMinor <= 0
      || booking.paymentStatus === "notRequired") {
      throw new HttpsError("failed-precondition", "This booking has no cash amount to collect.");
    }
    const settlement = calculateSettlement(
      collectableMinor,
      Number(booking.platformCommissionBps ?? 0),
    );
    tx.update(ref, {
      paymentStatus: "collected",
      cashCollectedMinor: collectableMinor,
      cashCollectedBy: uid,
      cashCollectedAt: FieldValue.serverTimestamp(),
      ...settlement,
      settlementStatus: settlement.platformCommissionMinor > 0
        ? "academyOwesPlatform"
        : "settled",
      updatedAt: FieldValue.serverTimestamp(),
    });
    tx.create(db.collection("auditLogs").doc(), {
      actorId: uid,
      action: "booking.cashCollected",
      entity: "booking",
      entityId: bookingId,
      academyId: booking.academyId,
      amountMinor: collectableMinor,
      platformCommissionMinor: settlement.platformCommissionMinor,
      createdAt: FieldValue.serverTimestamp(),
    });
  }); return {ok: true};
});

export const settleBookingCommission = onCall(callableOptions, async (request) => {
  const uid = requireAuth(request);
  const user = await profile(uid);
  const permissions: string[] = user.permissions ?? [];
  if (user.role !== "superAdmin"
    && !permissions.includes("platform.manage")
    && !permissions.includes("bookings.manage")) {
    throw new HttpsError("permission-denied", "Platform finance access is required.");
  }
  const bookingId = text(request.data?.bookingId, "bookingId");
  const reference = typeof request.data?.reference === "string"
    ? request.data.reference.trim().slice(0, 120)
    : "";
  const ref = db.collection("bookings").doc(bookingId);
  await db.runTransaction(async tx => {
    const booking = (await tx.get(ref)).data();
    if (!booking) throw new HttpsError("not-found", "Booking not found.");
    if (booking.paymentStatus !== "collected") {
      throw new HttpsError("failed-precondition", "Cash must be collected before settlement.");
    }
    if (booking.settlementStatus === "settled") {
      throw new HttpsError("already-exists", "This booking is already settled.");
    }
    tx.update(ref, {
      settlementStatus: "settled",
      settlementReference: reference || null,
      settledBy: uid,
      settledAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    tx.create(db.collection("auditLogs").doc(), {
      actorId: uid,
      action: "booking.commissionSettled",
      entity: "booking",
      entityId: bookingId,
      academyId: booking.academyId,
      amountMinor: Number(booking.platformCommissionMinor ?? 0),
      reference: reference || null,
      createdAt: FieldValue.serverTimestamp(),
    });
  });
  return {ok: true};
});

export const createMatch = onCall(callableOptions, async (request) => {
  const uid = requireAuth(request);
  const user = await profile(uid);
  const sport = text(request.data?.sport, "sport");
  const title = text(request.data?.title, "title");
  const courtId = text(request.data?.courtId, "courtId");
  const start = date(request.data?.startUtc, "startUtc");
  const capacity = Number(request.data?.capacity);
  if (!Number.isInteger(capacity) || capacity < 2 || capacity > 30) {
    throw new HttpsError("invalid-argument", "Capacity must be 2–30.");
  }
  if (start <= new Date()) throw new HttpsError("invalid-argument", "Match must be in the future.");
  if (start.valueOf() % (30 * 60_000) !== 0) {
    throw new HttpsError("invalid-argument", "Match start time must use a 30-minute boundary.");
  }
  if (title.length > 100) throw new HttpsError("invalid-argument", "Match title is too long.");
  const end = new Date(start.getTime() + 60 * 60 * 1000);
  const ref = db.collection("matches").doc();
  const bookingRef = db.collection("bookings").doc();
  const courtRef = db.collection("courts").doc(courtId);
  const slotStarts = [start, new Date(start.valueOf() + 30 * 60_000)];
  const lockRefs = slotStarts.map(slot =>
    db.collection("bookingLocks").doc(`${courtId}_${slot.valueOf()}`),
  );
  await db.runTransaction(async (tx) => {
    const courtSnap = await tx.get(courtRef);
    const court = courtSnap.data();
    if (!court || court.active === false) throw new HttpsError("not-found", "Court is unavailable.");
    if (court.bookable === false) throw new HttpsError("failed-precondition", "Online booking is not available for this court yet. Contact the venue for pricing and availability.");
    if (court.sport && String(court.sport).toLowerCase() !== sport.toLowerCase()) {
      throw new HttpsError("invalid-argument", "The selected court does not support this sport.");
    }
    const [academySnap, platformSnap, userBookings, ...locks] = await Promise.all([
      tx.get(db.collection("academies").doc(String(court.academyId))),
      tx.get(db.collection("platformConfig").doc("general")),
      tx.get(db.collection("bookings")
        .where("participants", "array-contains", uid)
        .where("startUtc", ">=", Timestamp.fromDate(new Date(start.valueOf() - 4 * 60 * 60_000)))
        .where("startUtc", "<", Timestamp.fromDate(end))),
      ...lockRefs.map(lockRef => tx.get(lockRef)),
    ]);
    const academy = requireActiveAcademy(academySnap);
    if (locks.some(lock => lock.exists)) {
      throw new HttpsError("already-exists", "This court was just booked. Choose another court or time.");
    }
    const conflict = userBookings.docs.some(document => {
      const booking = document.data();
      const bookingStart = booking.startUtc?.toDate?.();
      const bookingEnd = booking.endUtc?.toDate?.();
      return bookingIsActive(booking)
        && bookingStart instanceof Date
        && bookingEnd instanceof Date
        && overlaps(start, end, bookingStart, bookingEnd);
    });
    if (conflict) {
      throw new HttpsError("already-exists", "This match conflicts with another booking or match.");
    }
    validateCourtBlocks(court, start, end);
    validateCourtHours(court, start, end);
    const price = bookingTotal(court, 60);
    const settlement = calculateSettlement(
      price.totalMinor,
      commissionBpsFor(court, academy, platformSnap.data() ?? {}),
    );
    lockRefs.forEach((lockRef, index) => {
      const slotStart = slotStarts[index];
      tx.create(lockRef, {
        bookingId: bookingRef.id, userId: uid, courtId,
        startUtc: Timestamp.fromDate(slotStart),
        endUtc: Timestamp.fromDate(new Date(slotStart.valueOf() + 30 * 60_000)),
        expiresAt: Timestamp.fromDate(end),
        createdAt: FieldValue.serverTimestamp(),
      });
    });
    tx.create(bookingRef, {
      userId: uid, academyId: court.academyId, courtId, courtName: court.name,
      sport, startUtc: Timestamp.fromDate(start), endUtc: Timestamp.fromDate(end),
      status: "pending", currency: court.currency ?? "JOD", ...price,
      paymentMethod: "cash", paymentStatus: "pending", matchmaking: true,
      ...settlement, settlementStatus: "notCollected",
      playerCapacity: capacity, participants: [uid], matchId: ref.id,
      durationMinutes: 60, lockIds: lockRefs.map(lockRef => lockRef.id),
      createdAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp(),
    });
    tx.create(ref, {
      hostId: uid, hostName: user.displayName ?? "Player", title, sport,
      academyId: court.academyId, courtId, courtName: court.name, bookingId: bookingRef.id,
      startUtc: Timestamp.fromDate(start), endUtc: Timestamp.fromDate(end),
      skillRange: text(request.data?.skill, "skill"),
      type: request.data?.type === "Competitive" ? "Competitive" : "Casual",
      ranked: request.data?.type === "Competitive", status: "open", capacity,
      currency: court.currency ?? "JOD", totalMinor: price.totalMinor,
      players: [uid], playerNames: [user.displayName ?? "Player"], neededPlayers: capacity - 1,
      latitude: typeof court.latitude === "number" ? court.latitude : null,
      longitude: typeof court.longitude === "number" ? court.longitude : null,
      createdAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp(),
    });
    tx.create(db.collection("auditLogs").doc(), {
      actorId: uid, action: "match.create", entity: "match", entityId: ref.id,
      academyId: court.academyId, bookingId: bookingRef.id,
      createdAt: FieldValue.serverTimestamp(),
    });
  });
  return {matchId: ref.id, bookingId: bookingRef.id};
});

export const listAvailableCourts = onCall(callableOptions, async (request) => {
  const uid = requireAuth(request);
  await profile(uid);
  const sport = text(request.data?.sport, "sport");
  const start = date(request.data?.startUtc, "startUtc");
  const end = new Date(start.getTime() + 60 * 60 * 1000);
  if (start <= new Date()) throw new HttpsError("invalid-argument", "Choose a future match time.");
  if (start.valueOf() % (30 * 60_000) !== 0) {
    throw new HttpsError("invalid-argument", "Match start time must use a 30-minute boundary.");
  }
  const courts = await db.collection("courts")
    .where("active", "==", true)
    .where("sport", "==", sport)
    .get();
  const academyAvailability = new Map<string, Promise<boolean>>();
  const available = await Promise.all(courts.docs.map(async (courtDoc) => {
    const court = courtDoc.data();
    if (court.bookable === false) return null;
    const academyId = String(court.academyId ?? "");
    if (!academyId) return null;
    if (!academyAvailability.has(academyId)) {
      academyAvailability.set(
        academyId,
        db.collection("academies").doc(academyId).get()
          .then(snapshot => snapshot.data()?.status === "active"),
      );
    }
    if (!await academyAvailability.get(academyId)!) return null;
    try {
      validateCourtBlocks(court, start, end);
      validateCourtHours(court, start, end);
    } catch {
      return null;
    }
    const lockIds = [start, new Date(start.valueOf() + 30 * 60_000)]
      .map(slot => `${courtDoc.id}_${slot.valueOf()}`);
    const locks = await db.getAll(...lockIds.map(id => db.collection("bookingLocks").doc(id)));
    return locks.some(lock => lock.exists) ? null : courtDoc.id;
  }));
  return {courtIds: available.filter((id): id is string => id !== null)};
});

export const listCourtUnavailableSlots = onCall(callableOptions, async (request) => {
  const uid = requireAuth(request);
  await profile(uid);
  const courtId = text(request.data?.courtId, "courtId");
  const rangeStart = date(request.data?.rangeStartUtc, "rangeStartUtc");
  const rangeEnd = date(request.data?.rangeEndUtc, "rangeEndUtc");
  const rangeMs = rangeEnd.valueOf() - rangeStart.valueOf();
  if (rangeMs <= 0 || rangeMs > 8 * 24 * 60 * 60_000) {
    throw new HttpsError("invalid-argument", "Availability range must be between one minute and eight days.");
  }
  const court = (await db.collection("courts").doc(courtId).get()).data();
  if (!court || court.active !== true) {
    throw new HttpsError("not-found", "Court is unavailable.");
  }
  if (court.bookable === false) {
    throw new HttpsError("failed-precondition", "Online booking is not available for this court yet. Contact the venue for pricing and availability.");
  }
  requireActiveAcademy(
    await db.collection("academies").doc(String(court.academyId ?? "")).get(),
  );
  const locks = await db.collection("bookingLocks")
    .where("courtId", "==", courtId)
    .where("startUtc", ">=", Timestamp.fromDate(rangeStart))
    .where("startUtc", "<", Timestamp.fromDate(rangeEnd))
    .get();
  return {
    unavailableStartUtc: locks.docs
      .map(lock => (lock.data().startUtc as Timestamp | undefined)?.toDate().toISOString())
      .filter((value): value is string => Boolean(value)),
  };
});

export const createTournament = onCall(callableOptions, async (request) => {
  const uid = requireAuth(request);
  const actor = await profile(uid);
  const canCreate = actor.role === 'academyOwner'
    || (actor.role === 'academyStaff'
      && Array.isArray(actor.permissions)
      && actor.permissions.includes('academy.tournaments.manage'));
  if (!canCreate || !actor.academyId) {
    throw new HttpsError('permission-denied', 'Academy access is required.');
  }
  const name = text(request.data?.name, 'name');
  const sport = text(request.data?.sport, 'sport');
  const format = text(request.data?.format, 'format');
  if (!['singleElimination', 'doubleElimination', 'roundRobin', 'groupKnockout'].includes(format)) {
    throw new HttpsError('invalid-argument', 'Tournament format is invalid.');
  }
  const teamSize = Number(request.data?.teamSize);
  const maxEntries = Number(request.data?.maxEntries);
  if (!Number.isInteger(teamSize) || teamSize < 1 || teamSize > 30) throw new HttpsError('invalid-argument', 'Team size must be 1–30.');
  if (!Number.isInteger(maxEntries) || maxEntries < 2 || maxEntries > 256) throw new HttpsError('invalid-argument', 'Maximum entries must be 2–256.');
  const startsAt = date(request.data?.startsAt, 'startsAt');
  const registrationEndsAt = date(request.data?.registrationEndsAt, 'registrationEndsAt');
  if (registrationEndsAt <= new Date() || startsAt <= registrationEndsAt) throw new HttpsError('invalid-argument', 'Registration must close before the tournament starts.');
  const ref = db.collection('tournaments').doc();
  await ref.set({name, sport, format, teamSize, maxEntries, registrationCount: 0,
    participantType: teamSize === 1 ? 'individual' : 'team', academyId: actor.academyId,
    startsAt: Timestamp.fromDate(startsAt), registrationEndsAt: Timestamp.fromDate(registrationEndsAt),
    rules: typeof request.data?.rules === 'string' ? request.data.rules.trim() : '',
    imageUrl: typeof request.data?.imageUrl === 'string' ? request.data.imageUrl.trim() : '',
    status: 'registrationOpen', createdBy: uid, createdAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp()});
  return {tournamentId: ref.id};
});

export const registerTournament = onCall(callableOptions, async (request) => {
  const uid = requireAuth(request);
  await profile(uid);
  const tournamentId = text(request.data?.tournamentId, 'tournamentId');
  const ref = db.collection('tournaments').doc(tournamentId);
  const registrationRef = ref.collection('registrations').doc(uid);
  await db.runTransaction(async (tx) => {
    const [tournamentSnap, registrationSnap] = await Promise.all([tx.get(ref), tx.get(registrationRef)]);
    const tournament = tournamentSnap.data();
    if (!tournament || tournament.status !== 'registrationOpen') throw new HttpsError('failed-precondition', 'Registration is closed.');
    if (registrationSnap.exists) throw new HttpsError('already-exists', 'You are already registered.');
    if ((tournament.registrationEndsAt as Timestamp).toDate() <= new Date()) throw new HttpsError('failed-precondition', 'Registration has ended.');
    if ((tournament.registrationCount ?? 0) >= tournament.maxEntries) throw new HttpsError('resource-exhausted', 'Tournament is full.');
    tx.create(registrationRef, {userId: uid, teamName: typeof request.data?.teamName === 'string' ? request.data.teamName.trim() : '',
      roster: Array.isArray(request.data?.roster) ? request.data.roster.slice(0, tournament.teamSize) : [],
      paymentMethod: 'cash', paymentStatus: 'pending', status: 'registered', createdAt: FieldValue.serverTimestamp()});
    tx.update(ref, {registrationCount: FieldValue.increment(1), updatedAt: FieldValue.serverTimestamp()});
  });
  return {ok: true, paymentStatus: 'pending'};
});

export const seedUat = onCall(callableOptions, async (request) => {
  requireUatProject();
  const uid = requireAuth(request);
  const user = await profile(uid);
  if (user.role !== "superAdmin") throw new HttpsError("permission-denied", "Super administrator required.");
  const academyA = db.collection("academies").doc("uat-academy-a");
  const academyB = db.collection("academies").doc("uat-academy-b");
  const batch = db.batch();
  batch.set(academyA, {name: "Amman North Academy", status: "active", currency: "JOD", createdAt: FieldValue.serverTimestamp()});
  batch.set(academyB, {name: "Amman South Academy", status: "active", currency: "JOD", createdAt: FieldValue.serverTimestamp()});
  batch.set(db.collection("courts").doc("uat-court-a1"), {academyId: academyA.id, name: "North Padel 1", sport: "Padel", active: true, basePriceMinor: 1800, currency: "JOD", openingHour: 6, closingHour: 23, timezone: "Asia/Amman", blockedPeriods: [], maintenancePeriods: [], createdAt: FieldValue.serverTimestamp()});
  batch.set(db.collection("courts").doc("uat-court-b1"), {academyId: academyB.id, name: "South Basketball 1", sport: "Basketball", active: true, basePriceMinor: 2100, currency: "JOD", openingHour: 6, closingHour: 23, timezone: "Asia/Amman", blockedPeriods: [], maintenancePeriods: [], createdAt: FieldValue.serverTimestamp()});
  batch.set(db.collection("sports").doc("padel"), {name: "Padel", active: true});
  batch.set(db.collection("sports").doc("basketball"), {name: "Basketball", active: true});
  batch.set(db.collection("promotions").doc("uat-welcome"), {code: "UATWELCOME", active: true, discountType: "percentage", discountValue: 10, usageLimit: 100, usageCount: 0, startsAt: Timestamp.fromDate(new Date("2026-01-01T00:00:00Z")), endsAt: Timestamp.fromDate(new Date("2027-12-31T23:59:59Z"))});
  batch.set(db.collection("auditLogs").doc(), {actorId: uid, action: "uat.seed", entity: "platform", entityId: "uat", createdAt: FieldValue.serverTimestamp()});
  await batch.commit();
  return {ok: true, academies: 2, courts: 2};
});

export const createUatUser = onCall(callableOptions, async (request) => {
  requireUatProject();
  const uid = requireAuth(request);
  const actor = await profile(uid);
  if (actor.role !== "superAdmin") throw new HttpsError("permission-denied", "Super administrator required.");
  const email = text(request.data?.email, "email").toLowerCase();
  const displayName = text(request.data?.displayName, "displayName");
  const role = text(request.data?.role, "role");
  const allowedRoles = ["platformAdmin", "academyOwner", "courtOwner", "academyStaff", "player"];
  if (!allowedRoles.includes(role)) throw new HttpsError("invalid-argument", "Role is invalid.");
  const password = text(request.data?.temporaryPassword, "temporaryPassword");
  if (password.length < 12) throw new HttpsError("invalid-argument", "Temporary password must have at least 12 characters.");
  const created = await getAuth().createUser({email, displayName, password, emailVerified: true});
  await db.collection("users").doc(created.uid).set({uid: created.uid, email, displayName, role, permissions: Array.isArray(request.data?.permissions) ? request.data.permissions : [], academyId: request.data?.academyId ?? null, suspended: false, mustChangePassword: true, createdAt: FieldValue.serverTimestamp()});
  return {uid: created.uid};
});

export const createAcademyStaff = onCall(callableOptions, async (request) => {
  const uid = requireAuth(request); const actor = await profile(uid);
  if (actor.role !== "academyOwner" || !actor.academyId) throw new HttpsError("permission-denied", "Academy owner access is required.");
  const email = text(request.data?.email, "email").toLowerCase(); const displayName = text(request.data?.displayName, "displayName");
  const allowed = ["academy.bookings.manage", "academy.bookings.checkin", "academy.courts.manage", "academy.pricing.manage", "academy.profile.manage", "academy.reports.view", "academy.tournaments.manage"];
  const permissions = Array.isArray(request.data?.permissions) ? request.data.permissions.filter((item: unknown) => typeof item === "string" && allowed.includes(item)) : [];
  const password = randomBytes(32).toString("base64url");
  const created = await getAuth().createUser({email, displayName, password, emailVerified: false});
  try {
    await db.collection("users").doc(created.uid).set({uid: created.uid, email, displayName, role: "academyStaff", academyId: actor.academyId, permissions, suspended: false, mustChangePassword: false, createdAt: FieldValue.serverTimestamp()});
    await db.collection("auditLogs").add({actorId: uid, action: "academy.staff.create", entity: "user", entityId: created.uid, academyId: actor.academyId, createdAt: FieldValue.serverTimestamp()});
  } catch (error) {
    await getAuth().deleteUser(created.uid).catch(() => undefined);
    throw error;
  }
  return {uid: created.uid};
});

export const createManagedOwnerAccount = onCall(callableOptions, async (request) => {
  const uid = requireAuth(request);
  const actor = await profile(uid);
  if (actor.role !== 'superAdmin' && !(actor.role === 'platformAdmin' && Array.isArray(actor.permissions) && actor.permissions.includes('users.manage'))) {
    throw new HttpsError('permission-denied', 'Platform administrator access is required.');
  }
  const email = text(request.data?.email, 'email').toLowerCase();
  const displayName = text(request.data?.displayName, 'displayName');
  const academyId = text(request.data?.academyId, 'academyId');
  const ownerType = request.data?.ownerType === 'court' ? 'court' : 'academy';
  const courtId = ownerType === 'court' ? text(request.data?.courtId, 'courtId') : null;
  const academy = await db.collection('academies').doc(academyId).get();
  if (!academy.exists) throw new HttpsError('not-found', 'Academy does not exist.');
  if (courtId) {
    const court = await db.collection('courts').doc(courtId).get();
    if (!court.exists || court.data()?.academyId !== academyId) {
      throw new HttpsError('invalid-argument', 'The selected court does not belong to this academy.');
    }
  }
  const temporaryPassword = randomBytes(32).toString('base64url');
  let created;
  try {
    created = await getAuth().createUser({email, displayName, password: temporaryPassword, emailVerified: false});
    await db.collection('users').doc(created.uid).set({
      uid: created.uid, email, displayName,
      role: ownerType === 'court' ? 'courtOwner' : 'academyOwner', ownerType,
      academyId, courtIds: courtId ? [courtId] : [], permissions: [], suspended: false,
      mustChangePassword: false, createdBy: uid, createdAt: FieldValue.serverTimestamp(),
    });
    await db.collection('auditLogs').add({actorId: uid, action: 'owner.create', entity: 'user',
      entityId: created.uid, academyId, ownerType, courtId, createdAt: FieldValue.serverTimestamp()});
  } catch (error) {
    if (created?.uid) await getAuth().deleteUser(created.uid).catch(() => undefined);
    if ((error as {code?: string}).code === 'auth/email-already-exists') {
      throw new HttpsError('already-exists', 'An account already uses this email.');
    }
    throw error;
  }
  return {uid: created.uid, email, resetRequired: true};
});

export const deleteMyAccount = onCall({...callableOptions, timeoutSeconds: 120}, async (request) => {
  const uid = requireAnyAuth(request);
  await profile(uid, true);
  const writer = db.bulkWriter();
  const deleteQuery = async (query: FirebaseFirestore.Query) => {
    const snapshot = await query.get();
    snapshot.docs.forEach((document) => writer.delete(document.ref));
  };
  const [ownedBookings, participatedBookings, matches] = await Promise.all([
    db.collection("bookings").where("userId", "==", uid).get(),
    db.collection("bookings").where("participants", "array-contains", uid).get(),
    db.collection("matches").where("players", "array-contains", uid).get(),
    deleteQuery(db.collection("friendships").where("members", "array-contains", uid)),
    deleteQuery(db.collection("notifications").where("userId", "==", uid)),
    deleteQuery(db.collection("supportTickets").where("userId", "==", uid)),
    deleteQuery(db.collection("reviews").where("userId", "==", uid)),
    deleteQuery(db.collection("redemptions").where("userId", "==", uid)),
    deleteQuery(db.collection("promotionUses").where("userId", "==", uid)),
    deleteQuery(db.collection("bookingInvites").where("createdBy", "==", uid)),
  ]);
  const bookings = new Map([
    ...ownedBookings.docs,
    ...participatedBookings.docs,
  ].map(document => [document.id, document]));
  bookings.forEach((document) => writer.update(document.ref, {
    ...(document.data().userId === uid ? {userId: "deleted-user"} : {}),
    participants: FieldValue.arrayRemove(uid),
    accountDeleted: true,
    updatedAt: FieldValue.serverTimestamp(),
  }));
  await Promise.all(matches.docs.map(document =>
    deleteQuery(document.ref.collection("messages").where("userId", "==", uid)),
  ));
  matches.docs.forEach((document) => {
    const data = document.data();
    const players: string[] = data.players ?? [];
    const playerNames: string[] = data.playerNames ?? [];
    const remainingNames = playerNames.filter((_, index) => players[index] !== uid);
    const remainingCount = players.filter(playerId => playerId !== uid).length;
    writer.update(document.ref, {
      players: FieldValue.arrayRemove(uid),
      playerNames: remainingNames,
      neededPlayers: Math.max(0, Number(data.capacity ?? 0) - remainingCount),
      ...(data.hostId === uid ? {hostId: "deleted-user", hostName: "Deleted player"} : {}),
      accountDeleted: true,
      updatedAt: FieldValue.serverTimestamp(),
    });
  });
  writer.delete(db.collection("publicProfiles").doc(uid));
  writer.delete(db.collection("dashboardLayouts").doc(uid));
  await writer.close();
  await db.collection("auditLogs").add({
    actorId: uid,
    action: "account.deleted",
    entity: "user",
    entityId: uid,
    createdAt: FieldValue.serverTimestamp(),
  });
  await db.recursiveDelete(db.collection("users").doc(uid));
  await getAuth().deleteUser(uid);
  return {ok: true};
});

export const notifyBookingCreated = onDocumentCreated("bookings/{bookingId}", async (event) => {
  const booking = event.data?.data();
  if (!booking) return;
  const batch = db.batch();
  batch.set(db.collection("notifications").doc(), {userId: booking.userId, type: "bookingCreated", title: "Booking requested - cash payment pending", bookingId: event.params.bookingId, read: false, createdAt: FieldValue.serverTimestamp()});
  const owners = await db.collection("users").where("academyId", "==", booking.academyId).where("role", "in", ["academyOwner", "courtOwner", "academyStaff"]).get();
  for (const owner of owners.docs) {
    const ownerData = owner.data();
    if (ownerData.role === "courtOwner" && !(ownerData.courtIds ?? []).includes(booking.courtId)) continue;
    if (ownerData.role === "academyStaff"
      && !(ownerData.permissions ?? []).some((permission: string) => [
        "academy.bookings.manage",
        "academy.bookings.checkin",
      ].includes(permission))) continue;
    batch.set(db.collection("notifications").doc(), {userId: owner.id, type: "academyBookingCreated", title: `New cash booking for ${booking.courtName}`, bookingId: event.params.bookingId, academyId: booking.academyId, courtId: booking.courtId, read: false, createdAt: FieldValue.serverTimestamp()});
  }
  await batch.commit();
});

export const sendBookingReminders = onSchedule("every 15 minutes", async () => {
  const now = Date.now();
  const windowStart = new Date(now + 45 * 60_000);
  const windowEnd = new Date(now + 75 * 60_000);
  const bookings = await db.collection("bookings")
    .where("startUtc", ">=", Timestamp.fromDate(windowStart))
    .where("startUtc", "<=", Timestamp.fromDate(windowEnd))
    .get();

  for (const bookingDoc of bookings.docs) {
    const booking = bookingDoc.data();
    if (!["pending", "confirmed"].includes(booking.status)) continue;
    const participants = Array.from(new Set<string>(booking.participants ?? [booking.userId])).filter(Boolean);
    const start = (booking.startUtc as Timestamp).toDate();
    const title = "Booking starts soon";
    const body = `${booking.courtName ?? "Your court"} starts at ${start.toLocaleTimeString("en-US", {hour: "numeric", minute: "2-digit"})}`;

    await Promise.all(participants.map(async (userId) => {
      const userRef = db.collection("users").doc(userId);
      const user = (await userRef.get()).data();
      if (!user || user.notificationPreferences?.bookingReminders === false) return;
      const reminderRef = db.collection("notifications").doc(`${bookingDoc.id}_${userId}_60m`);
      const created = await db.runTransaction(async (tx) => {
        const existing = await tx.get(reminderRef);
        if (existing.exists) return false;
        tx.create(reminderRef, {
          userId,
          type: "bookingReminder",
          title,
          body,
          bookingId: bookingDoc.id,
          startUtc: booking.startUtc,
          read: false,
          createdAt: FieldValue.serverTimestamp(),
        });
        return true;
      });
      if (!created) return;

      const tokens = Array.from(new Set<string>(user?.fcmTokens ?? [])).filter(Boolean);
      if (tokens.length === 0) return;
      const response = await getMessaging().sendEachForMulticast({
        tokens: tokens.slice(0, 500),
        notification: {title, body},
        data: {type: "bookingReminder", bookingId: bookingDoc.id},
      }).catch(() => null);
      if (!response) return;
      const invalidTokens = response.responses.flatMap((result, index) => {
        const code = result.error?.code ?? "";
        return !result.success && [
          "messaging/registration-token-not-registered",
          "messaging/invalid-registration-token",
        ].includes(code) ? [tokens[index]] : [];
      });
      if (invalidTokens.length > 0) {
        await userRef.update({
          fcmTokens: FieldValue.arrayRemove(...invalidTokens),
          updatedAt: FieldValue.serverTimestamp(),
        }).catch(() => undefined);
      }
    }));
  }
});

export const closeStartedMatches = onSchedule("every 5 minutes", async () => {
  const snapshot = await db.collection("matches")
    .where("status", "in", ["open", "full"])
    .where("startUtc", "<=", Timestamp.now())
    .limit(500)
    .get();
  if (snapshot.empty) return;
  const batch = db.batch();
  snapshot.docs.forEach(document => {
    batch.update(document.ref, {
      status: "started",
      startedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
  });
  await batch.commit();
});

export const expirePendingBookings = onSchedule("every 5 minutes", async () => {
  const snapshot = await db.collection("bookings")
    .where("status", "==", "pending")
    .where("startUtc", "<=", Timestamp.now())
    .limit(500)
    .get();
  if (snapshot.empty) return;
  const writer = db.bulkWriter();
  for (const document of snapshot.docs) {
    const booking = document.data();
    const cashAlreadyCollected = booking.paymentStatus === "collected";
    writer.update(document.ref, {
      status: "cancelled",
      cancellationReason: "Expired before venue confirmation",
      cancelledBy: "system",
      cancelledAt: FieldValue.serverTimestamp(),
      // Cash already collected at check-in on a booking still pending venue confirmation
      // must keep its settlement snapshot intact for reconciliation instead of being zeroed.
      ...(cashAlreadyCollected ? {} : {
        paymentStatus: "notRequired",
        grossMinor: 0,
        platformCommissionMinor: 0,
        academyNetMinor: 0,
        settlementStatus: "void",
      }),
      updatedAt: FieldValue.serverTimestamp(),
    });
    for (const lockId of booking.lockIds ?? []) {
      writer.delete(db.collection("bookingLocks").doc(String(lockId)));
    }
    if (booking.matchId) {
      writer.update(db.collection("matches").doc(String(booking.matchId)), {
        status: "cancelled",
        cancelledAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });
    }
    for (const playerId of [...new Set<string>(booking.participants ?? [booking.userId])]) {
      writer.create(db.collection("notifications").doc(), {
        userId: playerId,
        type: "bookingExpired",
        title: booking.matchId ? "Match cancelled: venue did not confirm" : "Booking request expired",
        bookingId: document.id,
        matchId: booking.matchId ?? null,
        read: false,
        createdAt: FieldValue.serverTimestamp(),
      });
    }
  }
  await writer.close();
});

export const submitMatchScore = onCall(callableOptions, async (request) => {
  const uid = requireAuth(request);
  await profile(uid);
  const matchId = text(request.data?.matchId, "matchId");
  const teamAScore = Number(request.data?.teamAScore ?? 0);
  const teamBScore = Number(request.data?.teamBScore ?? 0);
  const sets = Array.isArray(request.data?.sets) ? request.data.sets.map(String) : [];
  const ref = db.collection("matches").doc(matchId);
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const match = snap.data();
    if (!match) throw new HttpsError("not-found", "Match not found.");
    const players: string[] = match.players ?? [];
    if (match.hostId !== uid && !players.includes(uid)) {
      throw new HttpsError("permission-denied", "You must be a match participant to submit scores.");
    }
    if (match.status === "cancelled") {
      throw new HttpsError("failed-precondition", "Cannot score a cancelled match.");
    }
    tx.update(ref, {
      score: { teamAScore, teamBScore, sets },
      scoreSubmittedBy: uid,
      scoreStatus: "pendingConfirmation",
      updatedAt: FieldValue.serverTimestamp(),
    });
  });
  return { success: true };
});

export const confirmMatchScore = onCall(callableOptions, async (request) => {
  const uid = requireAuth(request);
  await profile(uid);
  const matchId = text(request.data?.matchId, "matchId");
  const accept = request.data?.accept === true;
  const ref = db.collection("matches").doc(matchId);
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const match = snap.data();
    if (!match) throw new HttpsError("not-found", "Match not found.");
    if (match.scoreStatus !== "pendingConfirmation") {
      throw new HttpsError("failed-precondition", "No score is currently pending confirmation.");
    }
    if (match.scoreSubmittedBy === uid) {
      throw new HttpsError("failed-precondition", "An opponent or other participant must confirm the score.");
    }
    const players: string[] = match.players ?? [];
    if (match.hostId !== uid && !players.includes(uid)) {
      throw new HttpsError("permission-denied", "Only participants can confirm scores.");
    }
    if (!accept) {
      tx.update(ref, {
        scoreStatus: "disputed",
        scoreDisputedBy: uid,
        updatedAt: FieldValue.serverTimestamp(),
      });
      return;
    }
    const score = match.score ?? {};
    const teamAScore = Number(score.teamAScore ?? 0);
    const teamBScore = Number(score.teamBScore ?? 0);
    const teamAWon = teamAScore >= teamBScore;

    tx.update(ref, {
      scoreStatus: "confirmed",
      scoreConfirmedBy: uid,
      status: "completed",
      completedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });

    const hostId = match.hostId;
    if (hostId) {
      const hostRef = db.collection("users").doc(hostId);
      const hostSnap = await tx.get(hostRef);
      const hostData = hostSnap.data();
      if (hostData) {
        const currentRating = Number(hostData.rating ?? 0);
        const { aDelta } = calculateRatingDelta(currentRating, 2.5, teamAWon);
        const newRating = Math.max(1.0, Math.min(7.0, Number((currentRating > 0 ? currentRating + aDelta : (teamAWon ? 3.0 : 2.5)).toFixed(2))));
        const won = teamAWon;
        const currentMatches = Number(hostData.matches ?? 0) + 1;
        const currentWins = Math.round((Number(hostData.winRate ?? 0) / 100) * (currentMatches - 1)) + (won ? 1 : 0);
        const newWinRate = Math.round((currentWins / currentMatches) * 100);
        tx.update(hostRef, {
          rating: newRating,
          xp: FieldValue.increment(won ? 150 : 75),
          points: FieldValue.increment(won ? 40 : 20),
          matches: currentMatches,
          winRate: newWinRate,
          updatedAt: FieldValue.serverTimestamp(),
        });
      }
    }
  });
  return { success: true };
});

export const updateCashSplitStatus = onCall(callableOptions, async (request) => {
  const uid = requireAuth(request);
  const bookingId = text(request.data?.bookingId, "bookingId");
  const playerId = text(request.data?.playerId, "playerId");
  const paid = request.data?.paid === true;
  const ref = db.collection("bookings").doc(bookingId);
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const booking = snap.data();
    if (!booking) throw new HttpsError("not-found", "Booking not found.");
    if (booking.userId !== uid) {
      throw new HttpsError("permission-denied", "Only the booking host can update cash split records.");
    }
    const paidPlayers: string[] = Array.isArray(booking.cashPaidPlayers) ? booking.cashPaidPlayers : [booking.userId];
    let nextPaid: string[];
    if (paid) {
      nextPaid = [...new Set([...paidPlayers, playerId])];
    } else {
      nextPaid = paidPlayers.filter(id => id !== playerId);
    }
    tx.update(ref, {
      cashPaidPlayers: nextPaid,
      updatedAt: FieldValue.serverTimestamp(),
    });
  });
  return { success: true };
});
