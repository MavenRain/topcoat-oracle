# M13/M15 rustc render probe - f64 Display/Debug, str trim/Debug

Ground truth for shell/floatops.ml and shell/strops.ml, probed
2026-08-27 with the ambient rustc (1.96-nightly toolchain family) on
this machine. Program:

```rust
fn main() {
    let cases: [f64; 12] = [1.0, 1e300, 1e16, 1e15, 5e-324, 1e-5, 0.1,
        -0.0, f64::INFINITY, f64::NAN, 1.5e-7, 123456789012345680.0];
    cases.iter().for_each(|c| println!("D[{}] Q[{:?}]", c, c));
    println!("thensome {:?}", false.then_some(7.0));
    let s = "\u{85}x\u{a0}\u{3000}y\u{2028} ";
    println!("trim [{}] [{}]", s.trim_start(), s.trim_end());
    println!("dbgstr {:?}", "a\"b\\c\nd\u{0}e\u{7f}\u{1b}é");
    println!("len {}", "aé😀".len());
}
```

Output (1e300/5e-324 Display digits elided here; 1e300 prints "1"
followed by 300 zeros - 301 chars, fully positional; 5e-324 prints
"0." + 323 zeros + "5"):

| value | Display `{}` | Debug `{:?}` |
|---|---|---|
| 1.0 | `1` | `1.0` |
| 1e300 | 301-digit positional | `1e300` |
| 1e16 | `10000000000000000` | `1e16` |
| 1e15 | `1000000000000000` | `1000000000000000.0` |
| 5e-324 | 0.(323 zeros)5 positional | `5e-324` |
| 1e-5 | `0.00001` | `1e-5` |
| 0.1 | `0.1` | `0.1` |
| -0.0 | `-0` | `-0.0` |
| inf | `inf` | `inf` |
| NaN | `NaN` | `NaN` |
| 1.5e-7 | `0.00000015` | `1.5e-7` |
| 123456789012345680.0 | `123456789012345680` | `1.2345678901234568e17` |

Rules extracted:
- Display: shortest round-trip digits, ALWAYS positional, integral
  values drop the point, spellings `inf`/`-inf`/`NaN`/`-0`.
- Debug: same digits; positional with a forced `.0` when the decimal
  exponent e10 (of d1.d2..dn x 10^e10) is in [-4, 15]; exponential
  `d1[.d2..dn]e<e10>` otherwise, no `+` on positive exponents;
  zero renders `0.0`/`-0.0`.
- Debug form is always a valid f64-literal token for finite values
  (has `.` or `e`), which is why the printer's injected literal
  renderer reuses it; Display of integral values would be an integer
  literal, which expr! rejects (expr_lit.rs:30).

Other probes:
- `false.then_some(7.0)` -> `None` (argument evaluated eagerly as an
  ordinary Rust argument, value discarded; `then` stays lazy - the
  closure only runs on `true`).
- trim: `"\u{85}x\u{a0}\u{3000}y\u{2028} "` -> trim_start strips the
  leading U+0085 (NEL); trim_end strips the trailing space and
  U+2028; interior U+00A0/U+3000 untouched. Confirms Rust uses the
  Unicode White_Space property set.
- str Debug: `"a\"b\\c\nd\u{0}e\u{7f}\u{1b}é"` ->
  `"a\"b\\c\nd\0e\u{7f}\u{1b}é"` - named escapes for `"` `\` `\n`
  (`\r`/`\t` analogous), `\0` stays `\0`, other C0 and DEL as
  `\u{..}` lowercase hex, printable non-ASCII passes through.
- `"aé😀".len()` = 7: byte length (UTF-8), not chars/UTF-16 units.
