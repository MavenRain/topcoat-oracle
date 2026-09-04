// spec section 8.3
import test from "node:test";
import assert from "node:assert/strict";
import { bitsOfNumber, numberOfBits } from "../lib/bits.mjs";

test("the_three_halves_of_section_7_1", () => {
  assert.deepEqual({ ...bitsOfNumber(1.5) }, { hi: 1073217536, lo: 0 });
  assert.deepEqual({ ...bitsOfNumber(2.5) }, { hi: 1074003968, lo: 0 });
  assert.deepEqual({ ...bitsOfNumber(-98304) }, { hi: 3237478400, lo: 0 });
});

test("number_of_bits_inverts_all_three", () => {
  assert.equal(numberOfBits(1073217536, 0), 1.5);
  assert.equal(numberOfBits(1074003968, 0), 2.5);
  assert.equal(numberOfBits(3237478400, 0), -98304);
});

test("the_nan_payload_is_a_nan", () => {
  assert.equal(Number.isNaN(numberOfBits(2146959360, 1)), true);
});

test("nan_payload_survives_the_dataview_round_trip", () => {
  // Measured, not assumed.  DataView NaN canonicalisation is
  // implementation-defined in ECMA-262, so the spec section 2.3 probe
  // printed what this node does.  Probe step 5a, node v23.10.0:
  // [{"hi":1073217536,"lo":0},{"hi":2146959360,"lo":1}].  The payload
  // bit survives.
  assert.deepEqual({ ...bitsOfNumber(numberOfBits(2146959360, 1)) }, {
    hi: 2146959360,
    lo: 1,
  });
});
