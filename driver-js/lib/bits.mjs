// The IEEE-754 halves of a double, the same split harness.rs:91
// split_bits makes.  One module-level DataView, the pattern f64.ts:4
// uses.  DataView is big-endian by default, so hi holds the sign, the
// exponent and the top mantissa bits.
const VIEW = new DataView(new ArrayBuffer(8));

/**
 * Split a double into its two big-endian halves.
 * @param {number} v the double to split
 * @returns {{hi: number, lo: number}} the halves, as unsigned integers
 */
export function bitsOfNumber(v) {
  VIEW.setFloat64(0, v);
  return Object.freeze({ hi: VIEW.getUint32(0), lo: VIEW.getUint32(4) });
}

/**
 * Join two big-endian halves into a double.
 * @param {number} hi the high half
 * @param {number} lo the low half
 * @returns {number} the double
 */
export function numberOfBits(hi, lo) {
  VIEW.setUint32(0, hi);
  VIEW.setUint32(4, lo);
  return VIEW.getFloat64(0);
}
