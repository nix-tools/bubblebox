#!/usr/bin/env node
// bubblebox - Run an arbitrary CLI agent in a sandbox.
//
// Generalized from numtide/claudebox. The wrapper that invokes this script
// (built by nix/bubblebox.nix) sets BUBBLEBOX_CONFIG to a JSON file shaped
// like:
//
//   {
//     "name":         "claudebox",
//     "tool":         "claude",
//     "homeBindings": [".claude", ".claude.json"],
//     "defaultArgs":  ["--dangerously-skip-permissions"],
//     "env":          { "DISABLE_AUTOUPDATER": "1" }
//   }
//
// `name` and `tool` are required; the rest default to empty.
//
// Extra arguments after `--` on the command line are forwarded verbatim to
// the wrapped tool, after `defaultArgs` (modeled on numtide/claudebox#5).

const { execSync, spawn } = require("child_process");
const fs = require("fs");
const path = require("path");
const process = require("process");

// =============================================================================
// Config loading (from $BUBBLEBOX_CONFIG)
// =============================================================================

function loadBoxConfig() {
	const configPath = process.env.BUBBLEBOX_CONFIG;
	if (!configPath) {
		console.error(
			"bubblebox: BUBBLEBOX_CONFIG is not set. This script is meant to be invoked via the nix wrapper.",
		);
		process.exit(2);
	}
	const raw = JSON.parse(fs.readFileSync(configPath, "utf8"));
	if (!raw.name || !raw.tool) {
		throw new Error(
			`bubblebox: config at ${configPath} is missing required fields (name, tool)`,
		);
	}
	return {
		name: raw.name,
		tool: raw.tool,
		homeBindings: raw.homeBindings || [],
		defaultArgs: raw.defaultArgs || [],
		env: raw.env || {},
	};
}

const BOX = loadBoxConfig();

// =============================================================================
// Utility Functions
// =============================================================================

function getRepoRoot(projectDir) {
	try {
		return execSync("git rev-parse --show-toplevel 2>/dev/null", {
			encoding: "utf8",
			cwd: projectDir,
		}).trim();
	} catch {
		return projectDir;
	}
}

function randomHex(length) {
	const chars = "0123456789abcdef";
	let result = "";
	for (let i = 0; i < length; i++) {
		result += chars[Math.floor(Math.random() * chars.length)];
	}
	return result;
}

function realpath(p) {
	return fs.realpathSync(p);
}

function pathExists(p) {
	try {
		fs.accessSync(p);
		return true;
	} catch {
		return false;
	}
}

function isDirectory(p) {
	try {
		return fs.statSync(p).isDirectory();
	} catch {
		return false;
	}
}

function getTmpDir() {
	return process.env.TMPDIR || process.env.TEMP || process.env.TMP || "/tmp";
}

function shellQuote(s) {
	return `'${String(s).replace(/'/g, "'\\''")}'`;
}

// =============================================================================
// User-level config (~/.config/<name>/config.json)
// =============================================================================

const CONFIG_DEFAULTS = {
	allowSshAgent: false,
	allowGpgAgent: false,
	allowXdgRuntime: false,
};

function getUserConfigPath() {
	const xdgConfig =
		process.env.XDG_CONFIG_HOME || path.join(process.env.HOME, ".config");
	return path.join(xdgConfig, BOX.name, "config.json");
}

function loadUserConfig() {
	const configPath = getUserConfigPath();
	try {
		const content = fs.readFileSync(configPath, "utf8");
		return { ...CONFIG_DEFAULTS, ...JSON.parse(content) };
	} catch (err) {
		if (err.code !== "ENOENT") {
			console.error(
				`Warning: Failed to load config from ${configPath}: ${err.message}`,
			);
		}
		return { ...CONFIG_DEFAULTS };
	}
}

// =============================================================================
// Sandbox Interface
// =============================================================================

class Sandbox {
	constructor(config) {
		this.config = config;
	}

	wrap(_script) {
		throw new Error("Sandbox.wrap() must be implemented by subclass");
	}

	spawn(script) {
		const { cmd, args, env } = this.wrap(script);
		return spawn(cmd, args, { stdio: "inherit", env });
	}

	static create(config) {
		const platform = process.platform;
		switch (platform) {
			case "linux":
				return new BubblewrapSandbox(config);
			case "darwin":
				return new SeatbeltSandbox(config);
			default:
				throw new Error(
					`Unsupported platform: ${platform}. Supported: linux, darwin (macOS)`,
				);
		}
	}
}

// =============================================================================
// Linux: Bubblewrap Sandbox
// =============================================================================

class BubblewrapSandbox extends Sandbox {
	wrap(script) {
		const {
			sandboxHome,
			homeBindMounts,
			shareTree,
			repoRoot,
			allowSshAgent,
			allowGpgAgent,
			allowXdgRuntime,
		} = this.config;

		const home = process.env.HOME;
		const user = process.env.USER;
		const pathEnv = process.env.PATH;

		const args = [
			"--dev", "/dev",
			"--proc", "/proc",
			"--ro-bind-try", "/usr", "/usr",
			"--ro-bind-try", "/bin", "/bin",
			"--ro-bind-try", "/lib", "/lib",
			"--ro-bind-try", "/lib64", "/lib64",
			"--ro-bind", "/etc", "/etc",

			// Selective /run mounts (skip /run/user/$UID by default).
			"--ro-bind-try", "/run/systemd/resolve", "/run/systemd/resolve",
			"--ro-bind-try", "/run/current-system", "/run/current-system",

			// WSL2: /etc/resolv.conf is a symlink to /mnt/wsl/resolv.conf.
			"--ro-bind-try", "/mnt/wsl", "/mnt/wsl",
			"--ro-bind-try", "/run/booted-system", "/run/booted-system",
			"--ro-bind-try", "/run/opengl-driver", "/run/opengl-driver",
			"--ro-bind-try", "/run/opengl-driver-32", "/run/opengl-driver-32",
			"--ro-bind-try", "/run/nixos", "/run/nixos",
			"--ro-bind-try", "/run/wrappers", "/run/wrappers",

			"--ro-bind", "/nix", "/nix",
			"--bind", "/nix/var/nix/daemon-socket", "/nix/var/nix/daemon-socket",

			"--tmpfs", "/tmp",

			// Empty isolated home; tool-specific paths overlaid below.
			"--bind", sandboxHome, home,
		];

		// Per-tool home bindings (e.g. ~/.claude, ~/.claude.json).
		for (const { src, dst } of homeBindMounts) {
			args.push("--bind", src, dst);
		}

		args.push(
			"--unshare-all",
			"--share-net",
			"--setenv", "HOME", home,
			"--setenv", "USER", user,
			"--setenv", "PATH", pathEnv,
			"--setenv", "TMPDIR", "/tmp",
			"--setenv", "TEMPDIR", "/tmp",
			"--setenv", "TEMP", "/tmp",
			"--setenv", "TMP", "/tmp",
		);

		if (shareTree !== repoRoot) {
			args.push("--ro-bind", shareTree, shareTree);
		}
		args.push("--bind", repoRoot, repoRoot);

		const xdgRuntimeDir =
			process.env.XDG_RUNTIME_DIR || `/run/user/${process.getuid()}`;

		if (allowXdgRuntime) {
			if (isDirectory(xdgRuntimeDir)) {
				args.push("--ro-bind", xdgRuntimeDir, xdgRuntimeDir);
				args.push("--setenv", "XDG_RUNTIME_DIR", xdgRuntimeDir);
			}
		} else {
			if (allowSshAgent && process.env.SSH_AUTH_SOCK) {
				const sock = process.env.SSH_AUTH_SOCK;
				if (pathExists(sock)) {
					args.push("--ro-bind", sock, sock);
					args.push("--setenv", "SSH_AUTH_SOCK", sock);
				}
			}
			if (allowGpgAgent) {
				const gpgDir = path.join(xdgRuntimeDir, "gnupg");
				if (isDirectory(gpgDir)) {
					args.push("--ro-bind", gpgDir, gpgDir);
				}
			}
		}

		args.push("bash", "-c", script);

		return { cmd: "bwrap", args, env: process.env };
	}
}

// =============================================================================
// macOS: Seatbelt Sandbox (sandbox-exec)
// =============================================================================

class SeatbeltSandbox extends Sandbox {
	wrap(script) {
		const { repoRoot } = this.config;

		const seatbeltProfile = process.env.BUBBLEBOX_SEATBELT_PROFILE;
		if (!seatbeltProfile || !pathExists(seatbeltProfile)) {
			throw new Error(
				"Seatbelt profile not found. Set BUBBLEBOX_SEATBELT_PROFILE environment variable.",
			);
		}

		const basePolicy = fs.readFileSync(seatbeltProfile, "utf8");
		const canonicalRepoRoot = realpath(repoRoot);
		const tmpdir = getTmpDir();
		const canonicalTmpdir = realpath(tmpdir);
		const canonicalSlashTmp = realpath("/tmp");

		const writablePaths = [
			'(subpath (param "PROJECT_DIR"))',
			'(subpath (param "TMPDIR"))',
		];
		if (canonicalTmpdir !== canonicalSlashTmp) {
			writablePaths.push('(subpath (param "SLASH_TMP"))');
		}

		const dynamicPolicy = `
; Allow read-only file operations
(allow file-read*)

; Allow writes to project and temp directories
(allow file-write*
  ${writablePaths.join("\n  ")})

; Network access for the agent's API calls
(allow network-outbound)
(allow network-inbound)
(allow system-socket)
`;

		const fullPolicy = basePolicy + "\n" + dynamicPolicy;

		const args = [
			"-p",
			fullPolicy,
			`-DPROJECT_DIR=${canonicalRepoRoot}`,
			`-DTMPDIR=${canonicalTmpdir}`,
		];
		if (canonicalTmpdir !== canonicalSlashTmp) {
			args.push(`-DSLASH_TMP=${canonicalSlashTmp}`);
		}
		args.push("--", "bash", "-c", script);

		return { cmd: "/usr/bin/sandbox-exec", args, env: process.env };
	}
}

// =============================================================================
// CLI Argument Parsing
// =============================================================================

function mergeOptions(cliOverrides, fileConfig) {
	return {
		allowSshAgent:
			cliOverrides.allowSshAgent !== undefined
				? cliOverrides.allowSshAgent
				: fileConfig.allowSshAgent,
		allowGpgAgent:
			cliOverrides.allowGpgAgent !== undefined
				? cliOverrides.allowGpgAgent
				: fileConfig.allowGpgAgent,
		allowXdgRuntime:
			cliOverrides.allowXdgRuntime !== undefined
				? cliOverrides.allowXdgRuntime
				: fileConfig.allowXdgRuntime,
	};
}

function parseArgs(args) {
	const fileConfig = loadUserConfig();
	const cliOverrides = {
		allowSshAgent: undefined,
		allowGpgAgent: undefined,
		allowXdgRuntime: undefined,
	};

	let i = 0;
	while (i < args.length) {
		const arg = args[i];
		switch (arg) {
			case "--allow-ssh-agent":
				cliOverrides.allowSshAgent = true;
				i++;
				break;
			case "--allow-gpg-agent":
				cliOverrides.allowGpgAgent = true;
				i++;
				break;
			case "--allow-xdg-runtime":
				cliOverrides.allowXdgRuntime = true;
				i++;
				break;
			case "-h":
			case "--help":
				showHelp();
				process.exit(0);
				break;
			case "--":
				return {
					...mergeOptions(cliOverrides, fileConfig),
					toolArgs: args.slice(i + 1),
				};
			default:
				console.error(`Unknown option: ${arg}`);
				console.error("Use --help for usage information");
				process.exit(1);
		}
	}

	return { ...mergeOptions(cliOverrides, fileConfig), toolArgs: [] };
}

function showHelp() {
	const configPath = getUserConfigPath();
	const dflt = BOX.defaultArgs.length
		? `\n  By default, ${BOX.tool} is invoked with: ${BOX.defaultArgs.join(" ")}`
		: "";
	console.log(`Usage: ${BOX.name} [OPTIONS] [-- TOOL_ARGS...]

Sandboxed launcher for "${BOX.tool}".${dflt}

Options:
  --allow-ssh-agent           Allow access to SSH agent socket
  --allow-gpg-agent           Allow access to GPG agent socket
  --allow-xdg-runtime         Allow full XDG runtime directory access
  -h, --help                  Show this help message

Forward extra arguments to ${BOX.tool} after a literal '--':

  ${BOX.name} -- --foo bar
  ${BOX.name} --allow-ssh-agent -- --resume

Configuration:
  Settings can be configured in ${configPath}.
  CLI flags override config-file settings.

  Example:
    {
      "allowSshAgent": false,
      "allowGpgAgent": false,
      "allowXdgRuntime": false
    }`);
}

// =============================================================================
// Main
// =============================================================================

function main() {
	const args = process.argv.slice(2);
	const options = parseArgs(args);

	const projectDir = process.cwd();
	const repoRoot = getRepoRoot(projectDir);
	const sessionId = randomHex(8);

	const home = process.env.HOME;
	const sandboxHome = path.join(getTmpDir(), `${BOX.name}-${sessionId}`);

	const cleanup = () => {
		try {
			fs.rmSync(sandboxHome, { recursive: true, force: true });
		} catch {
			// Ignore cleanup errors.
		}
	};
	process.on("exit", cleanup);
	process.on("SIGINT", () => {
		cleanup();
		process.exit(130);
	});
	process.on("SIGTERM", () => {
		cleanup();
		process.exit(143);
	});

	fs.mkdirSync(sandboxHome, { recursive: true });

	// Resolve tool-specific home bindings: ensure each src exists on the host
	// (creating the directory or empty file as needed) and bind to the same
	// path under the sandbox home.
	const homeBindMounts = [];
	for (const rel of BOX.homeBindings) {
		const src = path.join(home, rel);
		const dst = path.join(home, rel);
		if (!pathExists(src)) {
			// Heuristic: paths ending in .json (or any extension other than no-ext)
			// are created as empty files; everything else as a directory.
			if (path.extname(rel)) {
				fs.mkdirSync(path.dirname(src), { recursive: true });
				fs.writeFileSync(src, "");
			} else {
				fs.mkdirSync(src, { recursive: true });
			}
		}
		homeBindMounts.push({ src, dst });
	}

	const realRepoRoot = realpath(repoRoot);
	const realHome = realpath(home);
	let shareTree;
	if (realRepoRoot.startsWith(realHome + "/")) {
		const relPath = realRepoRoot.slice(realHome.length + 1);
		const topDir = relPath.split("/")[0];
		shareTree = path.join(realHome, topDir);
	} else {
		shareTree = realRepoRoot;
	}

	let sandbox;
	try {
		sandbox = Sandbox.create({
			sandboxHome,
			homeBindMounts,
			shareTree,
			repoRoot,
			allowSshAgent: options.allowSshAgent,
			allowGpgAgent: options.allowGpgAgent,
			allowXdgRuntime: options.allowXdgRuntime,
		});
	} catch (err) {
		console.error(`Error: ${err.message}`);
		process.exit(1);
	}

	const allArgs = [...BOX.defaultArgs, ...options.toolArgs]
		.map(shellQuote)
		.join(" ");
	const script = `
cd ${shellQuote(projectDir)}
exec ${shellQuote(BOX.tool)}${allArgs ? " " + allArgs : ""}
`;

	const child = sandbox.spawn(script);
	child.on("close", (code) => process.exit(code || 0));
}

main();
