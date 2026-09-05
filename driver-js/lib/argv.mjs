// The CLI flags.  Every arm is explicit: no prefix matching, no
// clustering, no "=" form.  A repeated flag, an unknown token, a flag
// with no value and a missing --in or --out are all usage errors, the
// way harness.rs:38-39 treats the same flags on the Rust side.
import { fileURLToPath } from "node:url";
import { plantOfName } from "./plant.mjs";

/** The one-line usage text, which names every flag. */
export const USAGE =
  "usage: driver.mjs --in <jsonl> --out <jsonl> [--clone <dir>] [--timeout-ms N] [--startup-timeout-ms N] [--from I] [--to J] [--plant <name>]";

/** The clone root the m24 gate also checks: <repo>/../topcoat. */
export const DEFAULT_CLONE = fileURLToPath(
  new URL("../../../topcoat/", import.meta.url),
).replace(/\/$/, "");

const DIGITS = /^[0-9]+$/;

const DEFAULTS = Object.freeze({
  inPath: null,
  outPath: null,
  clonePath: DEFAULT_CLONE,
  timeoutMs: 2000,
  // The startup budget is generous because it covers the cold start of
  // one worker, which is the transform of the clone TypeScript and
  // grows with the load on the machine.  It is not the case budget and
  // it never stands in for one.
  startupTimeoutMs: 30000,
  fromCase: 0,
  toCase: Number.MAX_SAFE_INTEGER,
  // null and not "none", for the same reason Plant.of_string rejects
  // "none": there must be no spelling that selects the unplanted run.
  plant: null,
});

/**
 * Read a path argument.
 * @param {string} raw the token
 * @returns {{ok: true, value: string} | {ok: false, error: string}} the path
 */
const readPath = (raw) =>
  raw.length === 0
    ? { ok: false, error: "an empty path" }
    : { ok: true, value: raw };

/**
 * Read a non-negative integer inside the safe range.
 * @param {string} raw the token
 * @returns {{ok: true, value: number} | {ok: false, error: string}} the integer
 */
const readIndex = (raw) =>
  DIGITS.test(raw) === false
    ? { ok: false, error: `not a non-negative integer: ${raw}` }
    : Number(raw) > Number.MAX_SAFE_INTEGER
      ? { ok: false, error: `above Number.MAX_SAFE_INTEGER: ${raw}` }
      : { ok: true, value: Number(raw) };

/**
 * Read a timeout in milliseconds.  Zero is a usage error: the cap is
 * never removed.
 * @param {string} raw the token
 * @returns {{ok: true, value: number} | {ok: false, error: string}} the timeout
 */
const readTimeout = (raw) =>
  ((index) =>
    index.ok === false
      ? index
      : index.value === 0
        ? { ok: false, error: "--timeout-ms must be at least 1" }
        : index)(readIndex(raw));

/**
 * Read a plant name against the closed table.  An unknown name is a
 * usage error and never a silent unplanted run.
 * @param {string} raw the token
 * @returns {{ok: true, value: object} | {ok: false, error: string}} the plant
 */
const readPlant = (raw) =>
  ((plant) =>
    plant === null
      ? { ok: false, error: `unknown plant: ${raw}` }
      : { ok: true, value: plant })(plantOfName(raw));

const FLAGS = Object.freeze({
  "--in": Object.freeze({
    read: readPath,
    apply: (options, value) => ({ ...options, inPath: value }),
  }),
  "--out": Object.freeze({
    read: readPath,
    apply: (options, value) => ({ ...options, outPath: value }),
  }),
  "--clone": Object.freeze({
    read: readPath,
    apply: (options, value) => ({ ...options, clonePath: value }),
  }),
  "--timeout-ms": Object.freeze({
    read: readTimeout,
    apply: (options, value) => ({ ...options, timeoutMs: value }),
  }),
  "--startup-timeout-ms": Object.freeze({
    read: readTimeout,
    apply: (options, value) => ({ ...options, startupTimeoutMs: value }),
  }),
  "--from": Object.freeze({
    read: readIndex,
    apply: (options, value) => ({ ...options, fromCase: value }),
  }),
  "--to": Object.freeze({
    read: readIndex,
    apply: (options, value) => ({ ...options, toCase: value }),
  }),
  "--plant": Object.freeze({
    read: readPlant,
    apply: (options, value) => ({ ...options, plant: value }),
  }),
});

/**
 * Take the next token as a flag name.
 * @param {object} acc the frozen accumulator
 * @param {string} token the token
 * @returns {object} the next accumulator
 */
const beginFlag = (acc, token) =>
  Object.hasOwn(FLAGS, token) === false
    ? { ...acc, error: `unknown token: ${token}` }
    : acc.seen.includes(token)
      ? { ...acc, error: `repeated flag: ${token}` }
      : { ...acc, pending: token, seen: Object.freeze([...acc.seen, token]) };

/**
 * Take the next token as the pending flag's value.
 * @param {object} acc the frozen accumulator
 * @param {string} token the token
 * @returns {object} the next accumulator
 */
const takeValue = (acc, token) =>
  ((flag, read) =>
    read.ok === false
      ? { ...acc, error: `${acc.pending}: ${read.error}` }
      : {
          ...acc,
          pending: null,
          options: Object.freeze(flag.apply(acc.options, read.value)),
        })(FLAGS[acc.pending], FLAGS[acc.pending].read(token));

/**
 * Parse the argument vector.
 * @param {readonly string[]} args the arguments after the script name
 * @returns {{ok: true, value: object} | {ok: false, error: string}}
 *   the frozen options, or a usage error
 */
export function parseArgv(args) {
  const folded = args.reduce(
    (acc, token) =>
      acc.error !== null
        ? acc
        : acc.pending === null
          ? beginFlag(acc, token)
          : takeValue(acc, token),
    { pending: null, seen: Object.freeze([]), options: DEFAULTS, error: null },
  );
  return folded.error !== null
    ? { ok: false, error: folded.error }
    : folded.pending !== null
      ? { ok: false, error: `flag with no value: ${folded.pending}` }
      : folded.options.inPath === null
        ? { ok: false, error: "missing --in" }
        : folded.options.outPath === null
          ? { ok: false, error: "missing --out" }
          : { ok: true, value: folded.options };
}
