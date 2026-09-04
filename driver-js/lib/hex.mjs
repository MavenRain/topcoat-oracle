// Lowercase hex, both directions.  The Rust writer emits lowercase
// (harness.rs:514 format!("{b:02x}")), so uppercase is rejected on
// purpose: accepting it would accept a wire no one writes.
const DIGITS = "0123456789abcdef";

/**
 * Decode a lowercase hex string to bytes.
 * @param {string} hex the hex text, two lowercase characters per byte
 * @returns {{ok: true, value: Uint8Array} | {ok: false, error: "hex", at: number}}
 *   the bytes, or the offset of the first offending character
 */
export function bytesOfHex(hex) {
  const badAt = hex.split("").findIndex((c) => DIGITS.includes(c) === false);
  const odd = hex.length % 2 !== 0;
  return badAt !== -1
    ? { ok: false, error: "hex", at: badAt }
    : odd
      ? { ok: false, error: "hex", at: hex.length - 1 }
      : {
          ok: true,
          value: Uint8Array.from({ length: hex.length / 2 }, (ignored, i) =>
            Number.parseInt(hex.slice(i * 2, i * 2 + 2), 16),
          ),
        };
}

/**
 * Encode bytes as lowercase hex.
 * @param {Uint8Array} bytes the bytes to encode
 * @returns {string} two lowercase hex characters per byte
 */
export function hexOfBytes(bytes) {
  return Array.from(bytes, (b) => b.toString(16).padStart(2, "0")).join("");
}
