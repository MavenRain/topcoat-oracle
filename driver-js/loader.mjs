// M25 loader preload.  node runs this file with --import before the
// main script.  It reads --clone out of process.argv, resolves the
// clone root to an absolute directory URL, and registers the resolve
// hook on node's hooks thread.  The clone root reaches the hook only
// through the data argument of register.  No environment variable is
// read or written.
//
// Two files are needed because module.register loads the hook module by
// URL on a separate thread, so the module that calls register cannot
// also be the module that register loads.  See spec section 2.1.
import { register } from "node:module";
import { pathToFileURL } from "node:url";

const CLONE_FLAG = "--clone";

/**
 * The clone root as an absolute directory URL.  The default is the
 * sibling checkout that m24_gate.sh also checks.
 * @param {readonly string[]} args the argument vector to search
 * @returns {URL} the clone root, always with a trailing slash
 */
export function cloneRootOf(args) {
  const at = args.indexOf(CLONE_FLAG);
  const given = at === -1 ? undefined : args[at + 1];
  return given === undefined
    ? new URL("../../topcoat/", import.meta.url)
    : new URL(`${pathToFileURL(given).href.replace(/\/+$/, "")}/`);
}

register("./resolve-hook.mjs", import.meta.url, {
  data: { cloneSrc: cloneRootOf(process.argv).href },
});
