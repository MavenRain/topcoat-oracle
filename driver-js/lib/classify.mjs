// A port of driver-rs/harness.rs:224-237, arm for arm and in the same
// order.  It is a PORT, not a translation: the Rust spellings
// "Option::unwrap()" and "Result::unwrap()" with two colons stay.
//
// Rust, harness.rs:224-237                            | JS, this file
// msg == SIGNAL_WRITE_MSG => SignalWrite              | msg === SIGNAL_WRITE_MSG -> signal_write
// starts_with("called `Option::unwrap()`") => Unwrap  | startsWith(...) -> unwrap
// starts_with("called `Result::unwrap()`") => Unwrap  | startsWith(...) -> unwrap
// starts_with("called `Result::unwrap_err()`")        | startsWith(...) -> unwrap_err
//   => UnwrapErr                                      |
// hint Expect => Expect                               | HINT_CLASS.expect -> expect
// hint ExpectErr => ExpectErr                         | HINT_CLASS.expect_err -> expect_err
// hint Both => Other                                  | HINT_CLASS.both -> other
// hint None => Other                                  | HINT_CLASS.none -> other
//
// The consequence is deliberate.  The surrogates throw
// "called `Option.unwrap()` on a `None` value" with a DOT, which
// matches no prefix arm and classifies as other.  That divergence is
// the milestone's first finding.  Do not "fix" it here.

/** The message harness.rs:35 pins for a server-side signal write. */
export const SIGNAL_WRITE_MSG =
  "expressions in which a signal is written to cannot be run server-side";

const ARMS = Object.freeze([
  Object.freeze({ owns: (msg) => msg === SIGNAL_WRITE_MSG, class: "signal_write" }),
  Object.freeze({
    owns: (msg) => msg.startsWith("called `Option::unwrap()`"),
    class: "unwrap",
  }),
  Object.freeze({
    owns: (msg) => msg.startsWith("called `Result::unwrap()`"),
    class: "unwrap",
  }),
  Object.freeze({
    owns: (msg) => msg.startsWith("called `Result::unwrap_err()`"),
    class: "unwrap_err",
  }),
]);

const HINT_CLASS = Object.freeze({
  expect: "expect",
  expect_err: "expect_err",
  both: "other",
  none: "other",
});

/**
 * Classify a panic message, prefix tests first and the hint last.
 * @param {string} msg the panic message
 * @param {string} hint the wire hint: none, expect, expect_err or both
 * @returns {string} unwrap, expect, unwrap_err, expect_err, signal_write or other
 */
export function classify(msg, hint) {
  const arm = ARMS.find((candidate) => candidate.owns(msg));
  return arm === undefined
    ? Object.hasOwn(HINT_CLASS, hint)
      ? HINT_CLASS[hint]
      : "other"
    : arm.class;
}
