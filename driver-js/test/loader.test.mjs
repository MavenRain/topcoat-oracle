import test from "node:test";
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import {
  existsSync,
  mkdirSync,
  mkdtempSync,
  realpathSync,
  rmSync,
  symlinkSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join, relative } from "node:path";
import { pathToFileURL } from "node:url";
import { cloneRootOf, cloneSrcOf } from "../loader.mjs";

const SRC_SUBPATH = "crates/topcoat-runtime/browser/src/";
const LOADER = new URL("../loader.mjs", import.meta.url).href;

// A clone whose crates directory is a SYMLINK to a sibling tree, which is
// how a checkout that shares one crates tree is laid out.  The source file
// imports "./dep" with no extension, so only arm 2 of the hook resolves it.
const linkedClone = (t) => {
  const root = realpathSync(mkdtempSync(join(tmpdir(), "topcoat clone ")));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  const src = join(root, "real crates", "topcoat-runtime", "browser", "src");
  mkdirSync(src, { recursive: true });
  writeFileSync(join(src, "dep.ts"), "export const w: number = 2;\n");
  writeFileSync(join(src, "ctx.ts"),
    'import { w } from "./dep";\nexport const ctx: number = w;\n');
  const clone = join(root, "linked clone");
  mkdirSync(clone);
  symlinkSync(join(root, "real crates"), join(clone, "crates"), "dir");
  const entry = join(root, "entry.mjs");
  writeFileSync(entry, [
    `import { cloneRootOf } from ${JSON.stringify(LOADER)};`,
    "const root = cloneRootOf(process.argv);",
    `const mod = await import(new URL(${JSON.stringify(SRC_SUBPATH)} + "ctx.ts", root).href);`,
    'console.log(JSON.stringify({ ctx: mod.ctx }));',
  ].join("\n") + "\n");
  return { root, clone, src, entry };
};

const directoryUrl = (path) =>
  `${pathToFileURL(path).href.replace(/\/+$/, "")}/`;

const fixture = (t) => {
  const root = mkdtempSync(join(tmpdir(), "topcoat loader "));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  const physical = join(root, "physical checkout");
  const link = join(root, "linked checkout");
  const ancestor = join(root, "linked parent");
  mkdirSync(physical);
  symlinkSync(physical, link, "dir");
  symlinkSync(root, ancestor, "dir");
  return { root, physical, link, ancestor };
};

test("absolute_relative_and_trailing_slash_paths_share_the_physical_root", (t) => {
  const { physical } = fixture(t);
  const expected = directoryUrl(realpathSync(physical));
  [physical, relative(process.cwd(), physical), `${physical}/`, `${physical}///`]
    .forEach((path) => assert.equal(cloneRootOf(["--clone", path]).href, expected));
  assert.equal(expected.includes("%20"), true);
});

test("a_symlink_clone_uses_the_same_root_as_Node_loaded_modules", (t) => {
  const { physical, link } = fixture(t);
  const expected = directoryUrl(realpathSync(physical));
  [link, relative(process.cwd(), link), `${link}/`].forEach((path) =>
    assert.equal(cloneRootOf(["--clone", path]).href, expected),
  );
  assert.notEqual(directoryUrl(link), expected);
});

test("symlink_ancestors_are_canonicalized_with_space_safe_URLs", (t) => {
  const { physical, ancestor } = fixture(t);
  const throughAncestor = join(ancestor, "physical checkout");
  assert.equal(
    cloneRootOf(["--clone", throughAncestor]).href,
    directoryUrl(realpathSync(physical)),
  );
});

test("missing_clones_retain_the_absolute_lexical_URL_for_worker_errors", (t) => {
  const { root, ancestor } = fixture(t);
  const paths = [join(root, "missing checkout"), join(ancestor, "missing checkout")];
  paths.flatMap((path) => [path, relative(process.cwd(), path), `${path}/`])
    .forEach((path) => {
      assert.equal(cloneRootOf(["--clone", path]).href, directoryUrl(path));
    });
});

test("a_dangling_symlink_retains_its_lexical_URL", (t) => {
  const { root } = fixture(t);
  const link = join(root, "dangling checkout");
  symlinkSync(join(root, "absent"), link, "dir");
  assert.equal(cloneRootOf(["--clone", link]).href, directoryUrl(link));
});

test("a_symlinked_source_directory_below_the_root_is_canonicalized", (t) => {
  const { clone, src } = linkedClone(t);
  const expected = directoryUrl(realpathSync(src));
  assert.equal(cloneSrcOf(["--clone", clone]).href, expected);
  // The lexical answer, which the hook used to rebuild, is the wrong one.
  assert.notEqual(new URL(SRC_SUBPATH, directoryUrl(clone)).href, expected);
});

test("an_extensionless_import_resolves_under_a_symlinked_source_directory", (t) => {
  const { clone, entry } = linkedClone(t);
  const out = execFileSync(process.execPath, [entry, "--clone", clone],
    { encoding: "utf8" });
  assert.equal(JSON.parse(out).ctx, 2);
});

test("a_missing_source_directory_keeps_its_lexical_URL", (t) => {
  const { root } = fixture(t);
  const absent = join(root, "absent checkout");
  assert.equal(cloneSrcOf(["--clone", absent]).href,
    new URL(SRC_SUBPATH, directoryUrl(absent)).href);
});

test("the_default_checkout_is_canonicalized_when_it_exists", () => {
  const lexical = new URL("../../../topcoat/", import.meta.url);
  const expected = existsSync(lexical)
    ? directoryUrl(realpathSync(lexical))
    : lexical.href;
  assert.equal(cloneRootOf([]).href, expected);
  assert.equal(cloneRootOf(["--clone"]).href, expected);
});
