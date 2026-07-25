import {initializeApp} from "firebase-admin/app";
import {FieldValue, Timestamp, getFirestore} from "firebase-admin/firestore";
import {getAuth} from "firebase-admin/auth";
import {getMessaging} from "firebase-admin/messaging";
import {HttpsError, onCall} from "firebase-functions/v2/https";
import {onDocumentCreated, onDocumentWritten} from "firebase-functions/v2/firestore";
import {onSchedule} from "firebase-functions/v2/scheduler";
import {setGlobalOptions} from "firebase-functions/v2/options";
import {assertTransition, calculateTotal, overlaps} from "./domain";
import {randomBytes} from "node:crypto";

initializeApp();
setGlobalOptions({region: "me-central1", maxInstances: 20});
const db = getFirestore();

export const syncPublicProfile = onDocumentWritten("users/{userId}", async (event) => {
  const data = event.data?.after.data();
  const ref = db.collection("publicProfiles").doc(event.params.userId);
  if (!data || data.suspended === true) {
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
    currency: court.currency ?? "JOD",
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
  const slotStarts = Array.from(
    {length: Math.ceil(durationMinutes / 30)},
    (_, index) => new Date(start.valueOf() + index * 30 * 60_000),
  );
  const lockRefs = slotStarts.map(slot =>
    db.collection("bookingLocks").doc(`${courtId}_${slot.valueOf()}`),
  );
  return db.runTransaction(async (tx) => {
    const [courtSnap, ...lockSnaps] = await Promise.all([
      tx.get(courtRef),
      ...lockRefs.map(ref => tx.get(ref)),
    ]);
    const court = courtSnap.data();
    if (!court || court.active === false) throw new HttpsError("not-found", "Court is unavailable.");
    if (lockSnaps.some(lock => lock.exists)) throw new HttpsError("already-exists", "This time overlaps another booking.");
    for (const period of [...(court.blockedPeriods ?? []), ...(court.maintenancePeriods ?? [])]) {
      if (overlaps(start, end, period.start.toDate(), period.end.toDate())) throw new HttpsError("failed-precondition", "This period is blocked or under maintenance.");
    }
    const openingHour = Number(court.openingHour ?? 0);
    const closingHour = Number(court.closingHour ?? 24);
    if (start.getUTCHours() < openingHour || end.getUTCHours() > closingHour) throw new HttpsError("failed-precondition", "Court is closed at this time.");
    const price = calculateTotal({basePriceMinor: court.basePriceMinor, durationMinutes});
    const playerCapacity = Number(request.data?.playerCapacity ?? 20);
    if (!Number.isInteger(playerCapacity) || playerCapacity < 1 || playerCapacity > 30) throw new HttpsError("invalid-argument", "Player capacity must be 1-30.");
    const record = {
      userId: uid, academyId: court.academyId, courtId, courtName: court.name,
      sport: court.sport, startUtc: Timestamp.fromDate(start), endUtc: Timestamp.fromDate(end),
      status: "pending", currency: court.currency ?? "JOD", ...price,
      paymentMethod: "cash", paymentStatus: "pending",
      matchmaking: request.data?.matchmaking === true, playerCapacity, participants: [uid],
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
        createdAt: FieldValue.serverTimestamp(),
      });
    });
    tx.create(bookingRef, record);
    tx.create(db.collection("auditLogs").doc(), {actorId: uid, action: "booking.create", entity: "booking", entityId: bookingRef.id, academyId: court.academyId, createdAt: FieldValue.serverTimestamp()});
    return {bookingId: bookingRef.id, ...price, currency: record.currency};
  });
});

export const createBookingInvite = onCall(async (request) => {
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
    if (["cancelled", "completed"].includes(booking.status)) throw new HttpsError("failed-precondition", "This booking no longer accepts players.");
    tx.create(inviteRef, {token, bookingId, createdBy: uid, academyId: booking.academyId, active: true, uses: 0, maxUses: Number(booking.playerCapacity ?? 20) - 1, expiresAt: booking.endUtc, createdAt: FieldValue.serverTimestamp()});
  });
  return {token, bookingId, url: `https://playup.app/join/booking/${token}`};
});

export const joinBookingInvite = onCall(async (request) => {
  const uid = requireAuth(request);
  await profile(uid);
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
    if (!booking || ["cancelled", "completed"].includes(booking.status)) throw new HttpsError("failed-precondition", "Booking is unavailable.");
    const participants: string[] = booking.participants ?? [booking.userId];
    if (participants.includes(uid)) throw new HttpsError("already-exists", "You already joined this booking.");
    if (participants.length >= Number(invite.maxUses ?? 19) + 1) throw new HttpsError("resource-exhausted", "Booking is full.");
    tx.update(bookingRef, {participants: FieldValue.arrayUnion(uid), updatedAt: FieldValue.serverTimestamp()});
    tx.update(inviteRef, {uses: FieldValue.increment(1), updatedAt: FieldValue.serverTimestamp()});
    tx.create(db.collection("notifications").doc(), {userId: booking.userId, type: "bookingJoined", title: "A player joined your booking", bookingId: invite.bookingId, read: false, createdAt: FieldValue.serverTimestamp()});
  });
  return {bookingId: query.docs[0].data().bookingId};
});

export const redeemOffer = onCall(async (request) => {
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
    const academy = managesBooking(user, booking)
      && (["academyOwner", "courtOwner"].includes(user.role)
        || permissions.includes("academy.bookings.manage")
        || (next === "checkedIn" && permissions.includes("academy.bookings.checkin")));
    const playerCancel = booking.userId === uid && next === "cancelled";
    if (!platform && !academy && !playerCancel) throw new HttpsError("permission-denied", "You cannot change this booking.");
    try { assertTransition(booking.status, next); } catch (error) { throw new HttpsError("failed-precondition", (error as Error).message); }
    tx.update(ref, {status: next, updatedAt: FieldValue.serverTimestamp(), [`${next}At`]: FieldValue.serverTimestamp()});
    if (next === "cancelled") {
      const lockIds: string[] = booking.lockIds ?? [`${booking.courtId}_${booking.startUtc.toDate().valueOf()}`];
      lockIds.forEach(lockId => tx.delete(db.collection("bookingLocks").doc(lockId)));
    }
    if (next === "completed") {
      const participants: string[] = booking.participants ?? [booking.userId];
      for (const playerId of [...new Set(participants)]) {
        const playerRef = db.collection("users").doc(playerId);
        tx.update(playerRef, {points: FieldValue.increment(40), xp: FieldValue.increment(150), updatedAt: FieldValue.serverTimestamp()});
        tx.create(playerRef.collection("pointsLedger").doc(), {type: "bookingCompleted", description: `Completed booking at ${booking.courtName}`, delta: 40, bookingId, createdAt: FieldValue.serverTimestamp()});
      }
    }
    tx.create(db.collection("auditLogs").doc(), {actorId: uid, action: `booking.${next}`, entity: "booking", entityId: bookingId, academyId: booking.academyId, createdAt: FieldValue.serverTimestamp()});
  });
  return {ok: true};
});

export const joinMatch = onCall(async (request) => {
  const uid = requireAuth(request);
  const user = await profile(uid);
  const matchId = text(request.data?.matchId, "matchId");
  const ref = db.collection("matches").doc(matchId);
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const match = snap.data();
    if (!match || match.status !== "open") throw new HttpsError("failed-precondition", "Match is not open.");
    const players: string[] = match.players ?? [];
    if (players.includes(uid)) throw new HttpsError("already-exists", "You already joined this match.");
    if (players.length >= match.capacity) throw new HttpsError("resource-exhausted", "Match is full.");
    tx.update(ref, {
      players: FieldValue.arrayUnion(uid),
      playerNames: FieldValue.arrayUnion(user.displayName ?? "Player"),
      neededPlayers: FieldValue.increment(-1),
      updatedAt: FieldValue.serverTimestamp(),
    });
    tx.create(db.collection("notifications").doc(), {userId: match.hostId, type: "matchJoined", title: "A player joined your match", matchId, read: false, createdAt: FieldValue.serverTimestamp()});
  });
  return {ok: true};
});

export const sendFriendRequest = onCall(async (request) => {
  const uid = requireAuth(request);
  const sender = await profile(uid);
  const playerId = text(request.data?.playerId, "playerId");
  if (playerId === uid) throw new HttpsError("invalid-argument", "You cannot add yourself.");
  if (!(await db.collection("users").doc(playerId).get()).exists) {
    throw new HttpsError("not-found", "Player not found.");
  }
  const friendshipId = [uid, playerId].sort().join("_");
  const ref = db.collection("friendships").doc(friendshipId);
  if ((await ref.get()).exists) {
    throw new HttpsError("already-exists", "A friend connection already exists.");
  }
  await ref.set({
    members: [uid, playerId],
    requestedBy: uid,
    requestedTo: playerId,
    requesterName: sender.displayName ?? "Player",
    status: "pending",
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  });
  await db.collection("notifications").add({
    userId: playerId,
    type: "friendRequest",
    title: `${sender.displayName ?? "A player"} sent you a friend request`,
    friendshipId,
    read: false,
    createdAt: FieldValue.serverTimestamp(),
  });
  return {friendshipId};
});

export const respondFriendRequest = onCall(async (request) => {
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

export const leaveMatch = onCall(async (request) => {
  const uid = requireAuth(request); await profile(uid);
  const matchId = text(request.data?.matchId, "matchId"); const ref = db.collection("matches").doc(matchId);
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref); const match = snap.data();
    if (!match || match.status !== "open") throw new HttpsError("failed-precondition", "Match cannot be left now.");
    if (match.hostId === uid) throw new HttpsError("failed-precondition", "The host must cancel the match instead.");
    if (!(match.players ?? []).includes(uid)) throw new HttpsError("failed-precondition", "You are not in this match.");
    tx.update(ref, {players: FieldValue.arrayRemove(uid), neededPlayers: FieldValue.increment(1), updatedAt: FieldValue.serverTimestamp()});
  }); return {ok: true};
});

export const sendMatchMessage = onCall(async (request) => {
  const uid = requireAuth(request); const user = await profile(uid);
  const matchId = text(request.data?.matchId, "matchId"); const body = text(request.data?.body, "message");
  if (body.length > 1000) throw new HttpsError("invalid-argument", "Message is too long.");
  const match = (await db.collection("matches").doc(matchId).get()).data();
  if (!match || !(match.players ?? []).includes(uid)) throw new HttpsError("permission-denied", "Join this match before chatting.");
  const ref = db.collection("matches").doc(matchId).collection("messages").doc();
  await ref.set({userId: uid, displayName: user.displayName ?? "Player", body, createdAt: FieldValue.serverTimestamp()});
  return {messageId: ref.id};
});

export const recordCashPayment = onCall(async (request) => {
  const uid = requireAuth(request); const user = await profile(uid);
  const bookingId = text(request.data?.bookingId, "bookingId"); const ref = db.collection("bookings").doc(bookingId);
  await db.runTransaction(async (tx) => { const snap = await tx.get(ref); const booking = snap.data();
    if (!booking) throw new HttpsError("not-found", "Booking not found.");
    const allowed = user.role === "superAdmin"
      || (user.permissions ?? []).includes("bookings.manage")
      || managesBooking(user, booking);
    if (!allowed) throw new HttpsError("permission-denied", "You cannot record this payment.");
    if (booking.paymentStatus === "collected") throw new HttpsError("already-exists", "Cash payment is already recorded.");
    tx.update(ref, {paymentStatus: "collected", cashCollectedBy: uid, cashCollectedAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp()});
    tx.create(db.collection("auditLogs").doc(), {actorId: uid, action: "booking.cashCollected", entity: "booking", entityId: bookingId, academyId: booking.academyId, createdAt: FieldValue.serverTimestamp()});
  }); return {ok: true};
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
  const bookingDocs = await db.collection("bookings").where("courtId", "==", courtId).get();
  const end = new Date(start.getTime() + 60 * 60 * 1000);
  const unavailable = bookingDocs.docs.some((doc) => {
    const booking = doc.data();
    if (!["pending", "confirmed"].includes(booking.status)) return false;
    const bookingStart = (booking.startUtc as Timestamp).toDate();
    const bookingEnd = (booking.endUtc as Timestamp).toDate();
    return overlaps(start, end, bookingStart, bookingEnd);
  });
  if (unavailable) throw new HttpsError("already-exists", "This court was just booked. Choose another court or time.");
  const ref = db.collection("matches").doc();
  const bookingRef = db.collection("bookings").doc();
  const lockRef = db.collection("bookingLocks").doc(`${courtId}_${start.valueOf()}`);
  await db.runTransaction(async (tx) => {
    if ((await tx.get(lockRef)).exists) {
      throw new HttpsError("already-exists", "This court was just booked. Choose another court or time.");
    }
    const price = calculateTotal({basePriceMinor: court.basePriceMinor, durationMinutes: 60});
    tx.create(lockRef, {
      bookingId: bookingRef.id, userId: uid, courtId,
      startUtc: Timestamp.fromDate(start), endUtc: Timestamp.fromDate(end),
      createdAt: FieldValue.serverTimestamp(),
    });
    tx.create(bookingRef, {
      userId: uid, academyId: court.academyId, courtId, courtName: court.name,
      sport, startUtc: Timestamp.fromDate(start), endUtc: Timestamp.fromDate(end),
      status: "pending", currency: court.currency ?? "JOD", ...price,
      paymentMethod: "cash", paymentStatus: "pending", matchmaking: true,
      playerCapacity: capacity, participants: [uid], matchId: ref.id,
      createdAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp(),
    });
    tx.create(ref, {
      hostId: uid, hostName: user.displayName ?? "Player", title, sport,
      academyId: court.academyId, courtId, courtName: court.name, bookingId: bookingRef.id,
      startUtc: Timestamp.fromDate(start), skillRange: text(request.data?.skill, "skill"),
      type: request.data?.type === "Competitive" ? "Competitive" : "Casual",
      ranked: request.data?.type === "Competitive", status: "open", capacity,
      currency: court.currency ?? "JOD", totalMinor: price.totalMinor,
      players: [uid], playerNames: [user.displayName ?? "Player"], neededPlayers: capacity - 1,
      createdAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp(),
    });
  });
  return {matchId: ref.id};
});

export const listAvailableCourts = onCall(async (request) => {
  const uid = requireAuth(request);
  await profile(uid);
  const sport = text(request.data?.sport, "sport");
  const start = date(request.data?.startUtc, "startUtc");
  const end = new Date(start.getTime() + 60 * 60 * 1000);
  if (start <= new Date()) throw new HttpsError("invalid-argument", "Choose a future match time.");
  const courts = await db.collection("courts")
    .where("active", "==", true)
    .where("sport", "==", sport)
    .get();
  const available = await Promise.all(courts.docs.map(async (courtDoc) => {
    const court = courtDoc.data();
    const blocked = [...(court.blockedPeriods ?? []), ...(court.maintenancePeriods ?? [])]
      .some((period) => overlaps(start, end, period.start.toDate(), period.end.toDate()));
    if (blocked) return null;
    const bookings = await db.collection("bookings").where("courtId", "==", courtDoc.id).get();
    const conflict = bookings.docs.some((bookingDoc) => {
      const booking = bookingDoc.data();
      return ["pending", "confirmed"].includes(booking.status)
        && overlaps(start, end, booking.startUtc.toDate(), booking.endUtc.toDate());
    });
    return conflict ? null : courtDoc.id;
  }));
  return {courtIds: available.filter((id): id is string => id !== null)};
});

export const createTournament = onCall(async (request) => {
  const uid = requireAuth(request);
  const actor = await profile(uid);
  if (!['academyOwner', 'academyStaff'].includes(actor.role) || !actor.academyId) {
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

export const registerTournament = onCall(async (request) => {
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

export const seedUat = onCall(async (request) => {
  const uid = requireAuth(request);
  const user = await profile(uid);
  if (user.role !== "superAdmin") throw new HttpsError("permission-denied", "Super administrator required.");
  const academyA = db.collection("academies").doc("uat-academy-a");
  const academyB = db.collection("academies").doc("uat-academy-b");
  const batch = db.batch();
  batch.set(academyA, {name: "Amman North Academy", status: "active", currency: "JOD", createdAt: FieldValue.serverTimestamp()});
  batch.set(academyB, {name: "Amman South Academy", status: "active", currency: "JOD", createdAt: FieldValue.serverTimestamp()});
  batch.set(db.collection("courts").doc("uat-court-a1"), {academyId: academyA.id, name: "North Padel 1", sport: "Padel", active: true, basePriceMinor: 1800, currency: "JOD", openingHour: 6, closingHour: 23, blockedPeriods: [], maintenancePeriods: [], createdAt: FieldValue.serverTimestamp()});
  batch.set(db.collection("courts").doc("uat-court-b1"), {academyId: academyB.id, name: "South Basketball 1", sport: "Basketball", active: true, basePriceMinor: 2100, currency: "JOD", openingHour: 6, closingHour: 23, blockedPeriods: [], maintenancePeriods: [], createdAt: FieldValue.serverTimestamp()});
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
  const allowedRoles = ["platformAdmin", "academyOwner", "courtOwner", "academyStaff", "player"];
  if (!allowedRoles.includes(role)) throw new HttpsError("invalid-argument", "Role is invalid.");
  const password = text(request.data?.temporaryPassword, "temporaryPassword");
  if (password.length < 12) throw new HttpsError("invalid-argument", "Temporary password must have at least 12 characters.");
  const created = await getAuth().createUser({email, displayName, password, emailVerified: true});
  await db.collection("users").doc(created.uid).set({uid: created.uid, email, displayName, role, permissions: Array.isArray(request.data?.permissions) ? request.data.permissions : [], academyId: request.data?.academyId ?? null, suspended: false, mustChangePassword: true, createdAt: FieldValue.serverTimestamp()});
  return {uid: created.uid};
});

export const createAcademyStaff = onCall(async (request) => {
  const uid = requireAuth(request); const actor = await profile(uid);
  if (actor.role !== "academyOwner" || !actor.academyId) throw new HttpsError("permission-denied", "Academy owner access is required.");
  const email = text(request.data?.email, "email").toLowerCase(); const displayName = text(request.data?.displayName, "displayName"); const password = text(request.data?.temporaryPassword, "temporaryPassword");
  if (password.length < 12) throw new HttpsError("invalid-argument", "Temporary password must have at least 12 characters.");
  const allowed = ["academy.bookings.manage", "academy.bookings.checkin", "academy.courts.manage", "academy.pricing.manage", "academy.profile.manage", "academy.reports.view"];
  const permissions = Array.isArray(request.data?.permissions) ? request.data.permissions.filter((item: unknown) => typeof item === "string" && allowed.includes(item)) : [];
  const created = await getAuth().createUser({email, displayName, password, emailVerified: true});
  await db.collection("users").doc(created.uid).set({uid: created.uid, email, displayName, role: "academyStaff", academyId: actor.academyId, permissions, suspended: false, mustChangePassword: true, createdAt: FieldValue.serverTimestamp()});
  await db.collection("auditLogs").add({actorId: uid, action: "academy.staff.create", entity: "user", entityId: created.uid, academyId: actor.academyId, createdAt: FieldValue.serverTimestamp()});
  return {uid: created.uid};
});

export const createManagedOwnerAccount = onCall(async (request) => {
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
      mustChangePassword: true, createdBy: uid, createdAt: FieldValue.serverTimestamp(),
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

export const notifyBookingCreated = onDocumentCreated("bookings/{bookingId}", async (event) => {
  const booking = event.data?.data();
  if (!booking) return;
  const batch = db.batch();
  batch.set(db.collection("notifications").doc(), {userId: booking.userId, type: "bookingCreated", title: "Booking requested - cash payment pending", bookingId: event.params.bookingId, read: false, createdAt: FieldValue.serverTimestamp()});
  const owners = await db.collection("users").where("academyId", "==", booking.academyId).where("role", "in", ["academyOwner", "courtOwner", "academyStaff"]).get();
  for (const owner of owners.docs) {
    const ownerData = owner.data();
    if (ownerData.role === "courtOwner" && !(ownerData.courtIds ?? []).includes(booking.courtId)) continue;
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

      const user = (await db.collection("users").doc(userId).get()).data();
      const tokens = Array.from(new Set<string>(user?.fcmTokens ?? [])).filter(Boolean);
      if (tokens.length === 0) return;
      await getMessaging().sendEachForMulticast({
        tokens: tokens.slice(0, 500),
        notification: {title, body},
        data: {type: "bookingReminder", bookingId: bookingDoc.id},
      }).catch(() => undefined);
    }));
  }
});
