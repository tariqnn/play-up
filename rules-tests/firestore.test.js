const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {initializeTestEnvironment, assertFails, assertSucceeds} = require('@firebase/rules-unit-testing');
const {doc, getDoc, setDoc, updateDoc} = require('firebase/firestore');

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
    await setDoc(doc(db, 'courts/court-a'), {academyId: 'academy-a', name: 'A'});
    await setDoc(doc(db, 'academies/academy-a'), {name: 'Academy A', platformCommissionPercent: 12});
    await setDoc(doc(db, 'courts/court-b'), {academyId: 'academy-b', name: 'B'});
    await setDoc(doc(db, 'bookings/booking-b'), {academyId: 'academy-b', userId: 'player', status: 'confirmed'});
    await setDoc(doc(db, 'matches/match-a'), {players: ['player'], status: 'open'});
    await setDoc(doc(db, 'matches/match-a/messages/message-a'), {userId: 'player', body: 'hello'});
    await setDoc(doc(db, 'users/player/pointsLedger/entry-a'), {delta: 40});
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

test('player cannot escalate role or create booking directly', async () => {
  const db = env.authenticatedContext('player').firestore();
  await assertFails(updateDoc(doc(db, 'users/player'), {role: 'superAdmin'}));
  await assertFails(setDoc(doc(db, 'bookings/attack'), {userId: 'player', status: 'confirmed'}));
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
  await assertFails(getDoc(doc(db, 'matches/match-a/messages/message-a')));
});

test('academy owner cannot change the platform commission percentage', async () => {
  const db = env.authenticatedContext('owner-a').firestore();
  await assertFails(updateDoc(doc(db, 'academies/academy-a'), {platformCommissionPercent: 0}));
  await assertSucceeds(updateDoc(doc(db, 'academies/academy-a'), {name: 'Updated academy'}));
});
