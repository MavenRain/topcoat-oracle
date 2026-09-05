// M25 driver.  It reads the JSONL the rust leg wrote, runs the JS half
// of every selected line in its own worker thread, and writes one
// output line per input line in input order.  See spec section 3.
//
// One fresh worker per case is the isolation rule: a case that leaks a
// signal, a timer or a module-level mutation cannot reach the next
// case.  The cost is one transform of four clone modules per case.
//
// That cold start is not the case, so it is not charged to the case.
// The worker posts a ready message when its modules are loaded, and
// the case budget starts only then.  Startup has its own budget,
// --startup-timeout-ms, and its expiry is a driver_error that names
// startup.
//
// There is no exit 3 and no resume protocol.  A case that passes the
// timeout is terminated, gets a no_terminate line, and the run
// continues in a fresh worker, so a hanging case costs one line and not
// the run.
//
// Exit 0 every selected input line produced an output line, 1 a named
// IO error or an input line that is not JSON or has no usable case, 2
// usage.
import { readFileSync, writeFileSync } from "node:fs";
import { Worker } from "node:worker_threads";
import { parseArgv, USAGE } from "./lib/argv.mjs";
import { hexOfBytes } from "./lib/hex.mjs";
import { subsetViolation, readLine, outLine } from "./lib/line.mjs";
import { STARTUP, RUNNING, budgetOf, expiryRecord } from "./lib/budget.mjs";

const ENCODER = new TextEncoder();
const DETAIL_BYTES = 64;
const WORKER_URL = new URL("./worker.mjs", import.meta.url);
const OUTCOME = /^\{"case":[0-9]+,"outcome":"([a-z_]+)"/;
const CASE_HEAD = /^\{"case":([0-9]+)/;
const OUTCOMES = Object.freeze([
  "value",
  "panic",
  "js_error",
  "no_terminate",
  "skipped",
  "driver_error",
]);
// A readLine failure on either of these two names is a broken input,
// never a case observation: an output line with an invented case index
// would corrupt the pairing M26 depends on.
const FATAL_READ = Object.freeze(["line", "case"]);

/**
 * The hex of at most 64 bytes from an offset.
 * @param {Uint8Array} bytes the source bytes
 * @param {number} at the offset to start at
 * @returns {string} the lowercase hex of the window
 */
const detailAt = (bytes, at) => hexOfBytes(bytes.slice(at, at + DETAIL_BYTES));

/**
 * The message of a caught IO failure, without a coercion that can
 * itself throw.
 * @param {unknown} thrown the caught value
 * @returns {string} the message, or the typeof
 */
const errText = (thrown) =>
  thrown !== null &&
  typeof thrown === "object" &&
  typeof thrown.message === "string"
    ? thrown.message
    : typeof thrown;

/**
 * Read the input file whole.  The try/catch is one of the three the
 * house style allows.
 * @param {string} path the input path
 * @returns {{ok: true, value: string} | {ok: false, error: string}} the text
 */
const readInput = (path) => {
  try {
    return { ok: true, value: readFileSync(path, "utf8") };
  } catch (thrown) {
    return { ok: false, error: `cannot read ${path}: ${errText(thrown)}` };
  }
};

/**
 * Write the output file whole.
 * @param {string} path the output path
 * @param {readonly string[]} lines the finished output lines
 * @returns {{ok: true} | {ok: false, error: string}} the outcome
 */
const writeOutput = (path, lines) => {
  try {
    return ((ignored) => ({ ok: true }))(
      writeFileSync(path, lines.map((line) => `${line}\n`).join("")),
    );
  } catch (thrown) {
    return { ok: false, error: `cannot write ${path}: ${errText(thrown)}` };
  }
};

/**
 * Split the input into lines and drop one trailing empty element.
 * @param {string} text the whole input file
 * @returns {string[]} the input lines
 */
const splitLines = (text) => {
  const parts = text.split("\n");
  return parts.at(-1) === "" ? parts.slice(0, -1) : parts;
};

/**
 * Parse one input line.  The try/catch is the one JSON.parse the house
 * style allows.
 * @param {string} text the raw line
 * @returns {{ok: true, value: unknown} | {ok: false, error: string}} the parse
 */
const parseLine = (text) => {
  try {
    return { ok: true, value: JSON.parse(text) };
  } catch (thrown) {
    return { ok: false, error: errText(thrown) };
  }
};

/**
 * The case index a raw line names, read off the fixed leading key that
 * harness.rs:591-640 writes first.  It is only used when the subset
 * scan rejected the line before JSON.parse could see it.  An
 * unreadable head is the named error "case", never a guessed index: an
 * invented case 0 would sit beside the genuine case 0 line and corrupt
 * the pairing M26 depends on.
 * @param {string} text the raw line
 * @returns {{ok: true, value: number} | {ok: false, error: "case"}}
 *   the case index, or the named error
 */
const caseHead = (text) =>
  ((found) =>
    found === null
      ? { ok: false, error: "case" }
      : { ok: true, value: Number(found[1]) })(CASE_HEAD.exec(text));

/**
 * Plan one input line: a fatal input error, a driver_error line, or a
 * case to run.
 * @param {string} text the raw line
 * @param {number} lineNumber the 1-based line number
 * @param {string} inPath the input path, for the fatal message
 * @returns {object} the tagged plan
 */
const planOf = (text, lineNumber, inPath) => {
  const violation = subsetViolation(text);
  return violation !== null
    ? ((head) =>
        head.ok === false
          ? {
              kind: "fatal",
              message: `${inPath}:${lineNumber}: no usable case: ${head.error}`,
            }
          : {
              kind: "line",
              caseIndex: head.value,
              record: {
                kind: "driver_error",
                caseIndex: head.value,
                error: violation.kind,
                detailHex: detailAt(ENCODER.encode(text), violation.at),
              },
            })(caseHead(text))
    : ((parsed) =>
        parsed.ok === false
          ? {
              kind: "fatal",
              message: `${inPath}:${lineNumber}: not JSON: ${parsed.error}`,
            }
          : ((read) =>
              read.ok === false
                ? FATAL_READ.includes(read.error)
                  ? {
                      kind: "fatal",
                      message: `${inPath}:${lineNumber}: no usable case: ${read.error}`,
                    }
                  : {
                      kind: "line",
                      caseIndex: parsed.value.case,
                      record: {
                        kind: "driver_error",
                        caseIndex: parsed.value.case,
                        error: `line_${read.error}`,
                        detailHex: detailAt(
                          ENCODER.encode(`${read.error}`),
                          0,
                        ),
                      },
                    }
                : {
                    kind: "case",
                    caseIndex: read.value.caseIndex,
                    record: read.value,
                    text,
                  })(readLine(parsed.value)))(parseLine(text));
};

/**
 * The kind of one worker message, with no coercion that can throw.
 * @param {unknown} message the received message
 * @returns {string} the kind field, or "unknown"
 */
const messageKind = (message) =>
  message !== null &&
  typeof message === "object" &&
  typeof message.kind === "string"
    ? message.kind
    : "unknown";

/**
 * Run one case in its own worker.  Two budgets, never one: the startup
 * budget covers the worker's own module load, and the case budget
 * starts only when the worker's ready message arrives.  A case that
 * passes the case budget is terminated and gets a no_terminate line.
 * A worker that never reports ready is terminated and gets a
 * driver_error line that names startup.
 * @param {object} plan the case plan
 * @param {object} options the parsed CLI options
 * @returns {Promise<string>} the finished output line
 */
const runCase = (plan, options) =>
  new Promise((resolve) => {
    const worker = new Worker(WORKER_URL, {
      workerData: { lineText: plan.text },
      argv: [
        "--clone",
        options.clonePath,
        ...(options.plant === null ? [] : ["--plant", options.plant.name]),
      ],
    });
    // One phase and one timer at a time.  The holder is a const and
    // only its properties move, the way resolve-hook.mjs holds its one
    // configuration object.
    const state = { phase: STARTUP, timer: null };
    const finish = (line) => {
      clearTimeout(state.timer);
      worker.terminate();
      resolve(line);
    };
    const failed = (error, detail) =>
      finish(
        outLine({
          kind: "driver_error",
          caseIndex: plan.caseIndex,
          error,
          detailHex: detailAt(ENCODER.encode(detail), 0),
        }),
      );
    const expire = () =>
      ((record) =>
        record.ok === false
          ? failed(record.error, state.phase.kind)
          : finish(outLine(record.value)))(
        expiryRecord(
          state.phase,
          plan.caseIndex,
          plan.record.hint ?? "none",
          options,
        ),
      );
    const arm = (phase) => {
      clearTimeout(state.timer);
      state.phase = phase;
      const budget = budgetOf(phase, options);
      state.timer =
        budget.ok === false ? null : setTimeout(expire, budget.value);
      return budget.ok === false ? failed(budget.error, phase.kind) : undefined;
    };
    const received = (message) => {
      switch (messageKind(message)) {
        case "ready":
          return arm(RUNNING);
        case "line":
          return finish(`${message.text}`);
        default:
          return failed("worker_message", messageKind(message));
      }
    };
    arm(STARTUP);
    worker.on("message", received);
    worker.on("error", (thrown) => failed("worker_error", errText(thrown)));
    worker.on("exit", (code) => failed("worker_exit", `${code}`));
  });

/**
 * Run every planned line in input order, one worker at a time.
 * @param {readonly object[]} plans the selected plans
 * @param {object} options the parsed CLI options
 * @returns {Promise<string[]>} the finished output lines
 */
const runAll = (plans, options) =>
  plans.reduce(
    (chain, plan) =>
      chain.then((lines) =>
        plan.kind === "line"
          ? [...lines, outLine(plan.record)]
          : runCase(plan, options).then((line) => [...lines, line]),
      ),
    Promise.resolve([]),
  );

/**
 * The outcome word of one finished output line, read off the fixed key
 * order outLine writes.
 * @param {string} line the output line
 * @returns {string} the outcome word
 */
const outcomeOf = (line) =>
  ((found) =>
    found !== null && OUTCOMES.includes(found[1]) ? found[1] : "driver_error")(
    OUTCOME.exec(line),
  );

/**
 * The one stderr summary line, asserted whole by the verdict.
 * @param {readonly string[]} lines the finished output lines
 * @returns {string} the summary line
 */
const summaryOf = (lines) => {
  const tally = lines.reduce(
    (acc, line) => ({ ...acc, [outcomeOf(line)]: acc[outcomeOf(line)] + 1 }),
    Object.fromEntries(OUTCOMES.map((name) => [name, 0])),
  );
  return `driver-js: cases ${lines.length} ${OUTCOMES.map(
    (name) => `${name} ${tally[name]}`,
  ).join(" ")}`;
};

/**
 * Print a message on stderr and exit.
 * @param {string} message the message
 * @param {number} code the exit code
 * @returns {void}
 */
const die = (message, code) => {
  process.stderr.write(`${message}\n`);
  process.exit(code);
};

/**
 * The whole run.
 * @param {readonly string[]} args the arguments after the script name
 * @returns {Promise<void>} the finished run
 */
const main = async (args) => {
  const options = parseArgv(args);
  const usage = options.ok === false ? die(`${USAGE}\n${options.error}`, 2) : 0;
  const input = readInput(options.value.inPath);
  const read = input.ok === false ? die(input.error, 1) : 0;
  const plans = splitLines(input.value).map((text, at) =>
    planOf(text, at + 1, options.value.inPath),
  );
  const fatal = plans.find((plan) => plan.kind === "fatal");
  const stop = fatal === undefined ? 0 : die(fatal.message, 1);
  const selected = plans.filter(
    (plan) =>
      plan.caseIndex >= options.value.fromCase &&
      plan.caseIndex < options.value.toCase,
  );
  const lines = await runAll(selected, options.value);
  const written = writeOutput(options.value.outPath, lines);
  const wrote = written.ok === false ? die(written.error, 1) : 0;
  process.stderr.write(`${summaryOf(lines)}\n`);
};

await main(process.argv.slice(2));
