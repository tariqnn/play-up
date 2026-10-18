const test = require("node:test");
const assert = require("node:assert/strict");
const {calculateTotal, calculateSettlement, overlaps, assertTransition, calculateEffectiveHourlyRate, calculateRatingDelta, calculateNextReliability, canPublishPublicProfile} = require("../lib/domain.js");
const {buildAuthEmail, playUpActionLink} = require("../lib/auth-email.js");

test("public profiles exclude guests, demo accounts, test names, and private users", () => {
  assert.equal(canPublishPublicProfile({role: "player", displayName: "Tariq"}), true);
  for (const flag of ["isGuest", "isDemo", "isTest", "suspended"]) {
    assert.equal(canPublishPublicProfile({role: "player", displayName: "Player One", [flag]: true}), false);
  }
  for (const displayName of ["", "Player", "Guest Player", "UAT Player", "Demo Athlete", "Test Player"]) {
    assert.equal(canPublishPublicProfile({role: "player", displayName}), false);
  }
  assert.equal(canPublishPublicProfile({role: "player", displayName: "Sam Player"}), true);
  assert.equal(canPublishPublicProfile({role: "player", displayName: "Private Player", privacyPreferences: {publicProfile: false}}), false);
  assert.equal(canPublishPublicProfile({role: "player", displayName: "Test account", email: "player@playup-demo.test"}), false);
});

test("server calculates percentage discounts in minor units", () => {
  assert.deepEqual(calculateTotal({basePriceMinor: 12000, durationMinutes: 90, discountType: "percentage", discountValue: 10}), {subtotalMinor: 18000, discountMinor: 1800, totalMinor: 16200});
});

test("fixed discount cannot make total negative", () => {
  assert.equal(calculateTotal({basePriceMinor: 1000, durationMinutes: 60, discountType: "fixed", discountValue: 5000}).totalMinor, 0);
});

test("overlap uses half-open intervals", () => {
  const hour = 3_600_000;
  const start = new Date(0);
  assert.equal(overlaps(start, new Date(hour), new Date(hour), new Date(hour * 2)), false);
  assert.equal(overlaps(start, new Date(hour * 2), new Date(hour), new Date(hour * 3)), true);
});

test("terminal booking statuses cannot reopen", () => {
  assert.throws(() => assertTransition("cancelled", "confirmed"));
  assert.doesNotThrow(() => assertTransition("confirmed", "checkedIn"));
});

test("PlayUp auth emails show a text logo without remote or inline image loading", () => {
  const email = buildAuthEmail("resetPassword", "https://play-up.fit/auth/action?mode=resetPassword&token=unit-test");
  assert.equal(email.subject, "Reset your PlayUp password");
  assert.match(email.html, /bgcolor="#10231b"/);
  assert.match(email.html, /PlayUp<\/td>/);
  assert.match(email.html, /#22e879/);
  assert.doesNotMatch(email.html, /<img\b|cid:|playup-email-logo\.png/);
  assert.doesNotMatch(email.html, /Â·/);
  assert.match(email.text, /Reset password: https:\/\/play-up\.fit\/auth\/action/);
});

test("PlayUp auth actions use the branded action page and retain Firebase parameters", () => {
  const link = playUpActionLink(
    "https://sports-app-257a0.firebaseapp.com/__/auth/action?mode=resetPassword&oobCode=unit-code&apiKey=unit-api-key",
    "resetPassword",
  );
  const actionUrl = new URL(link);
  assert.equal(actionUrl.origin, "https://play-up.fit");
  assert.equal(actionUrl.pathname, "/auth/action");
  assert.equal(actionUrl.searchParams.get("mode"), "resetPassword");
  assert.equal(actionUrl.searchParams.get("oobCode"), "unit-code");
  assert.equal(actionUrl.searchParams.get("apiKey"), "unit-api-key");
});

test("cash settlement snapshots platform commission in minor units", () => {
  assert.deepEqual(calculateSettlement(12_345, 1_250), {
    grossMinor: 12_345,
    platformCommissionBps: 1_250,
    platformCommissionMinor: 1_543,
    academyNetMinor: 10_802,
  });
  assert.throws(() => calculateSettlement(1000, 10_001));
});

test("peak pricing applies during configured peak hours", () => {
  const peakDate = new Date("2026-06-01T19:00:00Z");
  const offPeakDate = new Date("2026-06-01T10:00:00Z");
  const config = { peakHourStart: 18, peakHourEnd: 23, peakPriceMinor: 2500 };
  const peakResult = calculateEffectiveHourlyRate(1500, peakDate, config);
  assert.equal(peakResult.hourlyRateMinor, 2500);
  assert.equal(peakResult.isPeak, true);

  const offPeakResult = calculateEffectiveHourlyRate(1500, offPeakDate, config);
  assert.equal(offPeakResult.hourlyRateMinor, 1500);
  assert.equal(offPeakResult.isPeak, false);
});

test("reliability calculation increments on completion and penalizes cancellation", () => {
  assert.equal(calculateNextReliability(98, "completed"), 100);
  assert.equal(calculateNextReliability(100, "lateCancel"), 85);
  assert.equal(calculateNextReliability(20, "noShow"), 0);
});

test("rating delta computes dynamic Elo changes", () => {
  const { aDelta, bDelta } = calculateRatingDelta(3.0, 3.0, true);
  assert.ok(aDelta > 0, "Winner should gain rating");
  assert.ok(bDelta < 0, "Loser should lose rating");
  assert.equal(Number((aDelta + bDelta).toFixed(2)), 0);
});
