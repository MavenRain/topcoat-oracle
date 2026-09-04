// spec section 8.5.  Twelve pairs, derived from the arms of classify
// itself: harness.rs carries no classify unit tests (spec section 0.9).
import test from "node:test";
import assert from "node:assert/strict";
import { classify, SIGNAL_WRITE_MSG } from "../lib/classify.mjs";

test("the_signal_write_message_classifies_as_signal_write", () => {
  assert.equal(classify(SIGNAL_WRITE_MSG, "none"), "signal_write");
});

test("the_message_beats_the_hint", () => {
  assert.equal(classify(SIGNAL_WRITE_MSG, "expect"), "signal_write");
});

test("option_unwrap_classifies_as_unwrap", () => {
  assert.equal(
    classify("called `Option::unwrap()` on a `None` value", "none"),
    "unwrap",
  );
});

test("result_unwrap_classifies_as_unwrap", () => {
  assert.equal(
    classify("called `Result::unwrap()` on an `Err` value: 1.5", "none"),
    "unwrap",
  );
});

test("result_unwrap_err_classifies_as_unwrap_err", () => {
  assert.equal(
    classify('called `Result::unwrap_err()` on an `Ok` value: "ok"', "none"),
    "unwrap_err",
  );
});

test("the_bare_prefix_is_enough", () => {
  assert.equal(classify("called `Option::unwrap()`", "none"), "unwrap");
});

test("the_expect_err_hint_classifies_as_expect_err", () => {
  assert.equal(classify("nope: ok", "expect_err"), "expect_err");
});

test("the_expect_hint_classifies_as_expect", () => {
  assert.equal(classify("boom", "expect"), "expect");
});

test("the_both_hint_classifies_as_other", () => {
  assert.equal(classify("nope: ok", "both"), "other");
});

test("no_prefix_and_no_hint_classifies_as_other", () => {
  assert.equal(classify("boom", "none"), "other");
});

test("the_empty_message_classifies_as_other", () => {
  assert.equal(classify("", "none"), "other");
});

test("the_dotted_js_spelling_classifies_as_other", () => {
  // Divergence D1, pinned on purpose.  The surrogates throw
  // "Option.unwrap()" with a dot;  the port keeps the Rust spelling
  // "Option::unwrap()" with two colons, so this message matches no
  // prefix arm.  A future change that returns "unwrap" here breaks this
  // test on purpose.
  assert.equal(
    classify("called `Option.unwrap()` on a `None` value", "none"),
    "other",
  );
});
