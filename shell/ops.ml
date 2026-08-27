(* Assembles the closure records injected into the dual-compiled
   core: the interpreter's op record (M14) and the printer's literal
   renderers (M13), both backed by Floatops/Strops. *)

let interp_ops : Interp.ops =
  {
    f_add = Floatops.f_add;
    f_sub = Floatops.f_sub;
    f_mul = Floatops.f_mul;
    f_div = Floatops.f_div;
    f_neg = Floatops.f_neg;
    f_eq = Floatops.f_eq;
    f_lt = Floatops.f_lt;
    f_le = Floatops.f_le;
    f_gt = Floatops.f_gt;
    f_ge = Floatops.f_ge;
    f_of_int = Floatops.f_of_int;
    f_display = Floatops.f_display;
    f_debug = Floatops.f_debug;
    str_cmp = Strops.cmp;
    str_debug = Strops.debug;
    str_trim = Strops.trim;
    str_trim_start = Strops.trim_start;
    str_trim_end = Strops.trim_end;
    str_starts_with = Strops.starts_with;
    str_ends_with = Strops.ends_with;
    str_contains = Strops.contains;
  }

let printer_renderer : Printer_rust.renderer =
  { lit_f64 = Floatops.f_literal; lit_str = Strops.debug }
