// spec section 8.4
import test from "node:test";
import assert from "node:assert/strict";
import { utf8OfString, stringOfUtf8 } from "../lib/text.mjs";
import { bytesOfHex } from "../lib/hex.mjs";

test("an_ascii_string_encodes_as_utf8", () => {
  assert.deepEqual(utf8OfString("a<b>+c"), {
    kind: "utf8",
    hex: "613c623e2b63",
  });
});

test("a_multi_byte_string_round_trips", () => {
  // The same bytes research/m23-driver-probe.md section 7 records for
  // the Rust side.
  const encoded = utf8OfString("é\u{1f600}");
  assert.deepEqual(encoded, { kind: "utf8", hex: "c3a9f09f9880" });
  assert.deepEqual(stringOfUtf8(bytesOfHex(encoded.hex).value), {
    ok: true,
    value: "é\u{1f600}",
  });
});

test("a_lone_surrogate_encodes_as_utf16_and_never_as_the_replacement", () => {
  const encoded = utf8OfString("\ud800");
  assert.deepEqual(encoded, { kind: "utf16", hex: "d800" });
  assert.notEqual(encoded.hex, "efbfbd");
});

test("string_of_utf8_accepts_valid_bytes", () => {
  assert.deepEqual(stringOfUtf8(bytesOfHex("613c623e2b63").value), {
    ok: true,
    value: "a<b>+c",
  });
  assert.deepEqual(stringOfUtf8(bytesOfHex("").value), {
    ok: true,
    value: "",
  });
});

test("string_of_utf8_keeps_a_leading_byte_order_mark", () => {
  // The default decoder strips the BOM, which would make these well
  // formed bytes answer the named error.
  assert.deepEqual(stringOfUtf8(bytesOfHex("efbbbf78").value), {
    ok: true,
    value: "\u{feff}x",
  });
  assert.deepEqual(utf8OfString("\u{feff}x"), {
    kind: "utf8",
    hex: "efbbbf78",
  });
});

test("string_of_utf8_rejects_a_stray_ff_byte", () => {
  assert.deepEqual(stringOfUtf8(bytesOfHex("ff").value), {
    ok: false,
    error: "utf8",
  });
});

test("string_of_utf8_rejects_a_truncated_three_byte_sequence", () => {
  assert.deepEqual(stringOfUtf8(bytesOfHex("e282").value), {
    ok: false,
    error: "utf8",
  });
});
