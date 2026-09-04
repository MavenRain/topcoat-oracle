// The Value form, both directions.  encodeValue turns a live surrogate
// into the wire JSON the Rust writer emits for the same value
// (harness.rs:518-566).  valueJson re-emits a DECODED wire Value in the
// same fixed key order, and readValue is its validator.
//
// encodeValue takes the surrogate classifier as an argument, so this
// module stays pure and the tests need no clone import.  Every read
// goes through the surrogate's public dehydrate().  Nothing reads a
// private field: TypeScript's private is erased by the transform, so a
// reader that reached in would keep working after a rename and would
// then report the wrong value.
import { bitsOfNumber } from "./bits.mjs";
import { utf8OfString } from "./text.mjs";

const HEX = /^[0-9a-f]*$/;

/**
 * The constructor name of a value, or the empty string.
 * @param {unknown} v the value to name
 * @returns {string} the constructor name
 */
const nameOf = (v) =>
  v === null || v === undefined || v.constructor === undefined
    ? ""
    : v.constructor.name;

/**
 * Wrap an encoded inner value in a one-key tag.
 * @param {string} tag the wire tag: some, ok or err
 * @param {object} encoded the encoded inner value
 * @returns {object} the wrapped result, or the inner failure
 */
const wrap = (tag, encoded) =>
  encoded.ok === false
    ? encoded
    : { ok: true, value: `{"t":"${tag}","v":${encoded.value}}` };

/**
 * The wire JSON of a raw JS string, lossy pair included.
 * @param {string} raw the string to encode
 * @returns {{ok: true, value: string}} the wire JSON
 */
const strJson = (raw) => {
  const text = utf8OfString(raw);
  return {
    ok: true,
    value:
      text.kind === "utf8"
        ? `{"t":"str","hex":"${text.hex}"}`
        : `{"t":"str","utf16_hex":"${text.hex}","lossy":true}`,
  };
};

/**
 * Encode one live surrogate as the wire Value JSON.
 * @param {unknown} v the surrogate, or undefined for unit
 * @param {(v: unknown) => string} kindOf the surrogate classifier
 * @returns {{ok: true, value: string} | {ok: false, error: string, detail: string}}
 *   the wire JSON, or a named driver error
 */
export function encodeValue(v, kindOf) {
  const kind = kindOf(v);
  switch (kind) {
    case "unit":
      return { ok: true, value: '{"t":"unit"}' };
    case "f64": {
      const halves = bitsOfNumber(v.dehydrate());
      return {
        ok: true,
        value: `{"t":"f64","hi":${halves.hi},"lo":${halves.lo}}`,
      };
    }
    case "bool":
      return {
        ok: true,
        value: `{"t":"bool","v":${v.dehydrate() === true ? "true" : "false"}}`,
      };
    case "str":
      return strJson(v.dehydrate());
    case "option": {
      const inner = v.dehydrate().v;
      return inner === null
        ? { ok: true, value: '{"t":"none"}' }
        : wrap("some", encodeValue(inner, kindOf));
    }
    case "result": {
      const dehydrated = v.dehydrate();
      return "ok" in dehydrated
        ? wrap("ok", encodeValue(dehydrated.ok, kindOf))
        : wrap("err", encodeValue(dehydrated.err, kindOf));
    }
    case "signal":
      return { ok: false, error: "unknown_surrogate", detail: nameOf(v) };
    case "function":
      return { ok: false, error: "function_value", detail: "function" };
    case "unknown":
      return { ok: false, error: "unknown_surrogate", detail: nameOf(v) };
    default:
      return { ok: false, error: "unknown_kind", detail: `${kind}` };
  }
}

/**
 * True when the node is a plain object with exactly these keys.
 * @param {unknown} node the node to check
 * @param {readonly string[]} keys the expected key set
 * @returns {boolean} true when the key sets are equal
 */
const hasKeys = (node, keys) =>
  typeof node === "object" &&
  node !== null &&
  Array.isArray(node) === false &&
  Object.keys(node).length === keys.length &&
  keys.every((key) => Object.hasOwn(node, key));

const isUint32 = (n) => Number.isInteger(n) && n >= 0 && n <= 4294967295;
const isHex = (s) => typeof s === "string" && HEX.test(s);

/**
 * A named value_shape failure.
 * @param {string} detail what was wrong
 * @returns {{ok: false, error: "value_shape", detail: string}} the failure
 */
const shape = (detail) => ({ ok: false, error: "value_shape", detail });

const VARIANTS = Object.freeze({
  unit: (node) =>
    hasKeys(node, ["t"]) ? { ok: true, value: '{"t":"unit"}' } : shape("unit"),
  none: (node) =>
    hasKeys(node, ["t"]) ? { ok: true, value: '{"t":"none"}' } : shape("none"),
  closure: (node) =>
    hasKeys(node, ["t"])
      ? { ok: true, value: '{"t":"closure"}' }
      : shape("closure"),
  f64: (node) =>
    hasKeys(node, ["t", "hi", "lo"]) &&
    isUint32(node.hi) &&
    isUint32(node.lo)
      ? { ok: true, value: `{"t":"f64","hi":${node.hi},"lo":${node.lo}}` }
      : shape("f64"),
  bool: (node) =>
    hasKeys(node, ["t", "v"]) && typeof node.v === "boolean"
      ? { ok: true, value: `{"t":"bool","v":${node.v === true ? "true" : "false"}}` }
      : shape("bool"),
  str: (node) =>
    hasKeys(node, ["t", "hex"]) && isHex(node.hex)
      ? { ok: true, value: `{"t":"str","hex":"${node.hex}"}` }
      : hasKeys(node, ["t", "utf16_hex", "lossy"]) &&
          isHex(node.utf16_hex) &&
          node.lossy === true
        ? {
            ok: true,
            value: `{"t":"str","utf16_hex":"${node.utf16_hex}","lossy":true}`,
          }
        : shape("str"),
  some: (node) => nested("some", node),
  ok: (node) => nested("ok", node),
  err: (node) => nested("err", node),
  tuple: (node) =>
    hasKeys(node, ["t", "vs"]) && Array.isArray(node.vs)
      ? ((parts) =>
          parts.find((part) => part.ok === false) ??
          {
            ok: true,
            value: `{"t":"tuple","vs":[${parts.map((part) => part.value).join(",")}]}`,
          })(node.vs.map((child) => valueJson(child)))
      : shape("tuple"),
});

/**
 * The shared body of the some, ok and err variants.
 * @param {string} tag the wire tag
 * @param {unknown} node the decoded node
 * @returns {object} the wire JSON result
 */
const nested = (tag, node) =>
  hasKeys(node, ["t", "v"]) ? wrap(tag, valueJson(node.v)) : shape(tag);

/**
 * Re-emit a decoded wire Value in the fixed key order.
 *
 * Deviation from spec 4.6, recorded in the build report: the declared
 * return type is a bare string.  A bare string leaves no total honest
 * answer for a tag the wire never wrote, because R14 forbids a throw
 * and a sentinel string would be silent.  The tagged result is used
 * instead, and it matches encodeValue.
 * @param {unknown} node the decoded Value node
 * @returns {{ok: true, value: string} | {ok: false, error: "value_shape", detail: string}}
 *   the wire JSON, or the named shape error
 */
export function valueJson(node) {
  const tag =
    typeof node === "object" && node !== null && Array.isArray(node) === false
      ? node.t
      : "";
  return typeof tag === "string" && Object.hasOwn(VARIANTS, tag)
    ? VARIANTS[tag](node)
    : shape(`${tag}`);
}

/**
 * Validate a decoded wire Value.
 * @param {unknown} node the decoded Value node
 * @returns {{ok: true, value: unknown} | {ok: false, error: "value_shape", detail: string}}
 *   the node itself, or the named shape error
 */
export function readValue(node) {
  const emitted = valueJson(node);
  return emitted.ok === true ? { ok: true, value: node } : emitted;
}
