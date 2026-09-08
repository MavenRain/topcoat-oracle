// M25 loader preload.  node runs this file with --import before the
// main script.  It reads --clone out of process.argv, resolves the
// clone source directory to an absolute directory URL, and registers
// the resolve hook on node's hooks thread.  That directory reaches the
// hook only through the data argument of register.  No environment
// variable is read or written.
//
// Two files are needed because module.register loads the hook module by
// URL on a separate thread, so the module that calls register cannot
// also be the module that register loads.  See spec section 2.1.
import { register } from "node:module";
import { realpathSync } from "node:fs";
import { pathToFileURL } from "node:url";

const CLONE_FLAG = "--clone";
const SRC_SUBPATH = "crates/topcoat-runtime/browser/src/";

/**
 * The clone root as an absolute directory URL.  Node resolves loaded
 * modules to physical paths, so the hook must use the same root even
 * when --clone or one of its ancestors is a symlink.  The default is
 * the sibling checkout that m24_gate.sh also checks.
 * @param {readonly string[]} args the argument vector to search
 * @returns {URL} the clone root, always with a trailing slash
 */
export function cloneRootOf(args) {
  const at = args.indexOf(CLONE_FLAG);
  const given = at === -1 ? undefined : args[at + 1];
  const lexical = given === undefined
    ? new URL("../../topcoat/", import.meta.url)
    : new URL(`${pathToFileURL(given).href.replace(/\/+$/, "")}/`);
  // Keep filesystem failures at the existing worker error boundary.
  // A missing or inaccessible clone must not make the preload abort.
  try {
    return new URL(`${pathToFileURL(realpathSync(lexical)).href.replace(/\/+$/, "")}/`);
  } catch {
    return lexical;
  }
}

/**
 * The clone source directory as an absolute directory URL.  The root alone
 * is not enough: node canonicalizes the parentURL of every module it
 * loads, so a symlink BELOW the clone root, for example a linked crates
 * directory, moves the loaded parentURL away from a lexically appended
 * source path and the hook then owns no specifier.  The source directory
 * is therefore resolved here, once, and the hook uses it as given.
 * @param {readonly string[]} args the argument vector to search
 * @returns {URL} the clone browser/src directory, with a trailing slash
 */
export function cloneSrcOf(args) {
  const lexical = new URL(SRC_SUBPATH, cloneRootOf(args));
  // Same boundary as cloneRootOf: a missing or inaccessible source
  // directory keeps its lexical URL and fails at the worker error.
  try {
    return new URL(`${pathToFileURL(realpathSync(lexical)).href.replace(/\/+$/, "")}/`);
  } catch {
    return lexical;
  }
}

register("./resolve-hook.mjs", import.meta.url, {
  data: { cloneSrc: cloneSrcOf(process.argv).href },
});
