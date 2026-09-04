// M23 rust-leg harness (DESIGN.md M23).  Static template: m23_gate.sh
// copies this file byte for byte into the emitted crate as
// src/harness.rs, so the file rustc compiles is the file in the repo.
// shell/driver.ml only decides which case functions call into it.
//
// Two channels per case, captured separately (never by splitting one
// render): the bit-exact value channel through Observe, and the JS wire
// form through Expr::into_evaluated_and_js plus View::render.
//
// Server-side signal writes: all five write shorthands (set, toggle,
// increment, decrement, push_str) reach write_in_browser_only() and
// panic with SIGNAL_WRITE_MSG (topcoat-runtime/src/surrogate/signal.rs
// lines 50, 62, 74, 84, 101, message at line 108).  At this pin the
// rust leg's signal channel therefore equals the inits by construction:
// a server-side store never changes, so the mirror local the emitter
// keeps beside each Signal reports the same value a live handle would.
// M36 (re-pin) must re-probe that.
//
// House rules: no unwrap, no expect, no panic!, no unsafe, no naked as
// casts, no a[i] indexing, no for / while / loop / break / continue /
// return keywords, no Iterator::scan.  catch_unwind is the one
// panic-adjacent call, and it CATCHES.  Errors are a hand-rolled enum.
// The cfg(test) module at the foot of the file is the one place that
// asserts;  it never compiles into the batch binary.
#![allow(dead_code)]

use std::io::Write;
use std::panic::AssertUnwindSafe;
use std::sync::mpsc;
use std::time::Duration;

use topcoat_core::context::Cx;
use topcoat_view::NodeViewParts;

pub const SIGNAL_WRITE_MSG: &str =
    "expressions in which a signal is written to cannot be run server-side";

const USAGE: &str = "usage: <driver> [--from I] [--to J] [--timeout-ms N]";
const DEFAULT_TIMEOUT_MS: u64 = 2000;

// The JS wire form of one expr! call site that has AT LEAST ONE
// external is "(() => { const [..] = [..]; return <body>; })()", so the
// body text sits between JS_RETURN and the last JS_TAIL.  The closure
// site wraps the same body in an arrow function, which means the whole
// direct JS is NOT a substring of the closure JS (the closure inserts
// "() =&gt; " after "return ", and a signal external carries a fresh
// UUID per site).  The body IS shared, and that is what assemble
// checks.
//
// A site with ZERO externals carries neither marker: there is no const
// head to introduce, so the whole render IS the body.  54 of the 298 JS
// lines of the regenerated a2 batch have that shape, for example
// "cx.hydrate(true)" and "(() =&gt; {  })()".  js_body therefore reads
// the whole text when NEITHER marker is present, slices when BOTH are,
// and fails closed on every other combination.
//
// Known limitation, M24+ work:  the head is the FIRST "; return ", so a
// String external whose own bytes contain "; return " mis-slices.
// rfind is wrong too, because a block body lowers to an IIFE that
// carries its own "; return ".  Only a quote-aware scan fixes it, and
// the failure mode meanwhile is a loud exit 4, never a silent pass.
const JS_RETURN: &str = "; return ";
const JS_TAIL: &str = "; })()";

// The wrapper an expression-position block gets, and only that block:
// the head is escaped because it sits in the tail of the site.
const JS_IIFE_HEAD: &str = "(() =&gt; ";
const JS_IIFE_TAIL: &str = ")()";

// ---------- the value channel ----------

// One variant per Obs.value constructor (core/obs.ml), same order, so
// the M24 parser is a straight table.  Tuple and Closure are
// unreachable at m20 scope;  they exist so the wire form does not
// change when the scope widens.
pub enum Value {
    Unit,
    F64 { hi: u32, lo: u32 },
    Bool(bool),
    Str(Vec<u8>),
    Tuple(Vec<Value>),
    None,
    Some(Box<Value>),
    Ok(Box<Value>),
    Err(Box<Value>),
    Closure,
}

// Both shifts are < 2^32, so try_from cannot fail;  the fallback is
// unreachable and exists only because expect is banned.
fn split_bits(bits: u64) -> (u32, u32) {
    let hi = u32::try_from(bits >> 32).unwrap_or(0);
    let lo = u32::try_from(bits & 0xffff_ffff).unwrap_or(0);
    (hi, lo)
}

pub trait Observe {
    fn observe(&self) -> Value;
}

impl Observe for f64 {
    fn observe(&self) -> Value {
        let halves = split_bits(self.to_bits());
        Value::F64 {
            hi: halves.0,
            lo: halves.1,
        }
    }
}

impl Observe for bool {
    fn observe(&self) -> Value {
        Value::Bool(*self)
    }
}

impl Observe for String {
    fn observe(&self) -> Value {
        Value::Str(self.as_bytes().to_vec())
    }
}

impl Observe for () {
    fn observe(&self) -> Value {
        Value::Unit
    }
}

impl<T: Observe> Observe for Option<T> {
    fn observe(&self) -> Value {
        self.as_ref()
            .map_or(Value::None, |v| Value::Some(Box::new(v.observe())))
    }
}

impl<T: Observe, E: Observe> Observe for Result<T, E> {
    fn observe(&self) -> Value {
        self.as_ref().map_or_else(
            |e| Value::Err(Box::new(e.observe())),
            |v| Value::Ok(Box::new(v.observe())),
        )
    }
}

// ---------- the rendered channel ----------

// The render of the EVALUATED VALUE alone, with no markers and no JS.
// Expr<T>'s own NodeViewParts impl is not used: rendering the whole
// Expr splices the JS between the markers with no separator to cut on.
pub fn render_node<T: NodeViewParts>(cx: &Cx, v: T) -> String {
    let view = topcoat_view::internal::build_sync(move || {
        topcoat_view::internal::write_block(move |parts| v.into_view_parts(cx, parts))
    });
    view.render(cx)
}

// () and Result have no NodeViewParts impl (topcoat-view node.rs:233
// starts impl_tuple! at T1, and node.rs has no Result impl), so the
// emitter picks observed_plain for those targets from Sample.target.
pub fn observed_rendered<T: Observe + NodeViewParts>(cx: &Cx, v: T) -> (Value, Vec<u8>) {
    let value = v.observe();
    (value, render_node(cx, v).into_bytes())
}

pub fn observed_plain<T: Observe>(v: T) -> (Value, Vec<u8>) {
    (v.observe(), Vec::new())
}

// ---------- panic capture and classification ----------

// The spellings are exactly Obs.encode_panic_class's (core/obs.ml), so
// M24 decodes with String.equal and no aliasing table.
#[derive(Clone, Copy)]
pub enum Class {
    Unwrap,
    Expect,
    UnwrapErr,
    ExpectErr,
    SignalWrite,
    Other,
}

impl Class {
    pub fn wire(self) -> &'static str {
        match self {
            Class::Unwrap => "unwrap",
            Class::Expect => "expect",
            Class::UnwrapErr => "unwrap_err",
            Class::ExpectErr => "expect_err",
            Class::SignalWrite => "signal_write",
            Class::Other => "other",
        }
    }
}

// The static hint the emitter derives from the body AST: Expect when
// the body mentions expect and not expect_err, ExpectErr for the
// converse, Both when it mentions both, None otherwise.  std gives
// Option::expect(m) the message m and nothing else, so an expect panic
// carries no prefix and the text alone cannot classify it.
#[derive(Clone, Copy)]
pub enum Hint {
    None,
    Expect,
    ExpectErr,
    Both,
}

impl Hint {
    pub fn wire(self) -> &'static str {
        match self {
            Hint::None => "none",
            Hint::Expect => "expect",
            Hint::ExpectErr => "expect_err",
            Hint::Both => "both",
        }
    }
}

// Prefix tests first, hint last.  There is no arm for
// "called `Option::expect()`": std never emits it.  A Both hint yields
// Other, and the gate accepts Other only on a line whose hint is both
// (the M26 adapter refines those from the reference leg).
pub fn classify(msg: &str, hint: Hint) -> Class {
    match () {
        () if msg == SIGNAL_WRITE_MSG => Class::SignalWrite,
        () if msg.starts_with("called `Option::unwrap()`") => Class::Unwrap,
        () if msg.starts_with("called `Result::unwrap()`") => Class::Unwrap,
        () if msg.starts_with("called `Result::unwrap_err()`") => Class::UnwrapErr,
        () => match hint {
            Hint::Expect => Class::Expect,
            Hint::ExpectErr => Class::ExpectErr,
            Hint::Both => Class::Other,
            Hint::None => Class::Other,
        },
    }
}

fn payload(e: Box<dyn std::any::Any + Send>) -> String {
    e.downcast_ref::<&str>()
        .map(|s| (*s).to_owned())
        .or_else(|| e.downcast_ref::<String>().cloned())
        .map_or_else(|| String::from("<non-string payload>"), |s| s)
}

// ---------- what one case function hands back ----------

// The value site: the evaluated value, its render, its JS, and one
// Debug text per signal handle, captured BEFORE the macro consumed the
// binding.  M25 recovers each signal's UUID from that text to bind the
// stub cx.
pub struct Triple {
    pub value: Value,
    pub rendered: Vec<u8>,
    pub js: Vec<u8>,
    pub sig_debug: Vec<String>,
}

// The closure site: JS only.  The Rust half is a closure value that is
// never called, so a body that panics at the value site still yields
// its JS here.
pub struct JsSite {
    pub js: Vec<u8>,
    pub sig_debug: Vec<String>,
}

pub struct SigInit {
    pub id: u32,
    pub value: Value,
}

pub fn sig<T: Observe>(id: u32, v: &T) -> SigInit {
    SigInit {
        id,
        value: v.observe(),
    }
}

pub fn debug_of<T: std::fmt::Debug>(v: &T) -> String {
    format!("{v:?}")
}

pub enum Inner {
    Value(Triple),
    Panic { class: Class, msg: String },
}

enum Form {
    Direct,
    Closure,
    Absent,
}

impl Form {
    fn wire(&self) -> &'static str {
        match self {
            Form::Direct => "direct",
            Form::Closure => "closure",
            Form::Absent => "absent",
        }
    }
}

enum Outcome {
    Value { value: Value, rendered: Vec<u8> },
    Panic { class: Class, msg: String },
    NoTerminate,
}

struct SigOut {
    id: u32,
    value: Value,
    debug: String,
}

pub struct Observed {
    outcome: Outcome,
    js: Vec<u8>,
    form: Form,
    hint: Hint,
    signals: Vec<SigOut>,
    js_consistent: bool,
}

pub fn catch_value<F: FnOnce() -> Triple>(hint: Hint, f: F) -> Inner {
    std::panic::catch_unwind(AssertUnwindSafe(f)).map_or_else(
        |e| {
            let msg = payload(e);
            Inner::Panic {
                class: classify(&msg, hint),
                msg,
            }
        },
        Inner::Value,
    )
}

pub fn catch_js<F: FnOnce() -> JsSite>(f: F) -> Option<JsSite> {
    std::panic::catch_unwind(AssertUnwindSafe(f)).ok()
}

// Both markers, or neither.  A text carrying exactly one of them is a
// wire shape this code does not know, so it yields None and the caller
// fails CLOSED (exit 4), instead of the old "no marker, so agree".
fn sliced_body(text: &str) -> Option<&str> {
    text.find(JS_RETURN).map_or_else(
        || Some(text).filter(|t| !t.contains(JS_TAIL)),
        |head| {
            text.rfind(JS_TAIL)
                .and_then(|tail| text.get(head + JS_RETURN.len()..tail))
        },
    )
}

// None on non-UTF-8 bytes, on a half-present marker set, and on an
// empty body slice.  Every None is a red: the consistency check has
// nothing to compare and must not report agreement.
fn js_body(js: &[u8]) -> Option<&str> {
    std::str::from_utf8(js)
        .ok()
        .and_then(sliced_body)
        .filter(|body| !body.is_empty())
}

// A block body is lowered TWICE, and the two lowerings differ in the
// wrapper only.  In the direct form the block is an expression, so it
// becomes an immediately invoked arrow, "(() =&gt; { .. })()".  In the
// closure form the same block is the arrow's own body, so the invoking
// wrapper is gone and the text is "() =&gt; { .. }".  The braces and
// everything between them are byte-identical, so the core of a direct
// body is the body with one IIFE wrapper peeled off.
//
// The peel is only sound when what it leaves is ONE brace-balanced run.
// The direct JS of "{ A } + { Z }" is
// "(() =&gt; { A; })() + (() =&gt; { Z; })()", which strips to
// "{ A; })() + (() =&gt; { Z; }": its depth falls back to zero in the
// middle, and a closure carrying both blocks would contain that text,
// so an unchecked peel would call two different programs consistent.
// Depth must therefore stay above zero at every byte before the last
// and land on exactly zero after it.  Braces inside a JS string literal
// only make the test refuse to peel, which costs a loud exit 4 and
// never a silent pass.
struct Depth {
    depth: i32,
    ok: bool,
}

fn step(acc: Depth, at: usize, byte: u8, last: usize) -> Depth {
    let depth = match byte {
        b'{' => acc.depth + 1,
        b'}' => acc.depth - 1,
        _ => acc.depth,
    };
    Depth {
        depth,
        ok: acc.ok && (depth > 0 || at == last),
    }
}

fn balanced(core: &str) -> bool {
    core.len()
        .checked_sub(1)
        .map(|last| {
            core.bytes()
                .enumerate()
                .fold(Depth { depth: 0, ok: true }, |acc, pair| {
                    step(acc, pair.0, pair.1, last)
                })
        })
        .is_some_and(|end| end.ok && end.depth == 0)
}

fn js_core(body: &str) -> Option<&str> {
    body.strip_prefix(JS_IIFE_HEAD)
        .and_then(|inner| inner.strip_suffix(JS_IIFE_TAIL))
        .filter(|core| balanced(core))
}

// An empty needle is NOT contained: the only way to reach this with an
// empty needle is a body slice that carried no bytes, and that is a
// wire shape the check must reject rather than wave through.
fn find(hay: &[u8], needle: &[u8]) -> bool {
    match () {
        () if needle.is_empty() => false,
        () if needle.len() > hay.len() => false,
        () => hay.windows(needle.len()).any(|w| w == needle),
    }
}

// The direct JS and the closure JS must agree on the body text.  Whole
// JS containment is false by construction (the closure site inserts the
// arrow wrapper and mints a fresh signal UUID), so the check runs on
// the body slice.  Two agreements count, because a block body loses its
// IIFE wrapper when it becomes the arrow's own body: the closure JS
// carries the whole direct body, or it carries that body's core.  A
// violation is exit 4, not a silent line.  A direct JS whose body
// cannot be read at all is also a violation:  the check fails CLOSED,
// because a drifted wire shape is exactly the event it exists to catch.
fn body_consistent(direct: &[u8], closure: &[u8]) -> bool {
    js_body(direct).is_some_and(|b| {
        find(closure, b.as_bytes())
            || js_core(b).is_some_and(|c| find(closure, c.as_bytes()))
    })
}

fn sig_outs(signals: Vec<SigInit>, debug: &[String]) -> Vec<SigOut> {
    signals
        .into_iter()
        .enumerate()
        .map(|pair| SigOut {
            id: pair.1.id,
            value: pair.1.value,
            debug: debug
                .get(pair.0)
                .map_or_else(String::new, std::clone::Clone::clone),
        })
        .collect()
}

// js_form is direct when the value site survived (the closure bytes are
// discarded), closure when it panicked and the closure site supplied
// the bytes, and absent when it panicked with no closure site.
pub fn assemble(
    inner: Inner,
    closure: Option<JsSite>,
    signals: Vec<SigInit>,
    hint: Hint,
) -> Observed {
    match inner {
        Inner::Value(t) => {
            let consistent = closure
                .as_ref()
                .map_or(true, |c| body_consistent(&t.js, &c.js));
            Observed {
                outcome: Outcome::Value {
                    value: t.value,
                    rendered: t.rendered,
                },
                js: t.js,
                form: Form::Direct,
                hint,
                signals: sig_outs(signals, &t.sig_debug),
                js_consistent: consistent,
            }
        }
        Inner::Panic { class, msg } => {
            // The signal channel survives a panic: its values come from
            // the mirror locals, not from the site that unwound.  Only
            // the Debug texts come from the site, so an absent closure
            // site costs the debug field and nothing else.
            let site = closure.map_or_else(
                || (Vec::new(), Form::Absent, Vec::new()),
                |c| (c.js, Form::Closure, c.sig_debug),
            );
            Observed {
                outcome: Outcome::Panic { class, msg },
                js: site.0,
                form: site.1,
                hint,
                signals: sig_outs(signals, &site.2),
                js_consistent: true,
            }
        }
    }
}

// ---------- the JSONL writer ----------

pub enum Error {
    Io,
    Range,
}

fn hex(bytes: &[u8]) -> String {
    bytes.iter().map(|b| format!("{b:02x}")).collect()
}

fn push_value(out: &mut String, v: &Value) {
    match v {
        Value::Unit => out.push_str("{\"t\":\"unit\"}"),
        Value::F64 { hi, lo } => {
            out.push_str("{\"t\":\"f64\",\"hi\":");
            out.push_str(&hi.to_string());
            out.push_str(",\"lo\":");
            out.push_str(&lo.to_string());
            out.push('}');
        }
        Value::Bool(b) => {
            out.push_str("{\"t\":\"bool\",\"v\":");
            out.push_str(if *b { "true" } else { "false" });
            out.push('}');
        }
        Value::Str(bytes) => {
            out.push_str("{\"t\":\"str\",\"hex\":\"");
            out.push_str(&hex(bytes));
            out.push_str("\"}");
        }
        Value::Tuple(vs) => {
            out.push_str("{\"t\":\"tuple\",\"vs\":[");
            vs.iter().fold(false, |sep, v1| {
                sep.then(|| out.push(','));
                push_value(out, v1);
                true
            });
            out.push_str("]}");
        }
        Value::None => out.push_str("{\"t\":\"none\"}"),
        Value::Some(v1) => {
            out.push_str("{\"t\":\"some\",\"v\":");
            push_value(out, v1);
            out.push('}');
        }
        Value::Ok(v1) => {
            out.push_str("{\"t\":\"ok\",\"v\":");
            push_value(out, v1);
            out.push('}');
        }
        Value::Err(v1) => {
            out.push_str("{\"t\":\"err\",\"v\":");
            push_value(out, v1);
            out.push('}');
        }
        Value::Closure => out.push_str("{\"t\":\"closure\"}"),
    }
}

fn push_signals(out: &mut String, signals: &[SigOut]) {
    out.push_str(",\"signals\":[");
    signals.iter().fold(false, |sep, s| {
        sep.then(|| out.push(','));
        out.push_str("{\"id\":");
        out.push_str(&s.id.to_string());
        out.push_str(",\"value\":");
        push_value(out, &s.value);
        out.push_str(",\"debug_hex\":\"");
        out.push_str(&hex(s.debug.as_bytes()));
        out.push_str("\"}");
        true
    });
    out.push_str("]}");
}

// Key order is fixed:  case, outcome, the outcome payload,
// js_consistent on a value line, js_hex, js_form, hint, signals.  Every
// payload is lowercase hex, so no string escaping is ever needed.
//
// js_consistent rides on the line because the batch is resumable: a run
// that exits 4 keeps going and reports 4 at the end, and the gate
// stitches its segments together, so the verdict has to be able to find
// an inconsistent case from the JSONL alone.
fn line_text(idx: usize, o: &Observed) -> String {
    let mut s = String::from("{\"case\":");
    s.push_str(&idx.to_string());
    match &o.outcome {
        Outcome::NoTerminate => {
            s.push_str(",\"outcome\":\"no_terminate\",\"hint\":\"");
            s.push_str(o.hint.wire());
            s.push_str("\"}");
            s
        }
        Outcome::Value { value, rendered } => {
            s.push_str(",\"outcome\":\"value\",\"value\":");
            push_value(&mut s, value);
            s.push_str(",\"rendered_hex\":\"");
            s.push_str(&hex(rendered));
            s.push_str("\",\"js_consistent\":");
            s.push_str(if o.js_consistent { "true" } else { "false" });
            push_tail(&mut s, o);
            s
        }
        Outcome::Panic { class, msg } => {
            s.push_str(",\"outcome\":\"panic\",\"class\":\"");
            s.push_str(class.wire());
            s.push_str("\",\"msg_hex\":\"");
            s.push_str(&hex(msg.as_bytes()));
            s.push('"');
            push_tail(&mut s, o);
            s
        }
    }
}

fn push_tail(s: &mut String, o: &Observed) {
    s.push_str(",\"js_hex\":\"");
    s.push_str(&hex(&o.js));
    s.push_str("\",\"js_form\":\"");
    s.push_str(o.form.wire());
    s.push_str("\",\"hint\":\"");
    s.push_str(o.hint.wire());
    s.push('"');
    push_signals(s, &o.signals);
}

pub fn write_line(out: &mut impl Write, idx: usize, o: &Observed) -> Result<(), Error> {
    let text = line_text(idx, o);
    out.write_all(text.as_bytes()).map_err(|_| Error::Io)?;
    out.write_all(b"\n").map_err(|_| Error::Io)?;
    out.flush().map_err(|_| Error::Io)
}

// ---------- the per-case timeout ----------

pub enum Step {
    Done(Observed),
    Timeout,
    Died,
}

// The case runs on its own thread and sends the observation home.  A
// while body whose condition stays true never returns, and the only way
// to observe that is to stop waiting:  the spinning thread dies with
// the process, and M24 resumes at the next index with --from.
pub fn run_one(f: fn() -> Observed, timeout: Duration) -> Step {
    let channel = mpsc::channel();
    let tx = channel.0;
    std::thread::spawn(move || {
        let _ = tx.send(f());
    });
    channel.1.recv_timeout(timeout).map_or_else(
        |e| match e {
            mpsc::RecvTimeoutError::Timeout => Step::Timeout,
            mpsc::RecvTimeoutError::Disconnected => Step::Died,
        },
        Step::Done,
    )
}

// ---------- entry point ----------

pub struct Case {
    pub run: fn() -> Observed,
    pub hint: Hint,
}

struct Opts {
    from: usize,
    to: usize,
    timeout: Duration,
}

enum Parse {
    Ok(Opts),
    Usage(&'static str),
}

fn num(s: &str) -> Option<usize> {
    s.parse::<usize>().ok()
}

fn parse_args(args: &[String], acc: Opts) -> Parse {
    match args {
        [] => Parse::Ok(acc),
        [flag, value, rest @ ..] if flag == "--from" => num(value).map_or(
            Parse::Usage(USAGE),
            |n| parse_args(rest, Opts { from: n, ..acc }),
        ),
        [flag, value, rest @ ..] if flag == "--to" => {
            num(value).map_or(Parse::Usage(USAGE), |n| {
                parse_args(rest, Opts { to: n, ..acc })
            })
        }
        // A zero timeout turns every case into no_terminate, and a
        // width that does not fit u64 used to be replaced by the
        // default in silence.  Both are usage errors now:  the gate
        // must never run a batch under a budget it did not ask for.
        [flag, value, rest @ ..] if flag == "--timeout-ms" => num(value)
            .and_then(|n| u64::try_from(n).ok())
            .filter(|ms| *ms > 0)
            .map_or(Parse::Usage(USAGE), |ms| {
                parse_args(
                    rest,
                    Opts {
                        timeout: Duration::from_millis(ms),
                        ..acc
                    },
                )
            }),
        _ => Parse::Usage(USAGE),
    }
}

fn parse(args: &[String], count: usize) -> Parse {
    let start = Opts {
        from: 0,
        to: count,
        timeout: Duration::from_millis(DEFAULT_TIMEOUT_MS),
    };
    match parse_args(args, start) {
        Parse::Usage(u) => Parse::Usage(u),
        Parse::Ok(o) => match () {
            () if o.to > count => Parse::Usage(USAGE),
            () if o.from > o.to => Parse::Usage(USAGE),
            () => Parse::Ok(o),
        },
    }
}

fn observed_bare(outcome: Outcome, hint: Hint) -> Observed {
    Observed {
        outcome,
        js: Vec::new(),
        form: Form::Absent,
        hint,
        signals: Vec::new(),
        js_consistent: true,
    }
}

// A case thread that unwound past its own catch cannot happen by
// design;  it is reported as an other panic and the batch continues.
fn died(hint: Hint) -> Observed {
    observed_bare(
        Outcome::Panic {
            class: Class::Other,
            msg: String::from("<case thread died>"),
        },
        hint,
    )
}

fn verdict(o: &Observed) -> Result<(), i32> {
    match () {
        () if matches!(o.outcome, Outcome::NoTerminate) => Err(3),
        () if !o.js_consistent => Err(4),
        () => Ok(()),
    }
}

fn one(cases: &[Case], i: usize, opts: &Opts, sink: &mut impl Write) -> Result<(), i32> {
    cases.get(i).map_or(Err(2), |c| {
        let observed = match run_one(c.run, opts.timeout) {
            Step::Done(o) => o,
            Step::Timeout => observed_bare(Outcome::NoTerminate, c.hint),
            Step::Died => died(c.hint),
        };
        write_line(sink, i, &observed)
            .map_or(Err(1), |()| Ok(()))
            .and_then(|()| verdict(&observed))
    })
}

// Exit 4 is FOLDED, never short-circuited: the inconsistent case has
// already written its line, the rest of the range is still worth
// running, and 0 < 4 so the worst code reaches the caller after the
// range.  Exit 3 still stops the process, because the spinning thread
// can only be reaped by process exit and the gate resumes with --from.
// Exit 1 (IO) and exit 2 (a missing index) are hard stops.
fn fold_code(worst: i32, code: i32) -> Result<i32, i32> {
    match () {
        () if code == 4 => Ok(worst.max(4)),
        () => Err(code),
    }
}

// The silent panic hook is installed once, before the first case, so
// stdout carries only JSONL and stderr stays empty.  It is never
// restored:  the process exists only to run the batch.
fn execute(cases: &[Case], opts: &Opts) -> i32 {
    std::panic::set_hook(Box::new(|_| {}));
    let out = std::io::stdout();
    let mut sink = out.lock();
    (opts.from..opts.to)
        .try_fold(0_i32, |worst, i| {
            one(cases, i, opts, &mut sink).map_or_else(|code| fold_code(worst, code), |()| Ok(worst))
        })
        .map_or_else(|code| code, |worst| worst)
}

// Exit codes:  0 every case in range produced a line, 1 an IO error, 2
// usage, 3 a case timed out, 4 the closure JS lost the direct body.
pub fn run(cases: &[Case]) -> i32 {
    let args: Vec<String> = std::env::args().skip(1).collect();
    match parse(&args, cases.len()) {
        Parse::Usage(u) => {
            let _ = writeln!(std::io::stderr(), "{u}");
            2
        }
        Parse::Ok(opts) => execute(cases, &opts),
    }
}

// The consistency check is the one piece of this file whose failure is
// silent by construction: a body check that answers true too often just
// stops reporting.  These tests pin the three rules that keep it loud,
// each with a NEGATIVE that must be rejected.  m23_gate.sh runs them
// with cargo test on the seed crate;  assert! lives only here, under
// cfg(test), never on the path a case runs.
#[cfg(test)]
mod tests {
    use super::{JS_IIFE_HEAD, JS_IIFE_TAIL, balanced, body_consistent, find, js_body, js_core};

    fn head_body_tail(body: &str) -> String {
        String::from("(() => { const [__external0] = [cx.hydrate(1.5)]; return ")
            + body
            + "; })()"
    }

    #[test]
    fn js_body_slices_a_site_with_externals() {
        let wire = head_body_tail("__external0");
        assert_eq!(js_body(wire.as_bytes()), Some("__external0"));
    }

    #[test]
    fn js_body_reads_a_zero_external_site_whole() {
        assert_eq!(js_body(b"cx.hydrate(true)"), Some("cx.hydrate(true)"));
    }

    #[test]
    fn js_body_fails_closed() {
        // Half a marker set, an empty body slice, empty bytes and
        // non-UTF-8 bytes are all None, which the caller reads as red.
        assert_eq!(js_body(b"() =&gt; foo; })()"), None);
        assert_eq!(js_body(b"(() => { const [] = []; return ; })()"), None);
        assert_eq!(js_body(b""), None);
        assert_eq!(js_body(&[0x66, 0xff, 0xfe]), None);
    }

    #[test]
    fn balanced_accepts_one_run_and_rejects_two() {
        assert!(balanced("{ a; }"));
        assert!(balanced("{ if (p) { x } else { y } }"));
        // The L4 shape: the depth returns to zero in the middle.
        assert!(!balanced("{ a; })() + (() =&gt; { z; }"));
        assert!(!balanced("plain"));
        assert!(!balanced(""));
        assert!(!balanced("{ a;"));
    }

    #[test]
    fn js_core_peels_only_a_balanced_block() {
        let block = String::from(JS_IIFE_HEAD) + "{ a; }" + JS_IIFE_TAIL;
        assert_eq!(js_core(&block), Some("{ a; }"));
        let two = String::from(JS_IIFE_HEAD) + "{ a; })() + (() =&gt; { z; }" + JS_IIFE_TAIL;
        assert_eq!(js_core(&two), None);
        assert_eq!(js_core("{ a; }"), None);
    }

    #[test]
    fn find_rejects_an_empty_needle() {
        assert!(!find(b"anything", b""));
        assert!(find(b"anything", b"thin"));
        assert!(!find(b"any", b"anything"));
    }

    #[test]
    fn body_consistent_holds_on_the_two_agreements() {
        // Whole body: the closure inserts its arrow after "return ".
        let direct = head_body_tail("__external0.add(cx.hydrate(1.5))");
        let closure = head_body_tail("() =&gt; __external0.add(cx.hydrate(1.5))");
        assert!(body_consistent(direct.as_bytes(), closure.as_bytes()));
        // Core: a block body loses its invoking wrapper in the closure.
        let direct_block = head_body_tail("(() =&gt; { __external0.clone(); })()");
        let closure_block = head_body_tail("() =&gt; { __external0.clone(); }");
        assert!(body_consistent(
            direct_block.as_bytes(),
            closure_block.as_bytes()
        ));
    }

    #[test]
    fn body_consistent_rejects_a_lost_body_and_a_drifted_shape() {
        let direct = head_body_tail("__external0.add(cx.hydrate(1.5))");
        let other = head_body_tail("() =&gt; __external0.sub(cx.hydrate(1.5))");
        assert!(!body_consistent(direct.as_bytes(), other.as_bytes()));
        // The L4 pair: two blocks added, against a closure that carries
        // both of them.  An unpeeled core would call this consistent.
        let two_blocks =
            head_body_tail("(() =&gt; { a; })() + (() =&gt; { z; })()");
        let carrier = head_body_tail("() =&gt; { a; })() + (() =&gt; { z; }");
        assert!(!body_consistent(two_blocks.as_bytes(), carrier.as_bytes()));
        // A half-present marker set fails CLOSED rather than agreeing,
        // even when the closure text carries the direct text verbatim.
        assert!(!body_consistent(
            b"() =&gt; foo; })()",
            b"xx () =&gt; foo; })() xx"
        ));
    }
}
