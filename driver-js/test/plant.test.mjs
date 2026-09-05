import test from "node:test";
import assert from "node:assert/strict";
import {
  plantOfName,
  plantedContext,
  SIGNAL_GET_PLUS_ONE,
} from "../lib/plant.mjs";

// Two stubs and a kit that recognises them.  No clone import, so this
// test runs without the topcoat checkout.
class StubSignal {
  constructor(value) {
    this.value = value;
  }
  get() {
    return this.value;
  }
}
class StubNumber {
  constructor(n) {
    this.n = n;
  }
  dehydrate() {
    return this.n;
  }
}
const KIT = Object.freeze({
  isSignal: (v) => v instanceof StubSignal,
  isNumber: (v) => v instanceof StubNumber,
  plusOne: (v) => new StubNumber(v.dehydrate() + 1),
});
const contextOf = (produced) => ({ hydrate: () => produced, tag: "real" });

test("an unknown plant name is null", () => {
  assert.equal(plantOfName("nope"), null);
  assert.equal(plantOfName("display_sign"), null);
  assert.equal(plantOfName(""), null);
});

test("the one plant name resolves", () => {
  assert.equal(plantOfName(SIGNAL_GET_PLUS_ONE).name, SIGNAL_GET_PLUS_ONE);
});

test("no plant returns the very same context", () => {
  const cx = contextOf(new StubSignal(new StubNumber(2.5)));
  assert.equal(plantedContext(cx, null, KIT), cx);
});

test("a number signal read gains one and the store does not", () => {
  const stored = new StubNumber(2.5);
  const signal = new StubSignal(stored);
  const cx = plantedContext(
    contextOf(signal),
    plantOfName(SIGNAL_GET_PLUS_ONE),
    KIT,
  );
  assert.equal(cx.hydrate({}).get().dehydrate(), 3.5);
  assert.equal(signal.value, stored);
  assert.equal(stored.dehydrate(), 2.5);
});

test("a non-number signal read is unchanged", () => {
  const cx = plantedContext(
    contextOf(new StubSignal("a bool surrogate")),
    plantOfName(SIGNAL_GET_PLUS_ONE),
    KIT,
  );
  assert.equal(cx.hydrate({}).get(), "a bool surrogate");
});

test("a non-signal hydration is unchanged", () => {
  const value = new StubNumber(2.5);
  const cx = plantedContext(
    contextOf(value),
    plantOfName(SIGNAL_GET_PLUS_ONE),
    KIT,
  );
  assert.equal(cx.hydrate({}), value);
});

test("the wrapper delegates every other property", () => {
  const cx = plantedContext(
    contextOf(new StubSignal(new StubNumber(1))),
    plantOfName(SIGNAL_GET_PLUS_ONE),
    KIT,
  );
  assert.equal(cx.tag, "real");
});
