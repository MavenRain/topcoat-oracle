// spec section 8.7
import test from "node:test";
import assert from "node:assert/strict";
import { parseArgv, USAGE, DEFAULT_CLONE } from "../lib/argv.mjs";

test("the_full_flag_set_parses", () => {
  const parsed = parseArgv([
    "--in",
    "/tmp/in.jsonl",
    "--out",
    "/tmp/out.jsonl",
    "--clone",
    "/tmp/topcoat",
    "--timeout-ms",
    "5000",
    "--startup-timeout-ms",
    "45000",
    "--from",
    "2",
    "--to",
    "9",
  ]);
  assert.equal(parsed.ok, true);
  assert.deepEqual({ ...parsed.value }, {
    inPath: "/tmp/in.jsonl",
    outPath: "/tmp/out.jsonl",
    clonePath: "/tmp/topcoat",
    timeoutMs: 5000,
    startupTimeoutMs: 45000,
    fromCase: 2,
    toCase: 9,
    plant: null,
  });
});

test("the_defaults_stand_when_only_in_and_out_are_given", () => {
  const parsed = parseArgv(["--in", "a.jsonl", "--out", "b.jsonl"]);
  assert.equal(parsed.ok, true);
  assert.deepEqual({ ...parsed.value }, {
    inPath: "a.jsonl",
    outPath: "b.jsonl",
    clonePath: DEFAULT_CLONE,
    timeoutMs: 2000,
    startupTimeoutMs: 30000,
    fromCase: 0,
    toCase: Number.MAX_SAFE_INTEGER,
    plant: null,
  });
});

test("the_startup_budget_is_bigger_than_the_case_budget", () => {
  const parsed = parseArgv(["--in", "a.jsonl", "--out", "b.jsonl"]);
  assert.equal(parsed.value.startupTimeoutMs > parsed.value.timeoutMs, true);
});

test("the_default_clone_is_the_sibling_checkout", () => {
  assert.equal(DEFAULT_CLONE.endsWith("/topcoat"), true);
});

test("the_usage_line_names_every_flag", () => {
  [
    "--in",
    "--out",
    "--clone",
    "--timeout-ms",
    "--startup-timeout-ms",
    "--from",
    "--to",
  ].forEach((flag) => assert.equal(USAGE.includes(flag), true));
});

const NEGATIVES = Object.freeze([
  Object.freeze(["--timeout-ms 0", ["--in", "a", "--out", "b", "--timeout-ms", "0"]]),
  Object.freeze(["--timeout-ms x", ["--in", "a", "--out", "b", "--timeout-ms", "x"]]),
  Object.freeze(["--timeout-ms -1", ["--in", "a", "--out", "b", "--timeout-ms", "-1"]]),
  Object.freeze([
    "--timeout-ms above the safe range",
    ["--in", "a", "--out", "b", "--timeout-ms", "9007199254740993"],
  ]),
  Object.freeze([
    "--startup-timeout-ms 0",
    ["--in", "a", "--out", "b", "--startup-timeout-ms", "0"],
  ]),
  Object.freeze([
    "--startup-timeout-ms x",
    ["--in", "a", "--out", "b", "--startup-timeout-ms", "x"],
  ]),
  Object.freeze([
    "a repeated --startup-timeout-ms",
    [
      "--in",
      "a",
      "--out",
      "b",
      "--startup-timeout-ms",
      "1",
      "--startup-timeout-ms",
      "2",
    ],
  ]),
  Object.freeze(["a repeated --in", ["--in", "a", "--in", "c", "--out", "b"]]),
  Object.freeze(["an unknown token", ["--in", "a", "--out", "b", "--wat"]]),
  Object.freeze(["a missing --out", ["--in", "a"]]),
  Object.freeze(["a flag with no value", ["--in", "a", "--out"]]),
  Object.freeze(["the empty array", []]),
]);

test("every_usage_error_is_reported_and_named", () => {
  NEGATIVES.forEach(([name, args]) => {
    const parsed = parseArgv(args);
    assert.equal(parsed.ok, false, name);
    assert.equal(typeof parsed.error, "string", name);
    assert.equal(parsed.error.length > 0, true, name);
  });
});

test("a_missing_in_is_named", () => {
  assert.deepEqual(parseArgv(["--out", "b"]), {
    ok: false,
    error: "missing --in",
  });
});
