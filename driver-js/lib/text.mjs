// The string byte model.  A well formed string travels as UTF-8 bytes.
// A string that is not well formed (a lone surrogate) travels as its
// UTF-16 code units, and the caller marks the line lossy.  R8: loud,
// never U+FFFD.
import { hexOfBytes } from "./hex.mjs";

const ENCODER = new TextEncoder();
const DECODER = new TextDecoder("utf-8", { ignoreBOM: true });

/**
 * The UTF-16 code units of a string, big-endian, two bytes each.
 * @param {string} s the string to split
 * @returns {Uint8Array} the code unit bytes
 */
const utf16Bytes = (s) =>
  Uint8Array.from(
    s.split("").flatMap((unit) => [
      unit.charCodeAt(0) >>> 8,
      unit.charCodeAt(0) & 0xff,
    ]),
  );

/**
 * Encode a string for the wire.
 * @param {string} s the string to encode
 * @returns {{kind: "utf8", hex: string} | {kind: "utf16", hex: string}}
 *   the UTF-8 hex, or the UTF-16 hex when the string is not well formed
 */
export function utf8OfString(s) {
  return s.isWellFormed()
    ? { kind: "utf8", hex: hexOfBytes(ENCODER.encode(s)) }
    : { kind: "utf16", hex: hexOfBytes(utf16Bytes(s)) };
}

/**
 * Decode UTF-8 bytes.  The decoder is non-fatal, so the decode is
 * checked by re-encoding and comparing the bytes.  That gets fatal
 * behaviour without a try/catch, which R14 does not allow here.
 * The decoder sets ignoreBOM, because the default decoder drops a
 * leading U+FEFF.  A dropped BOM makes the re-encode shorter than the
 * input, so well formed bytes that start with a BOM would answer the
 * named error.  The compare must answer well-formedness exactly.
 * @param {Uint8Array} bytes the bytes to decode
 * @returns {{ok: true, value: string} | {ok: false, error: "utf8"}}
 *   the string, or the named error
 */
export function stringOfUtf8(bytes) {
  const value = DECODER.decode(bytes);
  const again = ENCODER.encode(value);
  return again.length === bytes.length && again.every((b, i) => b === bytes[i])
    ? { ok: true, value }
    : { ok: false, error: "utf8" };
}
