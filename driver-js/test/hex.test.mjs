// spec section 8.2
import test from "node:test";
import assert from "node:assert/strict";
import { bytesOfHex, hexOfBytes } from "../lib/hex.mjs";

// The seven payloads of spec section 7.2, with their byte counts.
const PAYLOADS = Object.freeze([
  Object.freeze(["312e35", 3]),
  Object.freeze(["322e35", 3]),
  Object.freeze(["613c623e2b63", 6]),
  Object.freeze(["", 0]),
  Object.freeze([
    "63616c6c656420604f7074696f6e2e756e77726170282960206f6e206120604e6f6e65602076616c7565",
    42,
  ]),
  Object.freeze(["6e6f70653a206f6b", 8]),
  Object.freeze(["626f6f6d", 4]),
]);

test("the_seven_payloads_round_trip", () => {
  PAYLOADS.forEach(([hex, bytes]) => {
    const decoded = bytesOfHex(hex);
    assert.equal(decoded.ok, true);
    assert.equal(decoded.value.length, bytes);
    assert.equal(hexOfBytes(decoded.value), hex);
  });
});

test("an_odd_length_is_rejected", () => {
  assert.deepEqual(bytesOfHex("abc"), { ok: false, error: "hex", at: 2 });
});

test("uppercase_is_rejected", () => {
  // The Rust writer emits lowercase (harness.rs:514 "{b:02x}"), so
  // uppercase would be a wire no one writes.
  assert.deepEqual(bytesOfHex("AB"), { ok: false, error: "hex", at: 0 });
});

test("a_non_hex_character_is_rejected_with_its_offset", () => {
  assert.deepEqual(bytesOfHex("6g"), { ok: false, error: "hex", at: 1 });
});

test("the_empty_string_is_zero_bytes", () => {
  const decoded = bytesOfHex("");
  assert.equal(decoded.ok, true);
  assert.equal(decoded.value.length, 0);
  assert.equal(hexOfBytes(decoded.value), "");
});

test("the_two_rust_texts_of_section_7_2_decode_to_their_byte_counts", () => {
  assert.equal(
    bytesOfHex(
      "63616c6c656420604f7074696f6e3a3a756e77726170282960206f6e206120604e6f6e65602076616c7565",
    ).value.length,
    43,
  );
  assert.equal(bytesOfHex("6e6f70653a20226f6b22").value.length, 10);
});
