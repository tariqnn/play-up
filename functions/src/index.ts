import {initializeApp} from "firebase-admin/app";
import {FieldValue, Timestamp, getFirestore} from "firebase-admin/firestore";
import {getAuth} from "firebase-admin/auth";
import {HttpsError, onCall} from "firebase-functions/v2/https";
import {onDocumentCreated} from "firebase-functions/v2/firestore";
import {setGlobalOptions} from "firebase-functions/v2/options";
import {assertTransition, calculateTotal, overlaps} from "./domain";

initializeApp();
setGlobalOptions({region: "me-central1", maxInstances: 20});
const db = getFirestore();

function requireAuth(request: {auth?: {uid: string} | null}): string {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign in is required.");
  return request.auth.uid;
}

async function profile(uid: string) {
  const snap = await db.collection("users").doc(uid).get();
  const data = snap.data();
  if (!data || data.suspended === true) throw new HttpsError("permission-denied", "Account is unavailable.");
  return data;
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

export const quoteBooking = onCall(async (request) => {
  requireAuth(request);
  const courtId = text(request.data?.courtId, "courtId");
  const start = date(request.data?.startUtc, "startUtc");
  const end = date(request.data?.endUtc, "endUtc");
  const court = (await db.collection("courts").doc(courtId).get()).data();
  if (!court || court.active === false) throw new HttpsError("not-found", "Court is unavailable.");
  const durationMinutes = Math.round((end.valueOf() - start.valueOf()) / 60000);
  let promotion: FirebaseFirestore.DocumentData | undefined;
  const promotionCode = typeof request.data?.promotionCode === "string" ? request.data.promotionCode.trim().toUpperCase() : "";
  if (promotionCode) {
    const result = await db.collection("promotions").where("code", "==", promotionCode).where("active", "==", true).limit(1).get();
    promotion = result.docs[0]?.data();
    if (!promotion) throw new HttpsError("failed-precondition", "Promotion is invalid or inactive.");
    const now = new Date();
    if (promotion.startsAt?.toDate() > now || promotion.endsAt?.toDate() < now) throw new HttpsError("failed-precondition", "Promotion is outside its valid dates.");
    if (promotion.academyId && promotion.academyId !== court.academyId) throw new HttpsError("failed-precondition", "Promotion does not apply to this academy.");
  }
  return {
    currency: court.currency ?? "AED",
    ...calculateTotal({
      basePriceMinor: court.basePriceMinor,
      durationMinutes,
      discountType: promotion?.discountType,
      discountValue: promotion?.discountValue,
    }),
  };
});

export const createBooking = onCall(async (request) => {
  const uid = requireAuth(request);
  await profile(uid);
  const courtId = text(request.data?.courtId, "courtId");
  const start = date(request.data?.startUtc, "startUtc");
  const end = date(request.data?.endUtc, "endUtc");
  if (start <= new Date() || end <= start) throw new HttpsError("invalid-argument", "Choose a future time range.");
  const durationMinutes = Math.round((end.valueOf() - start.valueOf()) / 60000);
  if (durationMinutes < 30 || durationMinutes > 240) throw new HttpsError("invalid-argument", "Booking duration must be 30–240 minutes.");
  const courtRef = db.collection("courts").doc(courtId);
  const bookingRef = db.collection("bookings").doc();
  const lockRef = db.collection("bookingLocks").doc(`${courtId}_${start.valueOf()}`);
  return db.runTransaction(async (tx) => {
    const [courtSnap, lockSnap] = await Promise.all([tx.get(courtRef), tx.get(lockRef)]);
    const court = courtSnap.data();
    if (!court || court.active === false) throw new HttpsError("not-found", "Court is unavailable.");
    if (lockSnap.exists) throw new HttpsError("already-exists", "This slot was just booked.");
    for (const period of [...(court.blockedPeriods ?? []), ...(court.maintenancePeriods ?? [])]) {
      if (overlaps(start, end, period.start.toDate(), period.end.toDate())) throw new HttpsError("failed-precondition", "This period is blocked or under maintenance.");
    }
    const openingHour = Number(court.openingHour ?? 0);
    const closingHour = Number(court.closingHour ?? 24);
    if (start.getUTCHours() < openingHour || end.getUTCHours() > closingHour) throw new HttpsError("failed-precondition", "Court is closed at this time.");
    const price = calculateTotal({basePriceMinor: court.basePriceMinor, durationMinutes});
    const record = {
      userId: uid, academyId: court.academyId, courtId, courtName: court.name,
      sport: court.sport, startUtc: Timestamp.fromDate(start), endUtc: Timestamp.fromDate(end),
      status: "confirmed", currency: court.currency ?? "AED", ...price,
      paymentMethod: "payAtVenue", paymentStatus: "notCollected",
      createdAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp(),
    };
    tx.create(lockRef, {bookingId: bookingRef.id, userId: uid, courtId, startUtc: record.startUtc, endUtc: record.endUtc, createdAt: FieldValue.serverTimestamp()});
    tx.create(bookingRef, record);
    tx.create(db.collection("auditLogs").doc(), {actorId: uid, action: "booking.create", entity: "booking", entityId: bookingRef.id, academyId: court.academyId, createdAt: FieldValue.serverTimestamp()});
    return {bookingId: bookingRef.id, ...price, currency: record.currency};
  });
});

export const transitionBooking = onCall(async (request) => {
  const uid = requireAuth(request);
  const user = await profile(uid);
  const bookingId = text(request.data?.bookingId, "bookingId");
  const next = text(request.data?.status, "status");
  const ref = db.collection("bookings").doc(bookingId);
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const booking = snap.data();
    if (!booking) throw new HttpsError("not-found", "Booking not found.");
    const permissions: string[] = user.permissions ?? [];
    const platform = user.role === "superAdmin" || permissions.includes("bookings.manage");
    const academy = ["academyOwner", "academyStaff"].includes(user.role) && user.academyId === booking.academyId && (user.role === "academyOwner" || permissions.includes("academy.bookings.manage") || (next === "checkedIn" && permissions.includes("academy.bookings.checkin")));
    const playerCancel = booking.userId === uid && next === "cancelled";
    if (!platform && !academy && !playerCancel) throw new HttpsError("permission-denied", "You cannot change this booking.");
    try { assertTransition(booking.status, next); } catch (error) { throw new HttpsError("failed-precondition", (error as Error).message); }
    tx.update(ref, {status: next, updatedAt: FieldValue.serverTimestamp(), [`${next}At`]: FieldValue.serverTimestamp()});
    tx.create(db.collection("auditLogs").doc(), {actorId: uid, action: `booking.${next}`, entity: "booking", entityId: bookingId, academyId: booking.academyId, createdAt: FieldValue.serverTimestamp()});
  });
  return {ok: true};
});

export const joinMatch = onCall(async (request) => {
  const uid = requireAuth(request);
  await profile(uid);
  const matchId = text(request.data?.matchId, "matchId");
  const ref = db.collection("matches").doc(matchId);
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const match = snap.data();
    if (!match || match.status !== "open") throw new HttpsError("failed-precondition", "Match is not open.");
    const players: string[] = match.players ?? [];
    if (players.includes(uid)) throw new HttpsError("already-exists", "You already joined this match.");
    if (players.length >= match.capacity) throw new HttpsError("resource-exhausted", "Match is full.");
    tx.update(ref, {players: FieldValue.arrayUnion(uid), neededPlayers: FieldValue.increment(-1), updatedAt: FieldValue.serverTimestamp()});
    tx.create(db.collection("notifications").doc(), {userId: match.hostId, type: "matchJoined", title: "A player joined your match", matchId, read: false, createdAt: FieldValue.serverTimestamp()});
  });
  return {ok: true};
});

export const createMatch = onCall(async (request) => {
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
  const court = (await db.collection("courts").doc(courtId).get()).data();
  if (!court || court.active === false) throw new HttpsError("not-found", "Court is unavailable.");
  const ref = db.collection("matches").doc();
  await ref.set({
    hostId: uid, hostName: user.displayName ?? "Player", title, sport,
    academyId: court.academyId, courtId, courtName: court.name,
    startUtc: Timestamp.fromDate(start), skillRange: text(request.data?.skill, "skill"),
    type: request.data?.type === "Ranked" ? "Ranked" : "Casual",
    ranked: request.data?.type === "Ranked", status: "open", capacity,
    players: [uid], neededPlayers: capacity - 1,
    createdAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp(),
  });
  return {matchId: ref.id};
});

export const seedUat = onCall(async (request) => {
  const uid = requireAuth(request);
  const user = await profile(uid);
  if (user.role !== "superAdmin") throw new HttpsError("permission-denied", "Super administrator required.");
  const academyA = db.collection("academies").doc("uat-academy-a");
  const academyB = db.collection("academies").doc("uat-academy-b");
  const batch = db.batch();
  batch.set(academyA, {name: "UAT North Academy", status: "active", currency: "AED", createdAt: FieldValue.serverTimestamp()});
  batch.set(academyB, {name: "UAT South Academy", status: "active", currency: "AED", createdAt: FieldValue.serverTimestamp()});
  batch.set(db.collection("courts").doc("uat-court-a1"), {academyId: academyA.id, name: "North Padel 1", sport: "Padel", active: true, basePriceMinor: 18000, currency: "AED", openingHour: 6, closingHour: 23, blockedPeriods: [], maintenancePeriods: [], createdAt: FieldValue.serverTimestamp()});
  batch.set(db.collection("courts").doc("uat-court-b1"), {academyId: academyB.id, name: "South Basketball 1", sport: "Basketball", active: true, basePriceMinor: 21000, currency: "AED", openingHour: 6, closingHour: 23, blockedPeriods: [], maintenancePeriods: [], createdAt: FieldValue.serverTimestamp()});
  batch.set(db.collection("sports").doc("padel"), {name: "Padel", active: true});
  batch.set(db.collection("sports").doc("basketball"), {name: "Basketball", active: true});
  batch.set(db.collection("promotions").doc("uat-welcome"), {code: "UATWELCOME", active: true, discountType: "percentage", discountValue: 10, usageLimit: 100, usageCount: 0, startsAt: Timestamp.fromDate(new Date("2026-01-01T00:00:00Z")), endsAt: Timestamp.fromDate(new Date("2027-12-31T23:59:59Z"))});
  batch.set(db.collection("auditLogs").doc(), {actorId: uid, action: "uat.seed", entity: "platform", entityId: "uat", createdAt: FieldValue.serverTimestamp()});
  await batch.commit();
  return {ok: true, academies: 2, courts: 2};
});

export const createUatUser = onCall(async (request) => {
  const uid = requireAuth(request);
  const actor = await profile(uid);
  if (actor.role !== "superAdmin") throw new HttpsError("permission-denied", "Super administrator required.");
  const email = text(request.data?.email, "email").toLowerCase();
  const displayName = text(request.data?.displayName, "displayName");
  const role = text(request.data?.role, "role");
  const allowedRoles = ["platformAdmin", "academyOwner", "academyStaff", "player"];
  if (!allowedRoles.includes(role)) throw new HttpsError("invalid-argument", "Role is invalid.");
  const password = text(request.data?.temporaryPassword, "temporaryPassword");
  if (password.length < 12) throw new HttpsError("invalid-argument", "Temporary password must have at least 12 characters.");
  const created = await getAuth().createUser({email, displayName, password, emailVerified: true});
  await db.collection("users").doc(created.uid).set({uid: created.uid, email, displayName, role, permissions: Array.isArray(request.data?.permissions) ? request.data.permissions : [], academyId: request.data?.academyId ?? null, suspended: false, mustChangePassword: true, createdAt: FieldValue.serverTimestamp()});
  return {uid: created.uid};
});

export const notifyBookingCreated = onDocumentCreated("bookings/{bookingId}", async (event) => {
  const booking = event.data?.data();
  if (!booking) return;
  await db.collection("notifications").add({userId: booking.userId, type: "bookingCreated", title: "Booking confirmed", bookingId: event.params.bookingId, read: false, createdAt: FieldValue.serverTimestamp()});
});
