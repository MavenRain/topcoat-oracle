// M25 worker.  One case, one worker thread, one message out.  This is
// the only file in our tree that imports the clone.  It receives
// workerData = {lineText} and the clone root through --clone in its own
// argv, posts {kind: "ready"} once its clone modules are loaded, then
// posts {kind: "line", text} once, and returns.  It never writes a file
// and never touches stdout.  See spec section 5.
//
// The four clone modules are the headless surface: context.ts,
// signal.ts, surrogate/index.ts and surrogate/panic.ts.  panic.ts is
// imported directly as well as through the index re-export, so the
// Panic identity the catch tests is unambiguous.  Nothing from
// runtime.ts, scope.ts, scan.ts, text.ts, binding.ts, event.ts,
// comment.ts or view.ts is imported: those are the DOM-coupled modules.
//
// The evaluation is the production form of binding.ts:27, event.ts:14,
// text.ts:15 and scope.ts:93, semicolon included.  The call is plain,
// with no maverick root() and no effect, exactly as event.ts:15 calls
// its compiled handler;  the section 2.3 probe measured a signal read
// and a signal write working outside a root.
import { parentPort, workerData } from "node:worker_threads";
import { pathToFileURL } from "node:url";
import { decodeEntities } from "./lib/entities.mjs";
import { bytesOfHex, hexOfBytes } from "./lib/hex.mjs";
import { numberOfBits } from "./lib/bits.mjs";
import { stringOfUtf8, utf8OfString } from "./lib/text.mjs";
import { encodeValue } from "./lib/value.mjs";
import { classify } from "./lib/classify.mjs";
import { readLine, outLine } from "./lib/line.mjs";
import { plantOfName, plantedContext } from "./lib/plant.mjs";

const ENCODER = new TextEncoder();
const DETAIL_BYTES = 64;
const CLONE_FLAG = "--clone";
const SRC_SUBPATH = "crates/topcoat-runtime/browser/src/";
const SIGNAL_ID = /\{"t":"Signal","id":"([0-9a-fA-F-]{36})"/g;

/**
 * The clone browser/src directory as a URL.  pathToFileURL is used so
 * a clone path with a space or a symlink works.
 * @param {readonly string[]} args this worker's argument vector
 * @returns {URL} the browser/src directory URL, with a trailing slash
 */
const cloneSrcOf = (args) => {
  const at = args.indexOf(CLONE_FLAG);
  const given = at === -1 ? undefined : args[at + 1];
  const root =
    given === undefined
      ? new URL("../../topcoat/", import.meta.url)
      : new URL(`${pathToFileURL(given).href.replace(/\/+$/, "")}/`);
  return new URL(SRC_SUBPATH, root);
};

const SRC = cloneSrcOf(process.argv);

const PLANT_FLAG = "--plant";

/**
 * The selected plant, read from this worker's own argument vector.
 * An absent flag is null.  An unknown name cannot arrive here: the
 * driver validated it against the same table (lib/argv.mjs).
 * @param {readonly string[]} args this worker's argument vector
 * @returns {{name: string} | null} the plant, or null
 */
const plantOf = (args) =>
  ((at) => (at === -1 ? null : plantOfName(args[at + 1])))(
    args.indexOf(PLANT_FLAG),
  );

const PLANT = plantOf(process.argv);

/**
 * Import one clone module by relative path under browser/src.
 * @param {string} relative the path under browser/src
 * @returns {Promise<object>} the module namespace
 */
const moduleAt = (relative) => import(new URL(relative, SRC).href);

const [contextMod, signalMod, surrogateMod, panicMod, stringMod] =
  await Promise.all([
    moduleAt("context.ts"),
    moduleAt("signal.ts"),
    moduleAt("surrogate/index.ts"),
    moduleAt("surrogate/panic.ts"),
    moduleAt("surrogate/string.ts"),
  ]);

const { Context } = contextMod;
const { SignalRegistry } = signalMod;
const { F64, Bool, Option, Result, WriteSignal } = surrogateMod;
const { Panic } = panicMod;
// surrogate/index.ts re-exports ./bool, ./event, ./f64, ./option,
// ./panic, ./procedure, ./ref, ./result and ./signal, but NOT ./string.
// Str and String are imported there for the hydrate switch and are not
// re-exported, so the fifth module is imported directly.  String
// extends Str, so the one binding classifies the borrowed and the owned
// form together.  Recorded as a deviation from spec 5.1.
const { Str } = stringMod;

// The startup handshake.  The five clone modules above are transformed
// and loaded in THIS worker, which costs about 320 ms on an idle
// machine and several seconds on a loaded one.  The parent starts the
// case budget only when this message arrives, so that cold start is
// never charged to the case.  The message is posted before any case
// work begins, so a case that then hangs still leaves the parent with
// a running case budget.
const ready =
  parentPort === null ? undefined : parentPort.postMessage({ kind: "ready" });

// The surrogate classifier encodeValue asks for.  String extends Str,
// so the Str arm covers both the borrowed and the owned form, and both
// encode to the same wire tag.  undefined is the unit observation.
// The plant's view of the clone.  Two classifiers and one constructor,
// so lib/plant.mjs imports nothing and the node test can pass stubs.
const PLANT_KIT = Object.freeze({
  isSignal: (v) => v instanceof WriteSignal,
  isNumber: (v) => v instanceof F64,
  plusOne: (v) => new F64(v.dehydrate() + 1),
});

const KINDS = Object.freeze([
  Object.freeze({ owns: (v) => v === undefined, kind: "unit" }),
  Object.freeze({ owns: (v) => typeof v === "function", kind: "function" }),
  Object.freeze({ owns: (v) => v instanceof F64, kind: "f64" }),
  Object.freeze({ owns: (v) => v instanceof Bool, kind: "bool" }),
  Object.freeze({ owns: (v) => v instanceof Str, kind: "str" }),
  Object.freeze({ owns: (v) => v instanceof Option, kind: "option" }),
  Object.freeze({ owns: (v) => v instanceof Result, kind: "result" }),
  Object.freeze({ owns: (v) => v instanceof WriteSignal, kind: "signal" }),
]);

/**
 * Name the kind of one live surrogate.
 * @param {unknown} v the value to classify
 * @returns {string} the kind encodeValue understands
 */
const kindOf = (v) =>
  (KINDS.find((candidate) => candidate.owns(v)) ?? { kind: "unknown" }).kind;

/**
 * The hex of at most 64 bytes from an offset.  A decode failure needs
 * the offending bytes, not the whole line.
 * @param {Uint8Array} bytes the source bytes
 * @param {number} at the offset to start at
 * @returns {string} the lowercase hex of the window
 */
const detailAt = (bytes, at) =>
  hexOfBytes(bytes.slice(at, at + DETAIL_BYTES));

/**
 * The hex of a short diagnostic text.
 * @param {string} text the diagnostic
 * @returns {string} the lowercase hex of its UTF-8 bytes
 */
const detailOf = (text) => detailAt(ENCODER.encode(text), 0);

/**
 * The JS text of one line: bytes, then UTF-8, then entities.  The order
 * is not interchangeable: entities are ASCII, so decoding them before
 * the UTF-8 step would split a multi-byte sequence around an ampersand.
 * @param {string} jsHex the js_hex field of the input line
 * @returns {{ok: true, value: string} | {ok: false, error: string, detailHex: string}}
 *   the decoded JS text, or a named driver error
 */
const decodeJs = (jsHex) => {
  const bytes = bytesOfHex(jsHex);
  return bytes.ok === false
    ? {
        ok: false,
        error: "hex",
        detailHex: detailAt(ENCODER.encode(jsHex), bytes.at),
      }
    : ((text) =>
        text.ok === false
          ? { ok: false, error: "utf8", detailHex: detailAt(bytes.value, 0) }
          : ((decoded) =>
              decoded.ok === false
                ? {
                    ok: false,
                    error: "entity",
                    detailHex: detailAt(
                      ENCODER.encode(text.value),
                      decoded.at,
                    ),
                  }
                : { ok: true, value: decoded.value })(
              decodeEntities(text.value),
            ))(stringOfUtf8(bytes.value));
};

/**
 * Pair the wire u32 signal ids with the uuids the JS text names.  The
 * join is positional and guarded: a count mismatch is the named
 * signal_arity error and never a guess.
 * @param {string} js the decoded JS text
 * @param {readonly object[]} signals the wire signal records
 * @returns {{ok: true, value: readonly object[]} | {ok: false, error: string, detailHex: string}}
 *   the pairs, or the named driver error
 */
const pairSignals = (js, signals) => {
  const ids = [...js.matchAll(SIGNAL_ID)]
    .map((match) => match[1])
    .filter((id, at, all) => all.indexOf(id) === at);
  return ids.length !== signals.length
    ? {
        ok: false,
        error: "signal_arity",
        detailHex: detailOf(`${ids.length} ${signals.length}`),
      }
    : {
        ok: true,
        value: Object.freeze(
          signals.map((one, at) =>
            Object.freeze({ id: one.id, uuid: ids[at], value: one.value }),
          ),
        ),
      };
};

/**
 * A named unseedable failure.
 * @param {string} detail the wire tag that cannot seed a signal
 * @returns {{ok: false, error: "unseedable", detail: string}} the failure
 */
const unseedable = (detail) => ({ ok: false, error: "unseedable", detail });

/**
 * Wrap a seeded inner form in its dehydrated envelope.
 * @param {(inner: unknown) => object} envelope the wrapper
 * @param {unknown} node the inner wire Value
 * @returns {{ok: true, value: unknown} | {ok: false, error: string, detail: string}}
 *   the dehydrated form, or the inner failure
 */
const nest = (envelope, node) =>
  ((inner) =>
    inner.ok === false ? inner : { ok: true, value: envelope(inner.value) })(
    seedForm(node),
  );

/**
 * The dehydrated form of a wire str, which seeds the OWNED String.
 * push_str writes a String back, so a signal that started as Str would
 * change class on its first write.
 * @param {object} node the wire str node
 * @returns {{ok: true, value: string} | {ok: false, error: string, detail: string}}
 *   the raw string, or a named failure
 */
const strForm = (node) =>
  typeof node.hex !== "string"
    ? unseedable("lossy_str")
    : ((bytes) =>
        bytes.ok === false
          ? unseedable("str_hex")
          : ((text) =>
              text.ok === false
                ? unseedable("str_utf8")
                : { ok: true, value: text.value })(stringOfUtf8(bytes.value)))(
        bytesOfHex(node.hex),
      );

const SEED_FORMS = Object.freeze({
  unit: () => ({ ok: true, value: null }),
  f64: (node) => ({ ok: true, value: numberOfBits(node.hi, node.lo) }),
  bool: (node) => ({ ok: true, value: node.v }),
  str: (node) => strForm(node),
  none: () => ({ ok: true, value: { t: "Option", v: null } }),
  some: (node) => nest((inner) => ({ t: "Option", v: inner }), node.v),
  ok: (node) => nest((inner) => ({ t: "Result", ok: inner }), node.v),
  err: (node) => nest((inner) => ({ t: "Result", err: inner }), node.v),
  tuple: () => unseedable("tuple"),
  closure: () => unseedable("closure"),
});

/**
 * Turn one wire Value into the dehydrated form cx.hydrate accepts.
 * Spec section 5.4, the inverse of the encoder's table.
 * @param {unknown} node the wire Value node
 * @returns {{ok: true, value: unknown} | {ok: false, error: string, detail: string}}
 *   the dehydrated form, or a named failure
 */
function seedForm(node) {
  const tag =
    typeof node === "object" && node !== null && Array.isArray(node) === false
      ? node.t
      : "";
  return typeof tag === "string" && Object.hasOwn(SEED_FORMS, tag)
    ? SEED_FORMS[tag](node)
    : unseedable(`${tag}`);
}

/**
 * Seed the registry before the evaluation.  hydrateSurrogate's Signal
 * arm calls handle(id), which throws on an unknown id, so the registry
 * is never populated lazily during the run.  Every initial value goes
 * through cx.hydrate, the same path the generated code uses, because
 * the registry holds SURROGATES and not raw JS values.
 * @param {object} cx the Context
 * @param {object} registry the SignalRegistry
 * @param {readonly object[]} pairs the positional pairs
 * @returns {{ok: true} | {ok: false, error: string, detailHex: string}} the outcome
 */
const seedRegistry = (cx, registry, pairs) => {
  const forms = pairs.map((pair) => seedForm(pair.value));
  const bad = forms.find((form) => form.ok === false);
  return bad !== undefined
    ? { ok: false, error: bad.error, detailHex: detailOf(bad.detail) }
    : ((ignored) => ({ ok: true }))(
        pairs.forEach((pair, at) =>
          registry.insert(pair.uuid, cx.hydrate(forms[at].value)),
        ),
      );
};

/**
 * The final state of every signal the registry holds, under the WIRE
 * u32 id and in wire order.  The uuid never leaves the driver.  A pair
 * the registry does not hold has no final state to report and carries
 * no entry;  in a green run the registry holds every pair.
 * @param {object} registry the SignalRegistry
 * @param {readonly object[]} pairs the positional pairs
 * @returns {{ok: true, value: object[]} | {ok: false, error: string, detailHex: string}}
 *   the output entries, or a named driver error
 */
const finalSignals = (registry, pairs) => {
  const read = pairs
    .filter((pair) => registry.has(pair.uuid))
    .map((pair) => ({
      id: pair.id,
      encoded: encodeValue(registry.read(pair.uuid), kindOf),
    }));
  const bad = read.find((one) => one.encoded.ok === false);
  return bad !== undefined
    ? {
        ok: false,
        error: bad.encoded.error,
        detailHex: detailOf(bad.encoded.detail),
      }
    : { ok: true, value: read.map((one) => ({ id: one.id, value: one.encoded.value })) };
};

/**
 * The rendered channel.  toNodeText() is the text-binding channel
 * text.ts:15-21 writes into the DOM.  toString() is never used, even
 * where the two agree.  An observation whose toNodeText is not a
 * function renders the empty string, which is what Result does at this
 * pin and what the Rust leg does through Driver.renderable.
 * @param {unknown} observation the produced observation
 * @returns {string} the rendered text
 */
const nodeText = (observation) =>
  observation !== null &&
  observation !== undefined &&
  typeof observation.toNodeText === "function"
    ? `${observation.toNodeText()}`
    : "";

/**
 * Build and run the compiled expression.  The form is the production
 * text, semicolon included.  The construction, the call and the closure
 * invocation are all inside this ONE try.
 * @param {string} js the decoded JS text
 * @param {object} cx the Context
 * @param {string} jsForm the wire js form: direct or closure
 * @returns {object} a tagged outcome: observation, driver_error or thrown
 */
const evaluate = (js, cx, jsForm) => {
  try {
    const compiled = new Function("cx", `return ${js};`);
    const produced = compiled(cx);
    return jsForm !== "closure"
      ? { kind: "observation", value: produced }
      : typeof produced === "function"
        ? { kind: "observation", value: produced() }
        : {
            kind: "driver_error",
            error: "closure_not_function",
            detailHex: detailOf(typeof produced),
          };
  } catch (thrown) {
    return { kind: "thrown", value: thrown };
  }
};

/**
 * Classify a thrown value.  instanceof Panic is AUTHORITATIVE: an
 * object that only sets name to "Panic" is a js_error, and a js_error
 * is never folded into panic.  A thrown string, number or bare object
 * is reported by typeof, never by String(e), which throws on a symbol.
 * @param {unknown} thrown the caught value
 * @param {string} hint the wire hint
 * @returns {object} the panic or js_error fields
 */
const thrownFields = (thrown, hint) =>
  thrown instanceof Panic
    ? {
        kind: "panic",
        class: classify(`${thrown.message}`, hint),
        msg: utf8OfString(`${thrown.message}`),
      }
    : thrown !== null &&
        typeof thrown === "object" &&
        typeof thrown.name === "string" &&
        typeof thrown.message === "string"
      ? {
          kind: "js_error",
          name: utf8OfString(thrown.name),
          msg: utf8OfString(thrown.message),
        }
      : {
          kind: "js_error",
          name: utf8OfString("non_error"),
          msg: utf8OfString(typeof thrown),
        };

/**
 * The output record for an evaluation that produced an observation.
 * @param {object} record the input line record
 * @param {unknown} observation the produced observation
 * @param {readonly object[]} signals the final signal entries
 * @returns {object} the output record
 */
const valueRecord = (record, observation, signals) =>
  ((encoded) =>
    encoded.ok === false
      ? {
          kind: "driver_error",
          caseIndex: record.caseIndex,
          error: encoded.error,
          detailHex: detailOf(encoded.detail),
        }
      : {
          kind: "value",
          caseIndex: record.caseIndex,
          value: encoded.value,
          rendered: utf8OfString(nodeText(observation)),
          jsForm: record.jsForm,
          hint: record.hint,
          signals,
        })(encodeValue(observation, kindOf));

/**
 * Turn one evaluation outcome into the output record.
 * @param {object} record the input line record
 * @param {object} outcome the tagged evaluate outcome
 * @param {readonly object[]} signals the final signal entries
 * @returns {object} the output record
 */
const evaluatedRecord = (record, outcome, signals) => {
  switch (outcome.kind) {
    case "observation":
      return valueRecord(record, outcome.value, signals);
    case "driver_error":
      return {
        kind: "driver_error",
        caseIndex: record.caseIndex,
        error: outcome.error,
        detailHex: outcome.detailHex,
      };
    case "thrown":
      return {
        caseIndex: record.caseIndex,
        jsForm: record.jsForm,
        hint: record.hint,
        signals,
        ...thrownFields(outcome.value, record.hint),
      };
    default:
      return {
        kind: "driver_error",
        caseIndex: record.caseIndex,
        error: "unknown_outcome",
        detailHex: detailOf(`${outcome.kind}`),
      };
  }
};

/**
 * A named driver error record.
 * @param {number} caseIndex the case index
 * @param {{error: string, detailHex: string}} failure the named failure
 * @returns {object} the output record
 */
const driverError = (caseIndex, failure) => ({
  kind: "driver_error",
  caseIndex,
  error: failure.error,
  detailHex: failure.detailHex,
});

/**
 * Run one decoded input line.
 * @param {object} record the input line record
 * @returns {object} the output record
 */
const runRecord = (record) => {
  const jsHex = record.kind === "no_terminate" ? null : record.jsHex;
  return jsHex === null || record.jsForm === "absent"
    ? { kind: "skipped", caseIndex: record.caseIndex }
    : ((js) =>
        js.ok === false
          ? driverError(record.caseIndex, js)
          : ((pairs) =>
              pairs.ok === false
                ? driverError(record.caseIndex, pairs)
                : ((registry) =>
                    ((cx) =>
                      ((seeded) =>
                        seeded.ok === false
                          ? driverError(record.caseIndex, seeded)
                          : ((outcome) =>
                              ((signals) =>
                                signals.ok === false
                                  ? driverError(record.caseIndex, signals)
                                  : evaluatedRecord(
                                      record,
                                      outcome,
                                      signals.value,
                                    ))(finalSignals(registry, pairs.value)))(
                              evaluate(js.value, cx, record.jsForm),
                            ))(seedRegistry(cx, registry, pairs.value)))(
                      plantedContext(new Context(registry), PLANT, PLANT_KIT),
                    ))(new SignalRegistry()))(
              pairSignals(js.value, record.signals),
            ))(decodeJs(jsHex));
};

/**
 * Decode one input line.  The try/catch is the one JSON.parse the
 * house style allows.
 * @param {string} text the raw input line
 * @returns {{ok: true, value: unknown} | {ok: false, error: string}} the parse
 */
const parseLine = (text) => {
  try {
    return { ok: true, value: JSON.parse(text) };
  } catch {
    return { ok: false, error: "line_json" };
  }
};

const parsed = parseLine(`${workerData.lineText}`);
const fallbackCase =
  parsed.ok === true &&
  typeof parsed.value === "object" &&
  parsed.value !== null &&
  Number.isInteger(parsed.value.case)
    ? parsed.value.case
    : 0;
const read = parsed.ok === false ? parsed : readLine(parsed.value);
const outRecord =
  read.ok === false
    ? driverError(fallbackCase, {
        error: `line_${read.error}`,
        detailHex: detailOf(`${read.error}`),
      })
    : runRecord(read.value);

// One message out, and then the worker returns.  A null parentPort
// means the file was run outside a worker, which posts nothing.
const posted =
  parentPort === null
    ? undefined
    : parentPort.postMessage({ kind: "line", text: outLine(outRecord) });
