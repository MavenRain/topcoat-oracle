// spec section 8.7
import test from "node:test";
import assert from "node:assert/strict";
import { subsetViolation, readLine, outLine } from "../lib/line.mjs";

// The twelve seed lines, from the expected table of m23_verdict.sh
// lines 60-71, with js_hex and debug_hex masked exactly as that file
// masks them.  The masked form is used because a unit test does no file
// I/O and because the real js_hex carries a uuid that is fresh on every
// run.  The subset scanner is a byte scanner, so the mask changes
// nothing it looks at.
const SEED_LINES = Object.freeze([
  "{\"case\":0,\"outcome\":\"value\",\"value\":{\"t\":\"f64\",\"hi\":1073217536,\"lo\":0},\"rendered_hex\":\"312e35\",\"js_consistent\":true,\"js_hex\":\"JS\",\"js_form\":\"direct\",\"hint\":\"none\",\"signals\":[]}",
  "{\"case\":1,\"outcome\":\"value\",\"value\":{\"t\":\"str\",\"hex\":\"613c623e2b63\"},\"rendered_hex\":\"61266c743b622667743b2b63\",\"js_consistent\":true,\"js_hex\":\"JS\",\"js_form\":\"direct\",\"hint\":\"none\",\"signals\":[]}",
  "{\"case\":2,\"outcome\":\"value\",\"value\":{\"t\":\"str\",\"hex\":\"\"},\"rendered_hex\":\"\",\"js_consistent\":true,\"js_hex\":\"JS\",\"js_form\":\"direct\",\"hint\":\"none\",\"signals\":[]}",
  "{\"case\":3,\"outcome\":\"value\",\"value\":{\"t\":\"some\",\"v\":{\"t\":\"f64\",\"hi\":1073217536,\"lo\":0}},\"rendered_hex\":\"312e35\",\"js_consistent\":true,\"js_hex\":\"JS\",\"js_form\":\"direct\",\"hint\":\"none\",\"signals\":[]}",
  "{\"case\":4,\"outcome\":\"value\",\"value\":{\"t\":\"none\"},\"rendered_hex\":\"\",\"js_consistent\":true,\"js_hex\":\"JS\",\"js_form\":\"direct\",\"hint\":\"none\",\"signals\":[]}",
  "{\"case\":5,\"outcome\":\"panic\",\"class\":\"unwrap\",\"msg_hex\":\"63616c6c656420604f7074696f6e3a3a756e77726170282960206f6e206120604e6f6e65602076616c7565\",\"js_hex\":\"JS\",\"js_form\":\"closure\",\"hint\":\"none\",\"signals\":[]}",
  "{\"case\":6,\"outcome\":\"value\",\"value\":{\"t\":\"f64\",\"hi\":1074003968,\"lo\":0},\"rendered_hex\":\"322e35\",\"js_consistent\":true,\"js_hex\":\"JS\",\"js_form\":\"direct\",\"hint\":\"none\",\"signals\":[{\"id\":3,\"value\":{\"t\":\"f64\",\"hi\":1074003968,\"lo\":0},\"debug_hex\":\"DBG\"}]}",
  "{\"case\":7,\"outcome\":\"panic\",\"class\":\"signal_write\",\"msg_hex\":\"65787072657373696f6e7320696e2077686963682061207369676e616c206973207772697474656e20746f2063616e6e6f742062652072756e207365727665722d73696465\",\"js_hex\":\"JS\",\"js_form\":\"closure\",\"hint\":\"none\",\"signals\":[{\"id\":4,\"value\":{\"t\":\"bool\",\"v\":true},\"debug_hex\":\"DBG\"}]}",
  "{\"case\":8,\"outcome\":\"panic\",\"class\":\"expect_err\",\"msg_hex\":\"6e6f70653a20226f6b22\",\"js_hex\":\"JS\",\"js_form\":\"closure\",\"hint\":\"expect_err\",\"signals\":[]}",
  "{\"case\":9,\"outcome\":\"panic\",\"class\":\"expect\",\"msg_hex\":\"626f6f6d\",\"js_hex\":\"JS\",\"js_form\":\"closure\",\"hint\":\"expect\",\"signals\":[]}",
  "{\"case\":10,\"outcome\":\"panic\",\"class\":\"other\",\"msg_hex\":\"6e6f70653a20226f6b22\",\"js_hex\":\"JS\",\"js_form\":\"closure\",\"hint\":\"both\",\"signals\":[]}",
  "{\"case\":11,\"outcome\":\"no_terminate\",\"hint\":\"none\"}",
]);

test("the_twelve_seed_lines_are_inside_the_subset", () => {
  assert.equal(SEED_LINES.length, 12);
  SEED_LINES.forEach((text, i) =>
    assert.equal(subsetViolation(text), null, `line ${i}`),
  );
});

const VIOLATIONS = Object.freeze([
  // The offset is the offending escape CHARACTER, not the backslash.
  Object.freeze(['{"a":"\\u0041"}', "unicode_escape", 7]),
  Object.freeze(['{"a":"\\x"}', "bad_escape", 7]),
  Object.freeze(['{"case":-1}', "minus", 8]),
  Object.freeze(['{"case":1.5}', "fraction", 9]),
  Object.freeze(['{"case":1e3}', "exponent", 9]),
  Object.freeze([`{"case":${"1".repeat(19)}}`, "too_many_digits", 26]),
  Object.freeze(['{"case":01}', "leading_zero", 8]),
  Object.freeze(["[".repeat(65), "depth", 64]),
]);

test("every_named_subset_violation_is_found_at_its_offset", () => {
  VIOLATIONS.forEach(([text, kind, at]) =>
    assert.deepEqual(subsetViolation(text), { kind, at }, kind),
  );
});

test("the_eight_simple_escapes_are_accepted", () => {
  assert.equal(subsetViolation('{"a":"\\"\\\\\\/\\b\\f\\n\\r\\t"}'), null);
});

test("a_run_of_eighteen_digits_is_accepted", () => {
  assert.equal(subsetViolation(`{"case":${"1".repeat(18)}}`), null);
});

test("sixty_four_nested_arrays_are_accepted", () => {
  assert.equal(subsetViolation("[".repeat(64) + "]".repeat(64)), null);
});

test("a_duplicate_key_is_accepted", () => {
  // Negative control for the documented drop of spec section 10.
  // core/json.ml rejects a duplicate key with E_dup_key.
  // subsetViolation is a byte scanner with no structure, and
  // JSON.parse cannot report one, so the gap is pinned here rather
  // than hidden.
  assert.equal(subsetViolation('{"case":0,"case":1}'), null);
});

const VALUE_LINE = Object.freeze({
  case: 6,
  outcome: "value",
  value: { t: "f64", hi: 1074003968, lo: 0 },
  rendered_hex: "322e35",
  js_consistent: true,
  js_hex: "6162",
  js_form: "direct",
  hint: "none",
  signals: [
    {
      id: 3,
      value: { t: "f64", hi: 1074003968, lo: 0 },
      debug_hex: "322e35",
    },
  ],
});

test("read_line_accepts_the_three_input_shapes", () => {
  const value = readLine(structuredClone(VALUE_LINE));
  assert.equal(value.ok, true);
  assert.equal(value.value.kind, "value");
  assert.equal(value.value.caseIndex, 6);
  assert.equal(value.value.signals[0].id, 3);
  const panic = readLine({
    case: 5,
    outcome: "panic",
    class: "unwrap",
    msg_hex: "626f6f6d",
    js_hex: "6162",
    js_form: "closure",
    hint: "none",
    signals: [],
  });
  assert.equal(panic.ok, true);
  assert.equal(panic.value.kind, "panic");
  const noTerminate = readLine({
    case: 11,
    outcome: "no_terminate",
    hint: "none",
  });
  assert.deepEqual({ ...noTerminate.value }, {
    kind: "no_terminate",
    caseIndex: 11,
    hint: "none",
  });
});

test("read_line_accepts_a_line_with_no_js_hex", () => {
  const line = structuredClone(VALUE_LINE);
  delete line.js_hex;
  const read = readLine(line);
  assert.equal(read.ok, true);
  assert.equal(read.value.jsHex, null);
});

test("read_line_names_every_refusal", () => {
  const bad = (patch) => {
    const line = structuredClone(VALUE_LINE);
    return readLine({ ...line, ...patch });
  };
  assert.deepEqual(readLine(null), { ok: false, error: "line" });
  assert.deepEqual(bad({ case: "6" }), { ok: false, error: "case" });
  assert.deepEqual(bad({ outcome: "nope" }), { ok: false, error: "outcome" });
  assert.deepEqual(bad({ extra: 1 }), { ok: false, error: "keys" });
  assert.deepEqual(bad({ rendered_hex: "AB" }), { ok: false, error: "hex" });
  assert.deepEqual(bad({ js_consistent: 1 }), {
    ok: false,
    error: "js_consistent",
  });
  assert.deepEqual(bad({ js_form: "wat" }), { ok: false, error: "js_form" });
  assert.deepEqual(bad({ hint: "wat" }), { ok: false, error: "hint" });
  assert.deepEqual(bad({ value: { t: "wat" } }), {
    ok: false,
    error: "value_shape",
  });
  assert.deepEqual(bad({ signals: [{ id: 1 }] }), {
    ok: false,
    error: "signals",
  });
});

test("out_line_builds_the_six_shapes_in_the_key_order_of_section_3_2", () => {
  assert.equal(
    outLine({
      kind: "value",
      caseIndex: 0,
      value: '{"t":"f64","hi":1073217536,"lo":0}',
      rendered: { kind: "utf8", hex: "312e35" },
      jsForm: "direct",
      hint: "none",
      signals: [],
    }),
    '{"case":0,"outcome":"value","value":{"t":"f64","hi":1073217536,"lo":0},"rendered_hex":"312e35","js_form":"direct","hint":"none","signals":[]}',
  );
  assert.equal(
    outLine({
      kind: "panic",
      caseIndex: 9,
      class: "expect",
      msg: { kind: "utf8", hex: "626f6f6d" },
      jsForm: "closure",
      hint: "expect",
      signals: [],
    }),
    '{"case":9,"outcome":"panic","class":"expect","msg_hex":"626f6f6d","js_form":"closure","hint":"expect","signals":[]}',
  );
  assert.equal(
    outLine({
      kind: "js_error",
      caseIndex: 2,
      name: { kind: "utf8", hex: "547970654572726f72" },
      msg: { kind: "utf8", hex: "626f6f6d" },
      jsForm: "direct",
      hint: "none",
      signals: [],
    }),
    '{"case":2,"outcome":"js_error","name_hex":"547970654572726f72","msg_hex":"626f6f6d","js_form":"direct","hint":"none","signals":[]}',
  );
  assert.equal(
    outLine({ kind: "no_terminate", caseIndex: 11, hint: "none" }),
    '{"case":11,"outcome":"no_terminate","hint":"none"}',
  );
  assert.equal(
    outLine({ kind: "skipped", caseIndex: 11 }),
    '{"case":11,"outcome":"skipped","reason":"no_js"}',
  );
  assert.equal(
    outLine({
      kind: "driver_error",
      caseIndex: 3,
      error: "hex",
      detailHex: "6162",
    }),
    '{"case":3,"outcome":"driver_error","error":"hex","detail_hex":"6162"}',
  );
});

test("out_line_carries_the_wire_u32_ids_and_never_a_uuid", () => {
  assert.equal(
    outLine({
      kind: "value",
      caseIndex: 6,
      value: '{"t":"unit"}',
      rendered: { kind: "utf8", hex: "" },
      jsForm: "closure",
      hint: "none",
      signals: [
        { id: 4, value: '{"t":"bool","v":false}' },
        { id: 3, value: '{"t":"f64","hi":1074003968,"lo":0}' },
      ],
    }),
    '{"case":6,"outcome":"value","value":{"t":"unit"},"rendered_hex":"","js_form":"closure","hint":"none","signals":[{"id":4,"value":{"t":"bool","v":false}},{"id":3,"value":{"t":"f64","hi":1074003968,"lo":0}}]}',
  );
});

test("a_lossy_text_replaces_the_utf8_key_with_the_utf16_pair", () => {
  assert.equal(
    outLine({
      kind: "value",
      caseIndex: 1,
      value: '{"t":"str","utf16_hex":"d800","lossy":true}',
      rendered: { kind: "utf16", hex: "d800" },
      jsForm: "direct",
      hint: "none",
      signals: [],
    }),
    '{"case":1,"outcome":"value","value":{"t":"str","utf16_hex":"d800","lossy":true},"rendered_utf16_hex":"d800","lossy":true,"js_form":"direct","hint":"none","signals":[]}',
  );
});

test("two_lossy_texts_carry_the_lossy_marker_once", () => {
  assert.equal(
    outLine({
      kind: "js_error",
      caseIndex: 4,
      name: { kind: "utf16", hex: "d800" },
      msg: { kind: "utf16", hex: "dc00" },
      jsForm: "direct",
      hint: "none",
      signals: [],
    }),
    '{"case":4,"outcome":"js_error","name_utf16_hex":"d800","msg_utf16_hex":"dc00","lossy":true,"js_form":"direct","hint":"none","signals":[]}',
  );
});

test("an_unknown_record_kind_becomes_a_named_driver_error_line", () => {
  assert.equal(
    outLine({ kind: "wat", caseIndex: 7 }),
    '{"case":7,"outcome":"driver_error","error":"unknown_record","detail_hex":"776174"}',
  );
});

test("every_output_line_stays_inside_the_subset", () => {
  const built = [
    outLine({
      kind: "value",
      caseIndex: 0,
      value: '{"t":"f64","hi":1073217536,"lo":0}',
      rendered: { kind: "utf8", hex: "312e35" },
      jsForm: "direct",
      hint: "none",
      signals: [{ id: 3, value: '{"t":"bool","v":true}' }],
    }),
    outLine({ kind: "skipped", caseIndex: 11 }),
  ];
  built.forEach((text) => assert.equal(subsetViolation(text), null));
});
