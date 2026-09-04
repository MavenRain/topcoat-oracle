// One input line in, one output line out.  subsetViolation scans the
// raw text against the core/json.ml subset before JSON.parse sees it.
// readLine validates the key set per outcome.  outLine builds the
// output by concatenation in a fixed key order, never with
// JSON.stringify on the whole record: stringify promises no key order
// across engines and would happily emit a float or a \u escape and put
// the line outside the subset.
import { hexOfBytes } from "./hex.mjs";
import { readValue } from "./value.mjs";

const ENCODER = new TextEncoder();
const SIMPLE_ESCAPES = '"\\/bfnrt';
const MAX_DIGITS = 18;
const MAX_DEPTH = 64;
const HEX = /^[0-9a-f]*$/;
const JS_FORMS = Object.freeze(["direct", "closure", "absent"]);
const HINTS = Object.freeze(["none", "expect", "expect_err", "both"]);

const isHex = (s) => typeof s === "string" && HEX.test(s);
const isDigit = (c) => c >= "0" && c <= "9";

/**
 * A found violation, which every later step passes through unchanged.
 * @param {object} state the scan state
 * @param {string} kind the violation name
 * @param {number} at the offset of the offending character
 * @returns {object} the state carrying the violation
 */
const hit = (state, kind, at) => ({ ...state, violation: { kind, at } });

/**
 * One character of the subset scan, outside a string.
 * @param {object} state the scan state
 * @param {string} text the whole line
 * @param {string} c the character
 * @param {number} i the offset of the character
 * @returns {object} the next state
 */
const outsideString = (state, text, c, i) =>
  c === '"'
    ? { ...state, inString: true, digits: 0 }
    : c === "-"
      ? hit(state, "minus", i)
      : c === "."
        ? hit(state, "fraction", i)
        : (c === "e" || c === "E") && state.digits > 0
          ? hit(state, "exponent", i)
          : isDigit(c)
            ? state.digits === 0
              ? { ...state, digits: 1, seenDigitStart: i }
              : text[state.seenDigitStart] === "0"
                ? hit(state, "leading_zero", state.seenDigitStart)
                : state.digits + 1 > MAX_DIGITS
                  ? hit(state, "too_many_digits", i)
                  : { ...state, digits: state.digits + 1 }
            : c === "[" || c === "{"
              ? state.depth + 1 > MAX_DEPTH
                ? hit(state, "depth", i)
                : { ...state, depth: state.depth + 1, digits: 0 }
              : c === "]" || c === "}"
                ? { ...state, depth: state.depth - 1, digits: 0 }
                : { ...state, digits: 0 };

/**
 * Scan one raw line against the core/json.ml subset.  A duplicate key
 * is NOT detected: see the drop inventory, spec section 10.
 * @param {string} text the raw input line
 * @returns {null | {kind: string, at: number}} the first violation, or null
 */
export function subsetViolation(text) {
  const end = text.split("").reduce(
    (state, c, i) =>
      state.violation !== null
        ? state
        : state.escaped === true
          ? SIMPLE_ESCAPES.includes(c)
            ? { ...state, escaped: false }
            : c === "u"
              ? hit(state, "unicode_escape", i)
              : hit(state, "bad_escape", i)
          : state.inString === true
            ? c === "\\"
              ? { ...state, escaped: true }
              : c === '"'
                ? { ...state, inString: false }
                : state
            : outsideString(state, text, c, i),
    {
      inString: false,
      escaped: false,
      digits: 0,
      depth: 0,
      seenDigitStart: 0,
      violation: null,
    },
  );
  return end.violation;
}

/**
 * Read one signal entry of an input line.
 * @param {unknown} entry the decoded entry
 * @returns {{ok: true, value: object} | {ok: false, error: string}} the record
 */
const readSignal = (entry) =>
  typeof entry !== "object" ||
  entry === null ||
  Array.isArray(entry) === true ||
  Object.keys(entry).length !== 3 ||
  ["id", "value", "debug_hex"].every((key) => Object.hasOwn(entry, key)) ===
    false
    ? { ok: false, error: "signals" }
    : Number.isInteger(entry.id) === false ||
        entry.id < 0 ||
        isHex(entry.debug_hex) === false
      ? { ok: false, error: "signals" }
      : ((inner) =>
          inner.ok === false
            ? { ok: false, error: "signals" }
            : {
                ok: true,
                value: Object.freeze({
                  id: entry.id,
                  value: entry.value,
                  debugHex: entry.debug_hex,
                }),
              })(readValue(entry.value));

/**
 * Read the signals array of an input line.
 * @param {unknown} signals the decoded array
 * @returns {{ok: true, value: object[]} | {ok: false, error: string}} the records
 */
const readSignals = (signals) =>
  Array.isArray(signals) === false
    ? { ok: false, error: "signals" }
    : ((read) =>
        read.find((one) => one.ok === false) ?? {
          ok: true,
          value: Object.freeze(read.map((one) => one.value)),
        })(signals.map((entry) => readSignal(entry)));

/**
 * Check the key set of a line, with js_hex optional.
 * @param {object} parsed the decoded line
 * @param {readonly string[]} required every key the shape needs
 * @returns {boolean} true when the key set is exactly right
 */
const keysMatch = (parsed, required) =>
  required.every((key) => Object.hasOwn(parsed, key)) &&
  Object.keys(parsed).every(
    (key) => required.includes(key) || key === "js_hex",
  );

/**
 * The shared tail of the value and panic shapes.
 * @param {object} parsed the decoded line
 * @returns {{ok: true, value: object} | {ok: false, error: string}} the tail
 */
const readTail = (parsed) =>
  JS_FORMS.includes(parsed.js_form) === false
    ? { ok: false, error: "js_form" }
    : HINTS.includes(parsed.hint) === false
      ? { ok: false, error: "hint" }
      : Object.hasOwn(parsed, "js_hex") && isHex(parsed.js_hex) === false
        ? { ok: false, error: "hex" }
        : ((signals) =>
            signals.ok === false
              ? signals
              : {
                  ok: true,
                  value: Object.freeze({
                    jsForm: parsed.js_form,
                    jsHex: Object.hasOwn(parsed, "js_hex")
                      ? parsed.js_hex
                      : null,
                    hint: parsed.hint,
                    signals: signals.value,
                  }),
                })(readSignals(parsed.signals));

const SHAPES = Object.freeze({
  value: Object.freeze({
    required: Object.freeze([
      "case",
      "outcome",
      "value",
      "rendered_hex",
      "js_consistent",
      "js_form",
      "hint",
      "signals",
    ]),
    read: (parsed) =>
      isHex(parsed.rendered_hex) === false
        ? { ok: false, error: "hex" }
        : typeof parsed.js_consistent !== "boolean"
          ? { ok: false, error: "js_consistent" }
          : ((value) =>
              value.ok === false
                ? { ok: false, error: "value_shape" }
                : ((tail) =>
                    tail.ok === false
                      ? tail
                      : {
                          ok: true,
                          value: Object.freeze({
                            kind: "value",
                            caseIndex: parsed.case,
                            value: parsed.value,
                            renderedHex: parsed.rendered_hex,
                            jsConsistent: parsed.js_consistent,
                            ...tail.value,
                          }),
                        })(readTail(parsed)))(readValue(parsed.value)),
  }),
  panic: Object.freeze({
    required: Object.freeze([
      "case",
      "outcome",
      "class",
      "msg_hex",
      "js_form",
      "hint",
      "signals",
    ]),
    read: (parsed) =>
      typeof parsed.class !== "string"
        ? { ok: false, error: "class" }
        : isHex(parsed.msg_hex) === false
          ? { ok: false, error: "hex" }
          : ((tail) =>
              tail.ok === false
                ? tail
                : {
                    ok: true,
                    value: Object.freeze({
                      kind: "panic",
                      caseIndex: parsed.case,
                      class: parsed.class,
                      msgHex: parsed.msg_hex,
                      ...tail.value,
                    }),
                  })(readTail(parsed)),
  }),
  no_terminate: Object.freeze({
    required: Object.freeze(["case", "outcome", "hint"]),
    read: (parsed) =>
      HINTS.includes(parsed.hint) === false
        ? { ok: false, error: "hint" }
        : {
            ok: true,
            value: Object.freeze({
              kind: "no_terminate",
              caseIndex: parsed.case,
              hint: parsed.hint,
            }),
          },
  }),
});

/**
 * Validate one decoded input line.
 * @param {unknown} parsed the JSON.parse result of one input line
 * @returns {{ok: true, value: object} | {ok: false, error: string}}
 *   the tagged wire line, or a named error
 */
export function readLine(parsed) {
  return typeof parsed !== "object" ||
    parsed === null ||
    Array.isArray(parsed) === true
    ? { ok: false, error: "line" }
    : Number.isInteger(parsed.case) === false || parsed.case < 0
      ? { ok: false, error: "case" }
      : typeof parsed.outcome !== "string" ||
          Object.hasOwn(SHAPES, parsed.outcome) === false
        ? { ok: false, error: "outcome" }
        : keysMatch(parsed, SHAPES[parsed.outcome].required) === false
          ? { ok: false, error: "keys" }
          : SHAPES[parsed.outcome].read(parsed);
}

/**
 * The hex of a text field, with the UTF-16 key in place of the UTF-8
 * key when the text is lossy.  R8: loud, never U+FFFD.  The marker
 * itself is not written here: a record with two texts must carry the
 * marker once, and the subset of core/json.ml has no duplicate key.
 * @param {string} base the key stem: rendered, msg or name
 * @param {{kind: string, hex: string}} text the encoded text
 * @returns {string} the key and value pair, with no leading comma
 */
const textField = (base, text) =>
  text.kind === "utf16"
    ? `"${base}_utf16_hex":"${text.hex}"`
    : `"${base}_hex":"${text.hex}"`;

/**
 * The lossy marker of one record, written at most once, after the last
 * text field of the line.
 * @param {readonly {kind: string, hex: string}[]} texts every text of the record
 * @returns {string} the marker with its leading comma, or the empty string
 */
const lossyField = (texts) =>
  texts.some((text) => text.kind === "utf16") ? `,"lossy":true` : "";

/**
 * The output signals array.  It carries the WIRE u32 id, never a uuid.
 * @param {readonly {id: number, value: string}[]} signals the entries
 * @returns {string} the JSON array text
 */
const signalsField = (signals) =>
  `[${signals.map((one) => `{"id":${one.id},"value":${one.value}}`).join(",")}]`;

const OUT = Object.freeze({
  value: (record) =>
    `{"case":${record.caseIndex},"outcome":"value","value":${record.value},` +
    `${textField("rendered", record.rendered)}${lossyField([record.rendered])}` +
    `,"js_form":"${record.jsForm}",` +
    `"hint":"${record.hint}","signals":${signalsField(record.signals)}}`,
  panic: (record) =>
    `{"case":${record.caseIndex},"outcome":"panic","class":"${record.class}",` +
    `${textField("msg", record.msg)}${lossyField([record.msg])}` +
    `,"js_form":"${record.jsForm}",` +
    `"hint":"${record.hint}","signals":${signalsField(record.signals)}}`,
  js_error: (record) =>
    `{"case":${record.caseIndex},"outcome":"js_error",` +
    `${textField("name", record.name)},${textField("msg", record.msg)}` +
    `${lossyField([record.name, record.msg])},` +
    `"js_form":"${record.jsForm}","hint":"${record.hint}",` +
    `"signals":${signalsField(record.signals)}}`,
  no_terminate: (record) =>
    `{"case":${record.caseIndex},"outcome":"no_terminate","hint":"${record.hint}"}`,
  skipped: (record) =>
    `{"case":${record.caseIndex},"outcome":"skipped","reason":"no_js"}`,
  driver_error: (record) =>
    `{"case":${record.caseIndex},"outcome":"driver_error",` +
    `"error":"${record.error}","detail_hex":"${record.detailHex}"}`,
});

/**
 * Build one output line.  The total fallback returns a driver_error
 * line naming the unknown record kind, which is a named error in the
 * output's own vocabulary and never a throw.
 * @param {object} record the tagged output record
 * @returns {string} one output line, with no trailing newline
 */
export function outLine(record) {
  return Object.hasOwn(OUT, record.kind)
    ? OUT[record.kind](record)
    : `{"case":${Number.isInteger(record.caseIndex) ? record.caseIndex : 0},` +
        `"outcome":"driver_error","error":"unknown_record","detail_hex":"` +
        `${hexOfBytes(ENCODER.encode(`${record.kind}`))}"}`;
}
