#!/usr/bin/env node
// Bundles src/**/*.luau into a single dist/londra.luau with a private require shim.
// Deterministic: same input produces byte-identical output.

import fs from "node:fs";
import path from "node:path";

const ROOT = process.cwd();
const SRC = path.join(ROOT, "src");
const ENTRY = path.join(SRC, "Londra.luau");
const DIST_DIR = path.join(ROOT, "dist");
const OUT = path.join(DIST_DIR, "londra.luau");

const REQUIRES = /require\s*\(\s*(["'])([^"']+)\1\s*\)/g;

function fail(message) {
	console.error("build: " + message);
	process.exit(1);
}

function walk(dir) {
	const out = [];
	for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
		const full = path.join(dir, entry.name);
		if (entry.isDirectory()) out.push(...walk(full));
		else if (entry.isFile() && entry.name.endsWith(".luau")) out.push(full);
	}
	return out;
}

function idOf(file) {
	const rel = path.relative(SRC, file).replace(/\\/g, "/");
	return rel.replace(/\.luau$/, "");
}

function resolveRequire(fromFile, request) {
	if (!request.startsWith(".")) return null;
	const base = path.resolve(path.dirname(fromFile), request);
	for (const candidate of [base + ".luau", path.join(base, "init.luau")]) {
		if (fs.existsSync(candidate)) return candidate;
	}
	fail(`unresolved require "${request}" in ${path.relative(ROOT, fromFile)}`);
}

const files = walk(SRC);
const byId = new Map(files.map((f) => [idOf(f), f]));
const deps = new Map();

for (const file of files) {
	const code = fs.readFileSync(file, "utf8");
	const list = [];
	for (const match of code.matchAll(REQUIRES)) {
		const target = resolveRequire(file, match[2]);
		if (target) list.push(target);
	}
	deps.set(file, list);
}

// Topological order, entry last. Cycles are a hard error.
const order = [];
const state = new Map();

function visit(file, stack) {
	const seen = state.get(file);
	if (seen === "done") return;
	if (seen === "open") fail(`require cycle: ${stack.concat(idOf(file)).join(" -> ")}`);
	state.set(file, "open");
	for (const dep of deps.get(file) ?? []) visit(dep, stack.concat(idOf(file)));
	state.set(file, "done");
	order.push(file);
}

visit(ENTRY, []);

const unreachable = files.filter((f) => !order.includes(f));
if (unreachable.length > 0) {
	fail("modules not reachable from init: " + unreachable.map(idOf).join(", "));
}

const chunks = [];
chunks.push("-- Londra UI Library");
chunks.push("-- build: deterministic, do not edit. Source lives in src/.");
chunks.push(`-- modules: ${order.length}`);
chunks.push("");
chunks.push("local __modules = {}");
chunks.push("local __cache = {}");
chunks.push("");
chunks.push("local function require(name)");
chunks.push("\tlocal cached = __cache[name]");
chunks.push("\tif cached ~= nil then");
chunks.push("\t\treturn cached");
chunks.push("\tend");
chunks.push("\tlocal factory = __modules[name]");
chunks.push("\tif factory == nil then");
chunks.push("\t\terror('Londra: module not found: ' .. tostring(name), 0)");
chunks.push("\tend");
chunks.push("\tlocal module = factory()");
chunks.push("\t__cache[name] = module");
chunks.push("\treturn module");
chunks.push("end");
chunks.push("");

for (const file of order) {
	let code = fs.readFileSync(file, "utf8").replace(/\r\n/g, "\n");
	code = code.replace(REQUIRES, (whole, quote, request) => {
		const target = resolveRequire(file, request);
		if (!target) return whole;
		return `require(${quote}${idOf(target)}${quote})`;
	});
	chunks.push(`__modules["${idOf(file)}"] = function()`);
	chunks.push(code.replace(/\s+$/, ""));
	chunks.push("end");
	chunks.push("");
}

chunks.push(`return require("Londra")`);
chunks.push("");

const output = chunks.join("\n");
fs.mkdirSync(DIST_DIR, { recursive: true });
const tmp = OUT + ".tmp";
fs.writeFileSync(tmp, output, "utf8");
fs.renameSync(tmp, OUT);

const bytes = Buffer.byteLength(output, "utf8");
console.log(`build: ${order.length} modules, ${output.split("\n").length} lines, ${bytes} bytes -> dist/londra.luau`);
