import test from "node:test";
import assert from "node:assert/strict";
import { hexOfBytes } from "../lib/hex.mjs";
import { pairSignals } from "../lib/signals.mjs";

const FIRST = "01234567-89ab-cdef-0123-456789abcdef";
const SECOND = "fedcba98-7654-3210-fedc-ba9876543210";
const THIRD = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee";
const ENCODER = new TextEncoder();
const hex = (text) => hexOfBytes(ENCODER.encode(text));
const debug = (uuid, value = "true") =>
  `Signal { id: SignalId(${uuid}), value: ${value} }`;
const signal = (id, uuid, value = { t: "bool", v: true }) => ({
  id,
  value,
  debugHex: hex(debug(uuid)),
});
const refusal = (signals, error, detail = "record 0") =>
  assert.deepEqual(pairSignals(signals), {
    ok: false,
    error,
    detailHex: hex(detail),
  });

test("an_empty_signal_list_needs_no_JS_occurrences", () => {
  assert.deepEqual(pairSignals([]), { ok: true, value: [] });
});

test("bindings_keep_wire_order_and_each_own_UUID_when_names_are_reordered", () => {
  // Numeric wire names need not be sorted and JS can read 2 before 9.
  const signals = [signal(9, FIRST), signal(2, SECOND)];
  const paired = pairSignals(signals);
  assert.deepEqual(paired, {
    ok: true,
    value: [
      { id: 9, uuid: FIRST, value: signals[0].value },
      { id: 2, uuid: SECOND, value: signals[1].value },
    ],
  });
  assert.equal(Object.isFrozen(paired.value), true);
  paired.value.forEach((one) => assert.equal(Object.isFrozen(one), true));
});

test("unused_bindings_and_repeated_JS_reads_need_no_occurrence_count", () => {
  // JS can ignore all three bindings or read the third name repeatedly.
  // Pairing accepts only the records, so those uses cannot alter identity.
  const signals = [signal(0, FIRST), signal(4, SECOND), signal(8, THIRD)];
  const paired = pairSignals(signals);
  assert.equal(paired.ok, true);
  assert.deepEqual(paired.value.map((one) => one.id), [0, 4, 8]);
  assert.deepEqual(paired.value.map((one) => one.uuid), [FIRST, SECOND, THIRD]);
  assert.equal(paired.value[2].value, signals[2].value);
});

test("duplicate_wire_ids_and_duplicate_UUIDs_are_named_failures", () => {
  refusal([signal(2, FIRST), signal(2, SECOND)], "signal_duplicate_id", "2");
  refusal([signal(2, FIRST), signal(3, FIRST)], "signal_duplicate_uuid", FIRST);
});

test("wire_ids_must_be_nonnegative_safe_integers", () => {
  [undefined, null, "1", -1, 0.5, NaN, Infinity, 2 ** 53].forEach((id) =>
    refusal([{ ...signal(0, FIRST), id }], "signal_id"),
  );
  [null, undefined, [], true].forEach((one) => refusal([one], "signal_id"));
  [0, Number.MAX_SAFE_INTEGER].forEach((id) =>
    assert.equal(pairSignals([signal(id, FIRST)]).ok, true),
  );
});

test("missing_or_malformed_Debug_hex_is_a_named_failure", () => {
  [undefined, null, 1, [], "0", "0g", "AA"].forEach((debugHex) =>
    refusal([{ ...signal(0, FIRST), debugHex }], "signal_debug_hex"),
  );
  refusal([{ id: 0, value: { t: "unit" } }], "signal_debug_hex");
});

test("invalid_UTF8_never_becomes_replacement_text", () => {
  ["ff", "c0af", "eda080", "f4908080", `${hex(debug(FIRST))}ff`].forEach(
    (debugHex) =>
      refusal([{ ...signal(0, FIRST), debugHex }], "signal_debug_utf8"),
  );
});

test("Debug_requires_the_exact_outer_prefix_UUID_and_envelope", () => {
  const malformed = [
    "",
    ` ${debug(FIRST)}`,
    `\ufeff${debug(FIRST)}`,
    `Some(${debug(FIRST)})`,
    debug(FIRST).replace("SignalId(", "SignalId(\""),
    debug(FIRST).replace("id: ", "value: "),
    debug(FIRST).replace(", value: ", ", extra: "),
    debug(FIRST).replace(" }", ""),
    `${debug(FIRST)} trailing`,
    `${debug(FIRST)}\n`,
    debug(FIRST, ""),
    debug(FIRST.toUpperCase()),
    debug(FIRST.replaceAll("-", "0")),
    debug(FIRST.replace("a", "g")),
    debug(`${FIRST}0`),
    debug(FIRST.slice(1)),
  ];
  malformed.forEach((text) =>
    refusal([{ ...signal(0, FIRST), debugHex: hex(text) }], "signal_debug"),
  );
});

test("a_forged_Signal_inside_the_value_cannot_supply_the_outer_UUID", () => {
  const forged = JSON.stringify(debug(SECOND));
  const innerJs = JSON.stringify(`{"t":"Signal","id":"${THIRD}"}`);
  const good = pairSignals([
    { ...signal(0, FIRST), debugHex: hex(debug(FIRST, `${forged}, ${innerJs}`)) },
  ]);
  assert.equal(good.ok, true);
  assert.equal(good.value[0].uuid, FIRST);
  [forged, `String(${forged})`, debug("invalid", forged)].forEach((text) =>
    refusal([{ ...signal(0, FIRST), debugHex: hex(text) }], "signal_debug"),
  );
});

test("valid_opaque_Debug_values_can_contain_unicode_or_newlines", () => {
  const text = debug(FIRST, 'Some("\u00e9\n\u96ea")');
  const paired = pairSignals([{ ...signal(0, FIRST), debugHex: hex(text) }]);
  assert.equal(paired.ok, true);
  assert.equal(paired.value[0].uuid, FIRST);
});

test("a_bad_later_binding_reports_its_wire_position", () => {
  refusal(
    [signal(7, FIRST), { ...signal(2, SECOND), debugHex: hex("invalid") }],
    "signal_debug",
    "record 1",
  );
});
