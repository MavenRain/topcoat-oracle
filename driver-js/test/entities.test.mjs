// spec section 8.1
import test from "node:test";
import assert from "node:assert/strict";
import { decodeEntities } from "../lib/entities.mjs";

test("amp_decodes_to_an_ampersand", () => {
  assert.deepEqual(decodeEntities("&amp;"), { ok: true, value: "&" });
});

test("gt_decodes_to_a_greater_than", () => {
  assert.deepEqual(decodeEntities("&gt;"), { ok: true, value: ">" });
});

test("quot_decodes_to_a_double_quote", () => {
  assert.deepEqual(decodeEntities("&quot;"), { ok: true, value: '"' });
});

test("all_three_in_one_string", () => {
  assert.deepEqual(decodeEntities("a&amp;b&gt;c&quot;d"), {
    ok: true,
    value: 'a&b>c"d',
  });
});

test("a_string_with_no_entity_decodes_to_itself", () => {
  assert.deepEqual(decodeEntities("a<b>+c"), { ok: true, value: "a<b>+c" });
});

test("the_nesting_case_decodes_to_the_literal_text", () => {
  // "&amp;gt;" splits to ["", "amp;gt;"], so the entity contributes "&"
  // and "gt;" stays literal.  A chain of replaceAll calls would produce
  // ">" here, which is why the split is the implementation.
  assert.deepEqual(decodeEntities("&amp;gt;"), { ok: true, value: "&gt;" });
});

test("a_bare_ampersand_is_rejected_with_its_offset", () => {
  assert.deepEqual(decodeEntities("a&b"), {
    ok: false,
    error: "entity",
    at: 1,
  });
});

test("an_unknown_entity_is_rejected", () => {
  // The comment escaper never emits "&lt;": escape.rs:105-106 has three
  // entries and "<" is not one of them.
  assert.deepEqual(decodeEntities("&lt;"), {
    ok: false,
    error: "entity",
    at: 0,
  });
});

test("quot_inside_a_js_string_literal_is_decoded", () => {
  assert.deepEqual(decodeEntities("cx.hydrate(&quot;ok&quot;)"), {
    ok: true,
    value: 'cx.hydrate("ok")',
  });
});

test("the_empty_string_decodes_to_itself", () => {
  assert.deepEqual(decodeEntities(""), { ok: true, value: "" });
});

test("the_offset_is_counted_in_utf8_bytes", () => {
  // Two bytes for the e acute, so the bare ampersand sits at byte 2.
  assert.deepEqual(decodeEntities("é&x"), {
    ok: false,
    error: "entity",
    at: 2,
  });
});
