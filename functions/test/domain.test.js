const test = require("node:test");
const assert = require("node:assert/strict");
const {calculateTotal, overlaps, assertTransition} = require("../lib/domain.js");

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
