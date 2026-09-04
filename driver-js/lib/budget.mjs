// The two budgets of one case.  One fresh worker per case is the
// isolation rule, and the price of that rule is one cold start per
// case: the worker transforms the clone TypeScript through the resolve
// hook before it can run anything.  That cold start is startup, not
// the case, so it gets its own budget.
//
// The measurement that made this file: on an idle machine the cold
// start of one worker is about 320 ms, and on the same machine under
// load it is about 7000 ms.  A single budget charged that cold start
// to the 2000 ms case budget, so a busy machine turned every case into
// a no_terminate line and lost the skipped line with them.
//
// The phase is a tagged union with two members.  The driver arms one
// timer for the budget of the phase it is in, and rearms it for the
// case budget when the worker reports that its modules are loaded.
import { hexOfBytes } from "./hex.mjs";

const ENCODER = new TextEncoder();

/** The phase a case starts in: the worker is loading its modules. */
export const STARTUP = Object.freeze({ kind: "startup" });

/** The phase after the worker reports ready: the case is running. */
export const RUNNING = Object.freeze({ kind: "running" });

/**
 * The budget of one phase, in milliseconds.
 * @param {{kind: string}} phase the phase the case is in
 * @param {{timeoutMs: number, startupTimeoutMs: number}} budgets the parsed budgets
 * @returns {{ok: true, value: number} | {ok: false, error: string}}
 *   the budget, or a named error
 */
export function budgetOf(phase, budgets) {
  switch (phase.kind) {
    case "startup":
      return { ok: true, value: budgets.startupTimeoutMs };
    case "running":
      return { ok: true, value: budgets.timeoutMs };
    default:
      return { ok: false, error: "unknown_phase" };
  }
}

/**
 * The output record an expiry of one phase produces.  A startup expiry
 * is a driver_error that names startup, never a no_terminate: the case
 * never ran, so the run holds no evidence that the case does not
 * terminate.  The detail is the budget that expired, so the log names
 * the number to raise.
 * @param {{kind: string}} phase the phase whose budget expired
 * @param {number} caseIndex the case index
 * @param {string} hint the wire hint of the case
 * @param {{timeoutMs: number, startupTimeoutMs: number}} budgets the parsed budgets
 * @returns {{ok: true, value: object} | {ok: false, error: string}}
 *   the output record, or a named error
 */
export function expiryRecord(phase, caseIndex, hint, budgets) {
  switch (phase.kind) {
    case "startup":
      return {
        ok: true,
        value: {
          kind: "driver_error",
          caseIndex,
          error: "worker_startup",
          detailHex: hexOfBytes(ENCODER.encode(`${budgets.startupTimeoutMs}`)),
        },
      };
    case "running":
      return { ok: true, value: { kind: "no_terminate", caseIndex, hint } };
    default:
      return { ok: false, error: "unknown_phase" };
  }
}
