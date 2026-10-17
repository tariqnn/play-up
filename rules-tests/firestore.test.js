const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {initializeTestEnvironment, assertFails, assertSucceeds} = require('@firebase/rules-unit-testing');
const {collection, doc, getDoc, getDocs, orderBy, query, setDoc, updateDoc, where} = require('firebase/firestore');

let env;
test.before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'playup-rules-test',
    firestore: {rules: fs.readFileSync(path.join(__dirname, '..', 'firestore.rules'), 'utf8')},
  });
  await env.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await setDoc(doc(db, 'users/owner-a'), {role: 'academyOwner', academyId: 'academy-a', permissions: [], suspended: false});
    await setDoc(doc(db, 'users/owner-b'), {role: 'academyOwner', academyId: 'academy-b', permissions: [], suspended: false});
    await setDoc(doc(db, 'users/player'), {role: 'player', permissions: [], suspended: false});
    await setDoc(doc(db, 'users/staff-a'), {role: 'academyStaff', academyId: 'academy-a', permissions: [], suspended: false});
    await setDoc(doc(db, 'users/court-owner-a'), {role: 'courtOwner', academyId: 'academy-a', courtIds: ['court-a'], permissions: [], suspended: false});
    await setDoc(doc(db, 'courts/court-a'), {academyId: 'academy-a', name: 'Court A', sport: 'Padel', active: true, basePriceMinor: 1800, currency: 'JOD', openingHour: 6, closingHour: 23, timezone: 'Asia/Amman'});
    await setDoc(doc(db, 'academies/academy-a'), {name: 'Academy A', platformCommissionPercent: 12});
    await setDoc(doc(db, 'courts/court-b'), {academyId: 'academy-b', name: 'Court B', sport: 'Padel', active: true, basePriceMinor: 1800, currency: 'JOD', openingHour: 6, closingHour: 23, timezone: 'Asia/Amman'});
    await setDoc(doc(db, 'bookings/booking-b'), {academyId: 'academy-b', userId: 'player', status: 'confirmed'});
    await setDoc(doc(db, 'bookings/booking-a'), {academyId: 'academy-a', courtId: 'court-a', userId: 'player', participants: ['player', 'participant'], startUtc: new Date('2026-10-18T10:00:00.000Z'), status: 'confirmed'});
    await setDoc(doc(db, 'bookings/booking-a2'), {academyId: 'academy-a', courtId: 'court-a2', userId: 'player', status: 'confirmed'});
    await setDoc(doc(db, 'courts/court-a2'), {academyId: 'academy-a', name: 'Court A2', sport: 'Padel', active: true, basePriceMinor: 1800, currency: 'JOD', openingHour: 6, closingHour: 23, timezone: 'Asia/Amman'});
    await setDoc(doc(db, 'matches/match-a'), {players: ['player'], status: 'open'});
    await setDoc(doc(db, 'matches/match-closed'), {players: ['player'], status: 'completed'});
    await setDoc(doc(db, 'matches/match-a/messages/message-a'), {userId: 'player', body: 'hello'});
    await setDoc(doc(db, 'bookingLocks/private-lock'), {courtId: 'court-a', userId: 'player'});
    await setDoc(doc(db, 'users/player/pointsLedger/entry-a'), {delta: 40});
    await setDoc(doc(db, 'users/participant'), {role: 'player', permissions: [], suspended: false});
    await setDoc(doc(db, 'users/platform'), {role: 'platformAdmin', permissions: ['platform.manage', 'users.manage'], suspended: false});
    await setDoc(doc(db, 'publicProfiles/player'), {displayName: 'Player', xp: 0});
    await setDoc(doc(db, 'platformConfig/general'), {maintenanceMode: false});
    await setDoc(doc(db, 'bookingInvites/private-invite'), {bookingId: 'booking-a', token: 'secret'});
    await setDoc(doc(db, 'supportTickets/ticket-a'), {userId: 'player', category: 'Booking', message: 'Please help with this booking.', status: 'open'});
    await setDoc(doc(db, 'promotions/WELCOME'), {code: 'WELCOME', discountType: 'percentage', discountValue: 10, usageLimit: 100, usageCount: 4, active: true});
  });
});

test('academy owner can read own staff but not another academy owner', async () => {
  const db = env.authenticatedContext('owner-a').firestore();
  await assertSucceeds(getDoc(doc(db, 'users/staff-a')));
  await assertFails(getDoc(doc(db, 'users/owner-b')));
});

test('match chat and points ledger stay private to participants and owner', async () => {
  const playerDb = env.authenticatedContext('player').firestore();
  const outsiderDb = env.authenticatedContext('owner-a').firestore();
  await assertSucceeds(getDoc(doc(playerDb, 'matches/match-a/messages/message-a')));
  await assertFails(getDoc(doc(outsiderDb, 'matches/match-a/messages/message-a')));
  await assertSucceeds(getDoc(doc(playerDb, 'users/player/pointsLedger/entry-a')));
  await assertFails(getDoc(doc(outsiderDb, 'users/player/pointsLedger/entry-a')));
});
test.after(async () => env?.cleanup());

test('academy A cannot read or modify academy B private records', async () => {
  const db = env.authenticatedContext('owner-a').firestore();
  await assertFails(getDoc(doc(db, 'bookings/booking-b')));
  await assertFails(updateDoc(doc(db, 'courts/court-b'), {name: 'Compromised'}));
});

test('academy owner can update a court in own tenant without changing tenant', async () => {
  const db = env.authenticatedContext('owner-a').firestore();
  await assertSucceeds(updateDoc(doc(db, 'courts/court-a'), {name: 'Updated', academyId: 'academy-a'}));
  await assertFails(updateDoc(doc(db, 'courts/court-a'), {academyId: 'academy-b'}));
});

test('court owner is restricted to the assigned court and its bookings', async () => {
  const db = env.authenticatedContext('court-owner-a').firestore();
  await assertSucceeds(getDoc(doc(db, 'courts/court-a')));
  await assertSucceeds(updateDoc(doc(db, 'courts/court-a'), {name: 'Owner update', academyId: 'academy-a'}));
  await assertFails(updateDoc(doc(db, 'courts/court-a2'), {name: 'Not assigned', academyId: 'academy-a'}));
  await assertSucceeds(getDoc(doc(db, 'bookings/booking-a')));
  await assertFails(getDoc(doc(db, 'bookings/booking-a2')));
  await assertFails(updateDoc(doc(db, 'academies/academy-a'), {name: 'Not allowed'}));
});

test('player cannot escalate role or create booking directly', async () => {
  const db = env.authenticatedContext('player').firestore();
  await assertFails(updateDoc(doc(db, 'users/player'), {role: 'superAdmin'}));
  await assertFails(updateDoc(doc(db, 'users/player'), {points: 999999, xp: 999999}));
  await assertSucceeds(updateDoc(doc(db, 'users/player'), {
    notificationPreferences: {bookingReminders: false},
  }));
  await assertFails(setDoc(doc(db, 'bookings/attack'), {userId: 'player', status: 'confirmed'}));
  await assertFails(setDoc(doc(db, 'bookings/valid-looking-attack'), {
    userId: 'player', academyId: 'academy-a', courtId: 'court-a',
    participants: ['player'], status: 'pending', totalMinor: 1,
  }));
  await assertFails(updateDoc(doc(db, 'publicProfiles/player'), {xp: 999999}));
});

test('new player profiles cannot mint points or experience', async () => {
  const db = env.authenticatedContext('new-player').firestore();
  await assertSucceeds(setDoc(doc(db, 'users/new-player'), {
    uid: 'new-player', role: 'player', permissions: [], suspended: false,
    points: 0, xp: 0, level: 1, nextLevelXp: 500, rating: 0, matches: 0,
  }));
  await assertFails(setDoc(doc(db, 'users/fake-points'), {
    uid: 'fake-points', role: 'player', permissions: [], suspended: false,
    points: 100, xp: 0, level: 1, nextLevelXp: 500, rating: 0, matches: 0,
  }));
});

test('booking participants can read their booking and platform status is public', async () => {
  const participantDb = env.authenticatedContext('participant').firestore();
  const publicDb = env.unauthenticatedContext().firestore();
  await assertSucceeds(getDoc(doc(participantDb, 'bookings/booking-a')));
  const participantBookings = await assertSucceeds(getDocs(query(
    collection(participantDb, 'bookings'),
    where('participants', 'array-contains', 'participant'),
    orderBy('startUtc'),
  )));
  assert.deepEqual(participantBookings.docs.map((booking) => booking.id), ['booking-a']);
  await assertSucceeds(getDoc(doc(publicDb, 'platformConfig/general')));
});

test('dashboard layouts are private per user', async () => {
  const db = env.authenticatedContext('player').firestore();
  await assertSucceeds(setDoc(doc(db, 'dashboardLayouts/player'), {platform: {visible: []}}));
  await assertFails(getDoc(doc(db, 'dashboardLayouts/owner-a')));
  assert.ok(true);
});

test('guest can browse matches but cannot read participant chat', async () => {
  const db = env.authenticatedContext('guest-anonymous').firestore();
  await assertSucceeds(getDoc(doc(db, 'matches/match-a')));
  await assertFails(getDoc(doc(db, 'matches/match-closed')));
  await assertFails(getDoc(doc(db, 'matches/match-a/messages/message-a')));
  await assertFails(getDoc(doc(db, 'bookingLocks/private-lock')));
});

test('academy owner cannot change the platform commission percentage', async () => {
  const db = env.authenticatedContext('owner-a').firestore();
  await assertFails(updateDoc(doc(db, 'academies/academy-a'), {platformCommissionPercent: 0}));
  await assertSucceeds(updateDoc(doc(db, 'academies/academy-a'), {name: 'Updated academy'}));
});

test('invite tokens are server-only and support users cannot rewrite tickets', async () => {
  const playerDb = env.authenticatedContext('player').firestore();
  const platformDb = env.authenticatedContext('platform').firestore();
  await assertFails(getDoc(doc(playerDb, 'bookingInvites/private-invite')));
  await assertSucceeds(getDoc(doc(playerDb, 'supportTickets/ticket-a')));
  await assertFails(updateDoc(doc(playerDb, 'supportTickets/ticket-a'), {status: 'closed'}));
  await assertSucceeds(updateDoc(doc(platformDb, 'supportTickets/ticket-a'), {
    status: 'closed',
    updatedAt: new Date(),
  }));
  await assertFails(updateDoc(doc(platformDb, 'supportTickets/ticket-a'), {userId: 'platform'}));
});

test('promotion usage is immutable to clients and academy offers require a positive cost', async () => {
  const platformDb = env.authenticatedContext('platform').firestore();
  const ownerDb = env.authenticatedContext('owner-a').firestore();
  await assertSucceeds(updateDoc(doc(platformDb, 'promotions/WELCOME'), {discountValue: 15}));
  await assertFails(updateDoc(doc(platformDb, 'promotions/WELCOME'), {usageCount: 0}));
  await assertFails(setDoc(doc(ownerDb, 'promotions/OWNER'), {
    code: 'OWNER', discountType: 'percentage', discountValue: 10,
    usageLimit: 10, perUserLimit: 1, usageCount: 0, active: true,
  }));
  await assertFails(setDoc(doc(ownerDb, 'offers/free'), {
    academyId: 'academy-a', title: 'Free exploit', points: 0,
    pointsCost: 0, partner: 'Academy reward', category: 'Academy', active: true,
  }));
  await assertSucceeds(setDoc(doc(ownerDb, 'offers/valid'), {
    academyId: 'academy-a', title: 'Valid reward', points: 500,
    pointsCost: 500, partner: 'Academy reward', category: 'Academy', active: true,
  }));
});
