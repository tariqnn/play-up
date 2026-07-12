const {initializeApp} = require('firebase-admin/app');
const {getFirestore} = require('firebase-admin/firestore');
initializeApp({projectId: 'sports-app-257a0'});
const db = getFirestore();
const password = process.env.UAT_TEMPORARY_PASSWORD;
if (!process.env.FIRESTORE_EMULATOR_HOST || !process.env.FIREBASE_AUTH_EMULATOR_HOST || !password) throw new Error('Emulator hosts and UAT_TEMPORARY_PASSWORD are required.');

async function signIn(email) {
  const response = await fetch('http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=fake', {method: 'POST', headers: {'content-type': 'application/json'}, body: JSON.stringify({email, password, returnSecureToken: true})});
  if (!response.ok) throw new Error(`Sign-in failed for ${email}: ${await response.text()}`);
  return (await response.json()).idToken;
}
async function call(name, token, data) {
  const response = await fetch(`http://127.0.0.1:5001/sports-app-257a0/me-central1/${name}`, {method: 'POST', headers: {'content-type': 'application/json', authorization: `Bearer ${token}`}, body: JSON.stringify({data})});
  const body = await response.json();
  if (!response.ok || body.error) throw new Error(`${name}: ${body.error?.message || response.status}`);
  return body.result;
}

(async () => {
  const [player, owner, admin] = await Promise.all([signIn('player@uat.invalid'), signIn('owner-a@uat.invalid'), signIn('superadmin@uat.invalid')]);
  const tomorrow = new Date(); tomorrow.setUTCDate(tomorrow.getUTCDate() + 1); tomorrow.setUTCHours(10, 0, 0, 0);
  const end = new Date(tomorrow.valueOf() + 60 * 60 * 1000);
  const attempts = await Promise.allSettled([call('createBooking', player, {courtId: 'uat-court-a1', startUtc: tomorrow.toISOString(), endUtc: end.toISOString()}), call('createBooking', player, {courtId: 'uat-court-a1', startUtc: tomorrow.toISOString(), endUtc: end.toISOString()})]);
  const successes = attempts.filter((x) => x.status === 'fulfilled');
  const failures = attempts.filter((x) => x.status === 'rejected');
  if (successes.length !== 1 || failures.length !== 1) throw new Error('Double-booking concurrency guard failed.');
  const bookingId = successes[0].value.bookingId;
  const booking = (await db.collection('bookings').doc(bookingId).get()).data();
  if (booking.totalMinor !== 18000 || booking.paymentMethod !== 'payAtVenue') throw new Error('Server pricing/payment policy failed.');
  await call('transitionBooking', admin, {bookingId, status: 'checkedIn'});
  await call('transitionBooking', admin, {bookingId, status: 'completed'});
  const match = await call('createMatch', player, {title: 'UAT Padel Doubles', sport: 'Padel', courtId: 'uat-court-a1', startUtc: tomorrow.toISOString(), capacity: 2, skill: 'Intermediate', type: 'Casual'});
  await call('joinMatch', owner, {matchId: match.matchId});
  let duplicateRejected = false; try { await call('joinMatch', owner, {matchId: match.matchId}); } catch { duplicateRejected = true; }
  if (!duplicateRejected) throw new Error('Duplicate matchmaking join was accepted.');
  await new Promise((resolve) => setTimeout(resolve, 1000));
  const notifications = await db.collection('notifications').where('userId', '==', booking.userId).get();
  if (notifications.empty) throw new Error('Booking notification was not generated.');
  const audit = await db.collection('auditLogs').where('entityId', '==', bookingId).get();
  if (audit.size < 3) throw new Error('Expected booking audit trail was not generated.');
  console.log(JSON.stringify({authRoles: 3, bookingId, doubleBookingRejected: true, serverTotalMinor: booking.totalMinor, finalBookingStatus: 'completed', matchId: match.matchId, duplicateJoinRejected: true, notifications: notifications.size, auditEntries: audit.size}, null, 2));
})().catch((error) => { console.error(error); process.exitCode = 1; });
