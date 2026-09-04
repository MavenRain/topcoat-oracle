// M25 resolve hook.  It runs on node's hooks thread and fixes the two
// specifier shapes the clone uses and node cannot resolve alone:
// the bare "@maverick-js/signals", which lives under driver-js and not
// under the clone, and the extensionless relative specifiers of the
// clone's own sources.  See spec section 2.2.
import { existsSync } from "node:fs";

const SIGNALS_SPECIFIER = "@maverick-js/signals";
const SRC_SUBPATH = "crates/topcoat-runtime/browser/src/";
const HOOK_URL = import.meta.url;

// One value crosses from initialize to resolve.  The binding is a
// module-level const and is never reassigned;  initialize places one
// frozen configuration object in the holder, once.
const holder = { config: null };

/**
 * Receive the data argument of module.register.
 * @param {{cloneSrc: string}} data the clone root directory URL as href
 * @returns {void}
 */
export function initialize(data) {
  holder.config = Object.freeze({
    srcUrl: new URL(SRC_SUBPATH, data.cloneSrc).href,
  });
}

/**
 * The clone source directory URL, or the empty string before
 * initialize ran.
 * @returns {string} the href of the clone browser/src directory
 */
const srcUrl = () => (holder.config === null ? "" : holder.config.srcUrl);

/**
 * The last segment of a specifier.
 * @param {string} specifier the module specifier
 * @returns {string} the text after the last slash
 */
const lastSegment = (specifier) => specifier.split("/").at(-1) ?? "";

/**
 * A relative specifier out of a clone source file, with no extension.
 * @param {string} specifier the module specifier
 * @param {{parentURL?: string}} context the resolve context
 * @returns {boolean} true when arm 2 owns the specifier
 */
const isCloneRelative = (specifier, context) =>
  (specifier.startsWith("./") || specifier.startsWith("../")) &&
  lastSegment(specifier).includes(".") === false &&
  typeof context.parentURL === "string" &&
  srcUrl() !== "" &&
  context.parentURL.startsWith(srcUrl());

/**
 * Resolve "./bool" to "./bool.ts", else to "./bool/index.ts".  When
 * neither file exists the hook defers, so node produces its own named
 * ERR_MODULE_NOT_FOUND.  The hook never rejects.
 * @param {string} specifier the module specifier
 * @param {{parentURL?: string}} context the resolve context
 * @param {Function} nextResolve the next hook in the chain
 * @returns {object|Promise<object>} the resolution
 */
const resolveCloneRelative = (specifier, context, nextResolve) => {
  const found = [`${specifier}.ts`, `${specifier}/index.ts`]
    .map((relative) => new URL(relative, context.parentURL))
    .find((candidate) => existsSync(candidate));
  return found === undefined
    ? nextResolve(specifier, context)
    : { url: found.href, shortCircuit: true };
};

// Three arms and a default, as an ordered table consumed by find.  Arm
// 1 re-parents the bare specifier onto this hook module, which puts
// driver-js/node_modules on the search path whatever file imports it.
const ARMS = Object.freeze([
  Object.freeze({
    owns: (specifier) => specifier === SIGNALS_SPECIFIER,
    run: (specifier, context, nextResolve) =>
      nextResolve(specifier, { ...context, parentURL: HOOK_URL }),
  }),
  Object.freeze({ owns: isCloneRelative, run: resolveCloneRelative }),
  Object.freeze({
    owns: () => true,
    run: (specifier, context, nextResolve) => nextResolve(specifier, context),
  }),
]);

/**
 * node's resolve hook.  No format is returned:  node infers
 * module-typescript from the .ts extension and the clone's
 * "type": "module".
 * @param {string} specifier the module specifier
 * @param {{parentURL?: string}} context the resolve context
 * @param {Function} nextResolve the next hook in the chain
 * @returns {object|Promise<object>} the resolution
 */
export function resolve(specifier, context, nextResolve) {
  const arm = ARMS.find((candidate) => candidate.owns(specifier, context));
  return arm === undefined
    ? nextResolve(specifier, context)
    : arm.run(specifier, context, nextResolve);
}
