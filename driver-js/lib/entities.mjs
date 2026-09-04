// The exact inverse of COMMENT_ESCAPES (escape.rs:105-106).  Three
// entities and nothing more.  A general HTML decoder would silently
// accept text the escaper could never have produced, so a bare "&" is a
// named error and never a pass through.
const ENCODER = new TextEncoder();

// The three entities, in the order of the escaper table.
const ENTITIES = Object.freeze([
  Object.freeze({ name: "amp;", char: "&" }),
  Object.freeze({ name: "gt;", char: ">" }),
  Object.freeze({ name: "quot;", char: '"' }),
]);

/**
 * The UTF-8 byte length of a string.
 * @param {string} text the text to measure
 * @returns {number} the number of UTF-8 bytes
 */
const byteLength = (text) => ENCODER.encode(text).length;

/**
 * Decode the three comment entities.  The split on "&" makes the
 * nesting case right: "&amp;gt;" decodes to the literal "&gt;", where a
 * chain of replaceAll calls would produce ">".
 * @param {string} text the escaped comment payload
 * @returns {{ok: true, value: string} | {ok: false, error: "entity", at: number}}
 *   the decoded text, or the byte offset of the offending "&"
 */
export function decodeEntities(text) {
  const parts = text.split("&");
  const head = parts[0] ?? "";
  const folded = parts.slice(1).reduce(
    (acc, fragment) =>
      acc.ok === false
        ? acc
        : ((found) =>
            found === undefined
              ? { ok: false, value: "", at: acc.at }
              : {
                  ok: true,
                  value:
                    acc.value + found.char + fragment.slice(found.name.length),
                  at: acc.at + 1 + byteLength(fragment),
                })(ENTITIES.find((entity) => fragment.startsWith(entity.name))),
    { ok: true, value: head, at: byteLength(head) },
  );
  return folded.ok === true
    ? { ok: true, value: folded.value }
    : { ok: false, error: "entity", at: folded.at };
}
