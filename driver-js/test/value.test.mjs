// spec section 8.6.  The expected texts are the Rust wire JSON of the
// value-typed seed lines of m23_verdict.sh:60-66, byte for byte.
import test from "node:test";
import assert from "node:assert/strict";
import { encodeValue, valueJson, readValue } from "../lib/value.mjs";

// Fake surrogates: plain objects that expose dehydrate(), so the test
// needs no clone import.  worker.mjs builds the real kindOf from
// instanceof over the imported classes.
const fake = (kind, dehydrated) =>
  Object.freeze({ kind, dehydrate: () => dehydrated });

const kindOf = (v) =>
  typeof v === "function"
    ? "function"
    : v === undefined
      ? "unit"
      : typeof v === "object" && v !== null && typeof v.kind === "string"
        ? v.kind
        : "unknown";

const f64 = (n) => fake("f64", n);
const bool = (b) => fake("bool", b);
const str = (s) => fake("str", s);
const option = (inner) => fake("option", { v: inner });
const resultOk = (inner) => fake("result", { ok: inner });
const resultErr = (inner) => fake("result", { err: inner });

const EXPECTED = Object.freeze([
  Object.freeze([undefined, '{"t":"unit"}']),
  Object.freeze([f64(1.5), '{"t":"f64","hi":1073217536,"lo":0}']),
  Object.freeze([f64(2.5), '{"t":"f64","hi":1074003968,"lo":0}']),
  Object.freeze([bool(true), '{"t":"bool","v":true}']),
  Object.freeze([bool(false), '{"t":"bool","v":false}']),
  Object.freeze([str("a<b>+c"), '{"t":"str","hex":"613c623e2b63"}']),
  Object.freeze([str(""), '{"t":"str","hex":""}']),
  Object.freeze([option(null), '{"t":"none"}']),
  Object.freeze([
    option(f64(1.5)),
    '{"t":"some","v":{"t":"f64","hi":1073217536,"lo":0}}',
  ]),
  Object.freeze([resultOk(str("ok")), '{"t":"ok","v":{"t":"str","hex":"6f6b"}}']),
  Object.freeze([
    resultErr(f64(1.5)),
    '{"t":"err","v":{"t":"f64","hi":1073217536,"lo":0}}',
  ]),
]);

test("encode_value_matches_the_rust_wire_json_byte_for_byte", () => {
  EXPECTED.forEach(([input, text]) => {
    assert.deepEqual(encodeValue(input, kindOf), { ok: true, value: text });
  });
});

test("a_lone_surrogate_string_encodes_as_the_lossy_pair", () => {
  assert.deepEqual(encodeValue(str("\ud800"), kindOf), {
    ok: true,
    value: '{"t":"str","utf16_hex":"d800","lossy":true}',
  });
});

test("a_function_value_is_a_named_driver_error", () => {
  const encoded = encodeValue(() => 1, kindOf);
  assert.equal(encoded.ok, false);
  assert.equal(encoded.error, "function_value");
});

test("an_unknown_surrogate_carries_its_constructor_name", () => {
  const encoded = encodeValue({ kind: "unknown" }, kindOf);
  assert.equal(encoded.ok, false);
  assert.equal(encoded.error, "unknown_surrogate");
  assert.equal(encoded.detail, "Object");
});

test("a_signal_is_a_named_driver_error", () => {
  const encoded = encodeValue(fake("signal", null), kindOf);
  assert.equal(encoded.ok, false);
  assert.equal(encoded.error, "unknown_surrogate");
});

test("an_unknown_kind_is_a_named_driver_error", () => {
  const encoded = encodeValue({ kind: "tuple" }, kindOf);
  assert.deepEqual(encoded, {
    ok: false,
    error: "unknown_kind",
    detail: "tuple",
  });
});

test("value_json_inverts_the_seed_table", () => {
  EXPECTED.forEach(([, text]) => {
    assert.deepEqual(valueJson(JSON.parse(text)), { ok: true, value: text });
  });
});

test("value_json_re_emits_the_wire_only_variants", () => {
  assert.deepEqual(valueJson(JSON.parse('{"t":"closure"}')), {
    ok: true,
    value: '{"t":"closure"}',
  });
  assert.deepEqual(
    valueJson(JSON.parse('{"t":"tuple","vs":[{"t":"unit"},{"t":"none"}]}')),
    { ok: true, value: '{"t":"tuple","vs":[{"t":"unit"},{"t":"none"}]}' },
  );
});

test("value_json_rejects_a_shape_the_wire_never_writes", () => {
  assert.equal(valueJson(JSON.parse('{"t":"i32","v":1}')).ok, false);
  assert.equal(valueJson(JSON.parse('{"t":"f64","hi":1}')).ok, false);
  assert.equal(valueJson(JSON.parse('{"t":"str","hex":"AB"}')).ok, false);
  assert.equal(valueJson(JSON.parse("[]")).ok, false);
});

test("read_value_returns_the_node_it_validated", () => {
  const node = JSON.parse('{"t":"some","v":{"t":"unit"}}');
  assert.deepEqual(readValue(node), { ok: true, value: node });
  assert.equal(readValue({ t: "nope" }).ok, false);
});

test("the_encoder_never_emits_a_unicode_escape_a_minus_or_a_point", () => {
  const all = EXPECTED.map(([, text]) => text).join("");
  assert.equal(/\\u/.test(all), false);
  assert.equal(/-/.test(all), false);
  assert.equal(/\./.test(all), false);
});
