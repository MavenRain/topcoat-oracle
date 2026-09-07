// M23 probe runner.  One `cargo run` establishes every open M23 fact: the
// concrete evaluated type per target type, the public render route and the
// Expr marker layout, NodeViewParts membership, the live panic payloads, the
// signal read route, the f64 / String init round trip, and whether a top level
// closure captures the JS without evaluating the Rust half.  Every line starts
// with a stable key so the spec can cite it by name.
#![allow(dead_code, unused_variables)]

use std::panic::{AssertUnwindSafe, catch_unwind};

use topcoat_core::context::Cx;
use topcoat_runtime::{Signal, Surrogate, Surrogated};
use topcoat_runtime_macro::expr;
use topcoat_view::NodeViewParts;

fn hex(bytes: &[u8]) -> String {
    bytes.iter().map(|b| format!("{b:02x}")).collect::<String>()
}

fn render_node<T: NodeViewParts>(cx: &Cx, v: T) -> String {
    let view = topcoat_view::internal::build_sync(move || {
        topcoat_view::internal::write_block(move |parts| v.into_view_parts(cx, parts))
    });
    view.render(cx)
}

fn payload(e: Box<dyn std::any::Any + Send>) -> String {
    e.downcast_ref::<&str>()
        .map(|s| (*s).to_owned())
        .or_else(|| e.downcast_ref::<String>().cloned())
        .map_or_else(|| String::from("<non-string payload>"), |s| s)
}

fn catch<F: FnOnce()>(key: &str, f: F) {
    let r = catch_unwind(AssertUnwindSafe(f));
    let text = r.map_or_else(payload, |()| String::from("<NO PANIC>"));
    println!("PANIC {key} | {text}");
}

fn types() {
    {
        let v0: f64 = 1.5;
        let (val, _js) = expr!(v0 + 1.5).into_evaluated_and_js();
        println!("TYPE f64 | {} | {val}", std::any::type_name_of_val(&val));
    }
    {
        let v1: bool = true;
        let (val, _js) = expr!(!v1).into_evaluated_and_js();
        println!("TYPE bool | {} | {val}", std::any::type_name_of_val(&val));
    }
    {
        let v2: String = String::from("ab");
        let (val, _js) = expr!(v2.clone()).into_evaluated_and_js();
        println!("TYPE string | {} | {val}", std::any::type_name_of_val(&val));
    }
    {
        let v1: bool = true;
        let (val, _js) = expr!(if v1 {}).into_evaluated_and_js();
        println!("TYPE unit | {} | {val:?}", std::any::type_name_of_val(&val));
    }
    {
        let v8: Option<f64> = Some(1.5);
        let (val, _js) = expr!(v8.clone()).into_evaluated_and_js();
        println!("TYPE option_f64 | {} | {val:?}", std::any::type_name_of_val(&val));
    }
    {
        let v9: Option<String> = Some(String::from("s"));
        let (val, _js) = expr!(v9.clone()).into_evaluated_and_js();
        println!("TYPE option_string | {} | {val:?}", std::any::type_name_of_val(&val));
    }
    {
        let v6: Result<f64, String> = Ok(1.5);
        let (val, _js) = expr!(v6.clone()).into_evaluated_and_js();
        println!("TYPE result_f64_string | {} | {val:?}", std::any::type_name_of_val(&val));
    }
    {
        let v7: Result<String, f64> = Err(1.5);
        let (val, _js) = expr!(v7.clone()).into_evaluated_and_js();
        println!("TYPE result_string_f64 | {} | {val:?}", std::any::type_name_of_val(&val));
    }
    {
        let v1: bool = true;
        let v0: f64 = 1.5;
        let (val, _js) = expr!(v1.then_some(v0)).into_evaluated_and_js();
        println!("TYPE then_some | {} | {val:?}", std::any::type_name_of_val(&val));
    }
    {
        let v3 = Signal::new(2.5f64);
        let (val, _js) = expr!(v3.get()).into_evaluated_and_js();
        println!("TYPE signal_get_f64 | {} | {val}", std::any::type_name_of_val(&val));
    }
    {
        let v5 = Signal::new(String::from("sig"));
        let (val, _js) = expr!(v5.get()).into_evaluated_and_js();
        println!("TYPE signal_get_string | {} | {val}", std::any::type_name_of_val(&val));
    }
    {
        let v4 = Signal::new(true);
        let (val, _js) = expr!(v4.get()).into_evaluated_and_js();
        println!("TYPE signal_get_bool | {} | {val}", std::any::type_name_of_val(&val));
    }
}

fn render_route() {
    let cx = Cx::default();
    {
        let v0: f64 = 1.5;
        let (val, js) = expr!(v0 + 1.5).into_evaluated_and_js();
        let js_text = js.render(&cx);
        println!("RENDER f64_js_alone | {js_text}");
        println!("RENDER f64_js_alone_hex | {}", hex(js_text.as_bytes()));
        println!("RENDER f64_val_alone | {}", render_node(&cx, val));
    }
    {
        let v0: f64 = 1.5;
        let whole = render_node(&cx, expr!(v0 + 1.5));
        println!("RENDER f64_expr_whole | {whole}");
        println!("RENDER f64_expr_whole_hex | {}", hex(whole.as_bytes()));
    }
    {
        let v2: String = String::from("a<b>+c");
        let (val, js) = expr!(v2.clone()).into_evaluated_and_js();
        println!("RENDER str_js_alone | {}", js.render(&cx));
        println!("RENDER str_val_alone | {}", render_node(&cx, val));
    }
    {
        let v2: String = String::from("a<b>+c");
        println!("RENDER str_expr_whole | {}", render_node(&cx, expr!(v2.clone())));
    }
    {
        let v8: Option<f64> = None;
        println!("RENDER optnone_expr_whole | {}", render_node(&cx, expr!(v8.clone())));
    }
    {
        let v8: Option<f64> = Some(1.5);
        println!("RENDER optsome_expr_whole | {}", render_node(&cx, expr!(v8.clone())));
    }
}

fn nvp() {
    let cx = Cx::default();
    println!("NVP f64 | {}", render_node(&cx, 1.5f64));
    println!("NVP bool | {}", render_node(&cx, true));
    println!("NVP string | {}", render_node(&cx, String::from("s<q>\"z\"")));
    println!("NVP option_some_f64 | {}", render_node(&cx, Some(1.5f64)));
    println!("NVP option_none_f64 | {}", render_node(&cx, None::<f64>));
    println!("NVP option_some_string | {}", render_node(&cx, Some(String::from("s"))));
    println!("NVP unit | NOT IMPLEMENTED, impl_tuple! starts at T1 (topcoat-view/src/html/node.rs:233)");
    println!("NVP result | NOT IMPLEMENTED, no impl for Result in topcoat-view/src/html/node.rs");
}

fn signals() {
    let v3 = Signal::new(2.5f64);
    let s = Surrogated::into_surrogate(&v3);
    let before: f64 = Surrogate::into_real(s.get());
    println!("SIG read_before_macro | {before}");
    let (val, _js) = expr!(v3.get()).into_evaluated_and_js();
    println!("SIG get_inside_macro | {val}");
    println!("SIG clone | Signal<T> derives Debug only (topcoat-runtime/src/signal.rs:35), no Clone");
}

fn roundtrip() {
    let cx = Cx::default();
    {
        let v0: f64 = f64::from_bits(0x7ff8_0000_0000_0001u64);
        let (val, js) = expr!(v0).into_evaluated_and_js();
        println!("RT f64_nan_bits | {:016x}", val.to_bits());
        println!("RT f64_nan_js | {}", js.render(&cx));
    }
    {
        let v0: f64 = f64::from_bits(0xc0f8_0000_0000_0000u64);
        let (val, js) = expr!(v0).into_evaluated_and_js();
        println!("RT f64_neg_bits | {:016x} | {val}", val.to_bits());
        println!("RT f64_neg_js | {}", js.render(&cx));
    }
    {
        let v0: f64 = f64::from_bits(0x0000_0000_0000_0001u64);
        let (val, _js) = expr!(v0).into_evaluated_and_js();
        println!("RT f64_subnormal_bits | {:016x} | {val:e}", val.to_bits());
    }
    {
        let v2: String = String::from("a\"b\\c\nd\u{e9}\u{1f600}");
        let (val, js) = expr!(v2.clone()).into_evaluated_and_js();
        println!("RT str_hex | {}", hex(val.as_bytes()));
        println!("RT str_js | {}", js.render(&cx));
    }
    {
        let v2: String = String::from("");
        let (val, _js) = expr!(v2.clone()).into_evaluated_and_js();
        println!("RT str_empty_hex | {} | len {}", hex(val.as_bytes()), val.len());
    }
}

fn closure_js() {
    let cx = Cx::default();
    {
        let v0: f64 = 1.5;
        let (_val, js) = expr!(v0 + 1.5).into_evaluated_and_js();
        println!("CLS bare_js | {}", js.render(&cx));
    }
    {
        let v0: f64 = 1.5;
        let (_val, js) = expr!(move ||v0 + 1.5).into_evaluated_and_js();
        println!("CLS closure_js | {}", js.render(&cx));
    }
    {
        let v8: Option<f64> = None;
        let (_val, js) = expr!(move ||v8.clone().unwrap()).into_evaluated_and_js();
        println!("CLS closure_panicking_js | {}", js.render(&cx));
    }
    {
        let v4 = Signal::new(true);
        let (_val, js) = expr!(move ||v4.toggle()).into_evaluated_and_js();
        println!("CLS closure_signal_write_js | {}", js.render(&cx));
    }
}

fn panics() {
    catch("option_unwrap_none", || {
        let v8: Option<f64> = None;
        let _ = expr!(v8.clone().unwrap());
    });
    catch("option_expect_none", || {
        let v8: Option<f64> = None;
        let _ = expr!(v8.clone().expect("gone"));
    });
    catch("result_unwrap_err", || {
        let v6: Result<f64, String> = Err(String::from("bad"));
        let _ = expr!(v6.clone().unwrap());
    });
    catch("result_expect_err", || {
        let v6: Result<f64, String> = Err(String::from("bad"));
        let _ = expr!(v6.clone().expect("boom"));
    });
    catch("result_unwrap_err_on_ok", || {
        let v7: Result<String, f64> = Ok(String::from("ok"));
        let _ = expr!(v7.clone().unwrap_err());
    });
    catch("result_expect_err_on_ok", || {
        let v7: Result<String, f64> = Ok(String::from("ok"));
        let _ = expr!(v7.clone().expect_err("nope"));
    });
    catch("signal_set", || {
        let v3 = Signal::new(0.0f64);
        let _ = expr!(v3.set(1.5));
    });
    catch("signal_toggle", || {
        let v4 = Signal::new(true);
        let _ = expr!(v4.toggle());
    });
    catch("signal_increment", || {
        let v3 = Signal::new(0.0f64);
        let _ = expr!(v3.increment());
    });
    catch("signal_decrement", || {
        let v3 = Signal::new(0.0f64);
        let _ = expr!(v3.decrement());
    });
    catch("signal_push_str", || {
        let v5 = Signal::new(String::from("s"));
        let _ = expr!(v5.push_str("x"));
    });
    catch("no_panic_control", || {
        let v0: f64 = 1.5;
        let _ = expr!(v0 + 1.5);
    });
}

#[tokio::main(flavor = "current_thread")]
async fn main() {
    types();
    render_route();
    nvp();
    signals();
    roundtrip();
    closure_js();
    let prev = std::panic::take_hook();
    std::panic::set_hook(Box::new(|_| {}));
    panics();
    std::panic::set_hook(prev);
    println!("PROBE DONE");
}
