const {initializeApp, applicationDefault} = require('firebase-admin/app');
const {getAuth} = require('firebase-admin/auth');
const {getFirestore, FieldValue} = require('firebase-admin/firestore');

if (process.env.ALLOW_UAT_SEED !== 'yes') throw new Error('Set ALLOW_UAT_SEED=yes to confirm UAT-only seeding.');
const projectId = process.env.GCLOUD_PROJECT || process.env.FIREBASE_PROJECT_ID;
if (!projectId) throw new Error('Set FIREBASE_PROJECT_ID.');
const emulator = Boolean(process.env.FIRESTORE_EMULATOR_HOST && process.env.FIREBASE_AUTH_EMULATOR_HOST);
if (!emulator && !projectId.toLowerCase().includes('uat')) throw new Error('Refusing to seed a project whose ID does not contain "uat".');
initializeApp(emulator ? {projectId} : {credential: applicationDefault(), projectId});
const auth = getAuth(); const db = getFirestore();
const password = process.env.UAT_TEMPORARY_PASSWORD;
if (!password || password.length < 12) throw new Error('Set UAT_TEMPORARY_PASSWORD to at least 12 characters.');
const users = [
  ['superadmin@uat.invalid', 'UAT Super Admin', 'superAdmin', [], null],
  ['bookingadmin@uat.invalid', 'UAT Booking Admin', 'platformAdmin', ['bookings.manage','matchmaking.manage'], null],
  ['owner-a@uat.invalid', 'Academy A Owner', 'academyOwner', [], 'uat-academy-a'],
  ['owner-b@uat.invalid', 'Academy B Owner', 'academyOwner', [], 'uat-academy-b'],
  ['staff-a@uat.invalid', 'Academy A Staff', 'academyStaff', ['academy.bookings.manage','academy.bookings.checkin','academy.courts.manage'], 'uat-academy-a'],
  ['player@uat.invalid', 'UAT Player', 'player', [], null],
];
(async () => {
  for (const [email, displayName, role, permissions, academyId] of users) {
    let user; try { user = await auth.getUserByEmail(email); } catch { user = await auth.createUser({email, displayName, password, emailVerified: true}); }
    await db.collection('users').doc(user.uid).set({uid: user.uid, email, displayName, role, permissions, academyId, suspended: false, mustChangePassword: true, points: role === 'player' ? 2000 : 0, xp: 0, level: 1, updatedAt: FieldValue.serverTimestamp()}, {merge: true});
  }
  const batch = db.batch();
  batch.set(db.collection('academies').doc('uat-academy-a'), {name: 'UAT North Academy', status: 'active', currency: 'AED'});
  batch.set(db.collection('academies').doc('uat-academy-b'), {name: 'UAT South Academy', status: 'active', currency: 'AED'});
  batch.set(db.collection('courts').doc('uat-court-a1'), {academyId: 'uat-academy-a', name: 'North Padel 1', sport: 'Padel', active: true, basePriceMinor: 18000, currency: 'JOD', latitude: 31.9862, longitude: 35.9024, address: 'Sports City, Amman', image: 'https://images.unsplash.com/photo-1626224583764-f87db24ac4ea?w=1200&q=80', openingHour: 6, closingHour: 23, blockedPeriods: [], maintenancePeriods: []});
  batch.set(db.collection('courts').doc('uat-court-b1'), {academyId: 'uat-academy-b', name: 'South Basketball 1', sport: 'Basketball', active: true, basePriceMinor: 21000, currency: 'JOD', latitude: 31.9418, longitude: 35.9296, address: 'Abdoun, Amman', image: 'https://images.unsplash.com/photo-1504450758481-7338eba7524a?w=1200&q=80', openingHour: 6, closingHour: 23, blockedPeriods: [], maintenancePeriods: []});
  batch.set(db.collection('offers').doc('uat-offer-a'), {academyId: 'uat-academy-a', title: 'UAT Free Racket Rental', partner: 'UAT North Academy', points: 500, active: true, gradient: 'green', sort: 1});
  await batch.commit();
  console.log(`Seeded ${users.length} UAT users, 2 academies and 2 courts in ${projectId}.`);
})().catch((error) => { console.error(error); process.exitCode = 1; });
