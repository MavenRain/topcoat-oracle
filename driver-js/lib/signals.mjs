// Join wire signal ids to clone UUIDs using each binding's Rust Debug.
// JS occurrence order carries no identity: bindings can be unused,
// repeated, or read in a different order, and strings can look like JS.
import { bytesOfHex, hexOfBytes } from "./hex.mjs";
import { stringOfUtf8 } from "./text.mjs";

const ENCODER = new TextEncoder();
const DETAIL_BYTES = 64;
// The pinned clone derives Debug for Signal and SignalId.  Read only
// the outer id, with its exact prefix and canonical lowercase UUID.
// The value is opaque and may itself contain arbitrary Signal text.
const SIGNAL_DEBUG =
  /^Signal \{ id: SignalId\(([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\), value: [\s\S]+ \}$/;

/**
 * A stable named refusal with a bounded UTF-8 diagnostic.
 * @param {string} error the driver error name
 * @param {string} detail the diagnostic text
 * @returns {{ok: false, error: string, detailHex: string}} the failure
 */
const failure = (error, detail) => ({
  ok: false,
  error,
  detailHex: hexOfBytes(ENCODER.encode(detail).slice(0, DETAIL_BYTES)),
});

/**
 * Decode the UUID of one binding, without searching its value text.
 * @param {unknown} debugHex the Rust Debug encoded as lowercase hex
 * @param {number} at the record's position for diagnostics
 * @returns {{ok: true, value: string} | {ok: false, error: string, detailHex: string}}
 *   the UUID, or a named failure
 */
const uuidOf = (debugHex, at) => {
  const detail = `record ${at}`;
  return typeof debugHex !== "string"
    ? failure("signal_debug_hex", detail)
    : ((bytes) =>
        bytes.ok === false
          ? failure("signal_debug_hex", detail)
          : ((text) =>
              text.ok === false
                ? failure("signal_debug_utf8", detail)
                : ((matched) =>
                    matched === null || matched[0].length !== text.value.length
                      ? failure("signal_debug", detail)
                      : { ok: true, value: matched[1] })(
                    SIGNAL_DEBUG.exec(text.value),
                  ))(stringOfUtf8(bytes.value)))(bytesOfHex(debugHex));
};

/**
 * Pair one binding's wire id and value with its own Debug UUID.
 * @param {unknown} one the wire signal record
 * @param {number} at the record's position for diagnostics
 * @returns {{ok: true, value: object} | {ok: false, error: string, detailHex: string}}
 *   the immutable pair, or a named failure
 */
const pairOne = (one, at) =>
  typeof one !== "object" ||
  one === null ||
  Array.isArray(one) ||
  Number.isSafeInteger(one.id) === false ||
  one.id < 0
    ? failure("signal_id", `record ${at}`)
    : ((uuid) =>
        uuid.ok === false
          ? uuid
          : {
              ok: true,
              value: Object.freeze({
                id: one.id,
                uuid: uuid.value,
                value: one.value,
              }),
            })(uuidOf(one.debugHex, at));

/**
 * Refuse duplicate identities before any registry seeding can occur.
 * The Set keeps the valid path linear; locating the repeated entry is
 * needed only for a malformed wire and its diagnostic.
 * @param {readonly object[]} pairs the validated bindings in wire order
 * @param {"id" | "uuid"} key the identity to check
 * @returns {{ok: false, error: string, detailHex: string} | null} the failure
 */
const duplicate = (pairs, key) => {
  const values = pairs.map((one) => one[key]);
  return new Set(values).size === values.length
    ? null
    : failure(
        `signal_duplicate_${key}`,
        `${values.find((value, at) => values.indexOf(value) !== at)}`,
      );
};

/**
 * Pair every declared signal, preserving wire order and unused entries.
 * No JS scan or positional fallback is involved.  The clone's actual
 * hydration reports a JS reference to an unregistered UUID.
 * @param {readonly object[]} signals the decoded wire signal records
 * @returns {{ok: true, value: readonly object[]} | {ok: false, error: string, detailHex: string}}
 *   the immutable bindings, or a named driver error
 */
export const pairSignals = (signals) =>
  ((read) =>
    read.find((one) => one.ok === false) ??
    ((pairs) =>
      duplicate(pairs, "id") ??
      duplicate(pairs, "uuid") ?? {
        ok: true,
        value: Object.freeze(pairs),
      })(read.map((one) => one.value)))(signals.map(pairOne));
