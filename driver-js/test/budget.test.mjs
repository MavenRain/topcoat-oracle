// The two budgets of one case.  These vectors fail against a driver
// that keeps one budget: there the startup of a worker is charged to
// the case, and its expiry is a no_terminate line.
import test from "node:test";
import assert from "node:assert/strict";
import {
  STARTUP,
  RUNNING,
  budgetOf,
  expiryRecord,
} from "../lib/budget.mjs";

const BUDGETS = Object.freeze({ timeoutMs: 2000, startupTimeoutMs: 30000 });

test("the_startup_phase_gets_the_startup_budget", () => {
  assert.deepEqual(budgetOf(STARTUP, BUDGETS), { ok: true, value: 30000 });
});

test("the_running_phase_gets_the_case_budget", () => {
  assert.deepEqual(budgetOf(RUNNING, BUDGETS), { ok: true, value: 2000 });
});

test("the_two_budgets_are_not_the_same_number", () => {
  assert.notEqual(
    budgetOf(STARTUP, BUDGETS).value,
    budgetOf(RUNNING, BUDGETS).value,
  );
});

test("a_startup_expiry_names_startup_and_is_never_a_no_terminate", () => {
  const record = expiryRecord(STARTUP, 11, "none", BUDGETS);
  assert.equal(record.ok, true);
  assert.equal(record.value.kind, "driver_error");
  assert.equal(record.value.error, "worker_startup");
  assert.equal(record.value.caseIndex, 11);
  // The detail is the expired budget as text: "30000".
  assert.equal(record.value.detailHex, "3330303030");
});

test("a_case_expiry_is_the_no_terminate_line_with_the_hint", () => {
  assert.deepEqual(expiryRecord(RUNNING, 4, "expect", BUDGETS), {
    ok: true,
    value: { kind: "no_terminate", caseIndex: 4, hint: "expect" },
  });
});

test("an_unknown_phase_is_a_named_error_and_never_a_throw", () => {
  const phase = Object.freeze({ kind: "wat" });
  assert.deepEqual(budgetOf(phase, BUDGETS), {
    ok: false,
    error: "unknown_phase",
  });
  assert.deepEqual(expiryRecord(phase, 0, "none", BUDGETS), {
    ok: false,
    error: "unknown_phase",
  });
});
