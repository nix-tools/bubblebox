// Mount tests for bubblebox, driven through a purpose-built "testbox" whose
// path is passed in via $BUBBLEBOX_TESTBOX (see nix/tests.nix).
//
// Most tests run the launcher in dry-run mode (BUBBLEBOX_DRYRUN=1): the
// launcher resolves the full sandbox invocation and prints it as JSON without
// spawning bwrap, so we can assert *which* mounts a profile or flag produces
// without mounting anything. One end-to-end test actually runs bwrap and
// observes real read-only/read-write/absent behaviour from inside the sandbox
// — nested user namespaces let this work inside the Nix build sandbox.

const { test } = require("node:test");
const assert = require("node:assert");
const { execFileSync } = require("node:child_process");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

const BOX = process.env.BUBBLEBOX_TESTBOX;
assert.ok(BOX, "BUBBLEBOX_TESTBOX must point at the testbox binary");

// A throwaway HOME plus a nested working directory, both realpath-resolved so
// mount sources (which the launcher realpaths) compare equal to what we set up.
function scratch() {
	const home = fs.realpathSync(fs.mkdtempSync(path.join(os.tmpdir(), "bb-home-")));
	const base = fs.realpathSync(fs.mkdtempSync(path.join(os.tmpdir(), "bb-work-")));
	const cwd = path.join(base, "a", "b", "c");
	fs.mkdirSync(cwd, { recursive: true });
	for (const d of ["d/default", "d/roA", "d/rwA"]) {
		fs.mkdirSync(path.join(cwd, d), { recursive: true });
	}
	fs.writeFileSync(path.join(cwd, "d/roA/marker"), "hello\n");
	fs.mkdirSync(path.join(home, "tthome"), { recursive: true });
	const env = { ...process.env, HOME: home, USER: "tester" };
	return { home, cwd, env };
}

// Resolve the sandbox invocation for `boxArgs` without spawning it.
function plan(boxArgs, { cwd, env }) {
	const out = execFileSync(BOX, boxArgs, {
		cwd,
		env: { ...env, BUBBLEBOX_DRYRUN: "1" },
		encoding: "utf8",
	});
	return JSON.parse(out);
}

// Flatten a bwrap invocation into its bind mounts, in order.
function binds(pl) {
	const modes = {
		"--bind": "rw",
		"--bind-try": "rw",
		"--ro-bind": "ro",
		"--ro-bind-try": "ro",
	};
	const out = [];
	for (let i = 0; i < pl.args.length; i++) {
		const mode = modes[pl.args[i]];
		if (mode) {
			out.push({ mode, src: pl.args[i + 1], dst: pl.args[i + 2] });
			i += 2;
		}
	}
	return out;
}

// Last bind wins on overlap — mirrors how bwrap applies binds in order.
function effective(pl, dst) {
	return binds(pl)
		.filter((b) => b.dst === dst)
		.at(-1);
}

test("no profile flag activates the 'default' profile", () => {
	const s = scratch();
	const b = binds(plan([], s));
	assert.ok(
		b.some((m) => m.dst === path.join(s.cwd, "d/default") && m.mode === "ro"),
		"default profile mount should be present",
	);
});

test("--profile selects that profile's mounts, not 'default'", () => {
	const s = scratch();
	const b = binds(plan(["--profile", "ro"], s));
	assert.ok(b.some((m) => m.dst === path.join(s.cwd, "d/roA")));
	assert.ok(
		!b.some((m) => m.dst === path.join(s.cwd, "d/default")),
		"selecting a profile should replace 'default', not add to it",
	);
});

test("read-only profile mounts bind read-only", () => {
	const s = scratch();
	assert.strictEqual(
		effective(plan(["--profile", "ro"], s), path.join(s.cwd, "d/roA")).mode,
		"ro",
	);
});

test("read-write profile mounts bind read-write", () => {
	const s = scratch();
	assert.strictEqual(
		effective(plan(["--profile", "rw"], s), path.join(s.cwd, "d/rwA")).mode,
		"rw",
	);
});

test("~ in a profile mount expands to $HOME", () => {
	const s = scratch();
	const b = binds(plan(["--profile", "tilde"], s));
	assert.ok(b.some((m) => m.dst === path.join(s.home, "tthome")));
});

test("a --rw flag overrides an overlapping read-only profile mount", () => {
	const s = scratch();
	const dst = path.join(s.cwd, "d/roA");
	const pl = plan(["--profile", "ro", "--rw", "d/roA"], s);
	assert.strictEqual(effective(pl, dst).mode, "rw", "CLI mount should win");
});

test("parentMounts=parent binds the immediate parent read-only", () => {
	const s = scratch();
	const b = binds(plan(["--profile", "parent"], s));
	assert.ok(
		b.some((m) => m.dst === path.dirname(s.cwd) && m.mode === "ro"),
		"immediate parent should be bound read-only",
	);
});

test("parentMounts=tree binds the top-of-tree, not the immediate parent", () => {
	const s = scratch();
	const b = binds(plan(["--profile", "tree"], s));
	// cwd is <base>/a/b/c under /…/tmp; the deepest ancestor below "/" is <tmp>.
	assert.ok(
		!b.some((m) => m.dst === path.dirname(s.cwd)),
		"tree should not stop at the immediate parent",
	);
	assert.ok(
		b.some((m) => m.dst === os.tmpdir() && m.mode === "ro") ||
			b.some((m) => m.dst === fs.realpathSync(os.tmpdir()) && m.mode === "ro"),
		"tree should bind the top ancestor below /",
	);
});

test("end-to-end: profile mounts really are readable, writable, or absent", () => {
	const s = scratch();
	fs.writeFileSync(path.join(s.home, "secret"), "should-not-leak\n");
	const script = [
		"set -e",
		"touch ./wtest", // working tree is read-write
		"cat d/roA/marker >/dev/null", // read-only mount is readable
		'if echo x >d/roA/blocked 2>/dev/null; then echo RO_NOT_ENFORCED; exit 1; fi',
		"echo y >d/rwA/out", // read-write mount is writable
		'if [ -e "$HOME/secret" ]; then echo HOME_LEAKED; exit 1; fi', // empty home
		"echo E2E_OK",
	].join("\n");

	const out = execFileSync(BOX, ["--profile", "e2e", "--", "-c", script], {
		cwd: s.cwd,
		env: s.env,
		encoding: "utf8",
	});

	assert.match(out, /E2E_OK/);
	assert.ok(fs.existsSync(path.join(s.cwd, "wtest")), "write to working tree");
	assert.ok(fs.existsSync(path.join(s.cwd, "d/rwA/out")), "write to rw mount");
});
