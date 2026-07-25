# bubblebox

[`nix`][nix] + [`bwrap`][bwrap] + [`rstrict`][rstrict] + `$CLI` = `${CLI}box`!

[nix]: https://nixos.org/
[bwrap]: https://github.com/containers/bubblewrap
[rstrict]: https://github.com/creslinux/rstrict

Generalizes numtide's [claudebox] over an arbitrary CLI binary, so the same sandboxing wrapper
serves multiple CLIs from one builder. Adds [Landlock LSM][landlock] integration (soon). Additional
CLIs are welcome. Verified to work on NixOS, Ubuntu WSL, and MacOS (via Seatbelt).

[claudebox]: https://github.com/numtide/claudebox
[landlock]: https://docs.kernel.org/security/landlock.html

Like numtide's claudebox, each CLI gets a generic NixOS environment with an isolated `$HOME` and...

- `./` in read-write mode
- (e.g.) `~/.claude` in read-write mode
- `/run/user/$UID` is hidden by default
- parent directories hidden by default

## Available CLIs

- `claudebox` — Claude Code
- `codexbox` — [OpenAI Codex CLI](https://github.com/openai/codex)
- `opencodebox` — [OpenCode](https://github.com/anomalyco/opencode)
- `hermesbox` — [Hermes Agent](https://github.com/nousresearch/hermes-agent)
- `pibox` — [pi agent](https://github.com/badlogic/pi-mono/)

## Getting started: Minimal flake with a numtide devshell

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    devshell.url = "github:numtide/devshell";
    flake-parts.url = "github:hercules-ci/flake-parts";
    bubblebox.url = "github:nix-tools/bubblebox";
  };

  outputs = { nixpkgs, devshell, flake-parts, bubblebox, ... }@inputs:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" ];
      imports = [ devshell.flakeModule ];
      perSystem = { pkgs, system, ... }: {
        _module.args.pkgs = import nixpkgs {
          inherit system;
          config.allowUnfree = true;
          overlays = [ bubblebox.overlays.default ];
        };
        devshells.default.packages = [
          pkgs.claudebox
          pkgs.opencodebox
          # pkgs.hermesbox
          # pkgs.pibox
        ];
      };
    };
}
```

## Command-line arguments

### `--rw` / `--ro`

Override mounts with `--rw PATH` / `--ro PATH`. Handy for working with git worktrees, or when you
want to add a program-specific directory from `$HOME` or elsewhere:

```sh
claudebox --rw ../worktree-base -- --continue  # `git commit` works now
claudebox --ro ~/Downloads/assets -- -c        # add extra out-of-band dir
claudebox --rw ~/Projects/another-thing        # when you work on two things
claudebox --rw ~/.cargo                        # share Cargo package cache
```

### `--allow-ssh-agent` / `--allow-gpg-agent` / `--allow-dbus` / `--allow-xdg-runtime`

`/run/user/$UID` is hidden by default. These flags punch a specific hole through for tools that
need to reach a running agent:

```sh
claudebox --allow-ssh-agent    # bind $SSH_AUTH_SOCK (e.g. `git push` over SSH)
claudebox --allow-gpg-agent    # bind the GPG agent socket (e.g. signed commits)
claudebox --allow-dbus         # bind the D-Bus session socket (e.g. OS keyring / Secret Service)
claudebox --allow-xdg-runtime  # expose the whole XDG runtime dir, not just one socket
```

`--allow-dbus` is a tighter alternative to `--allow-xdg-runtime` when a tool only needs the OS
keyring: it binds just the D-Bus session socket instead of the whole runtime dir.

### `--profile NAME`

See [Profiles](#profiles).

## Profiles

### `mounts`

A profile has a named list of mounts baked into a box at build time and selected at runtime with `--profile NAME`. A profile named `default` is active when `--profile` is not given. Inspired by [nono.sh](https://nono.sh) profiles, but configured with Nix instead of runtime config files.

```nix
{ pkgs, ... }:
let
  claudebox = pkgs.claudebox.override {
    parentMounts = "parent";  # "none" (default) | "parent" | "tree"
    profiles = {
      # active without --profile; plain strings mean read-only,
      # or use { path = "..."; mode = "rw"; } for read-write
      default.mounts = [ ];
    };
  };
in
{
  environment.systemPackages = [ claudebox ];
}
```

Profile mounts that don't exist on the host are skipped.

CLI `--rw`/`--ro` flags override profile mounts on overlap.

Note that `.override { profiles = ...; }` replaces the box's whole profile set.

### `parentMounts`

The `parentMounts` setting controls how much of the working tree's ancestry is bound read-only. It can be overridden per profile:

- `"none"` (default): only `./` is mounted (read-write); parent directories appear empty
- `"parent"`: `../` is also mounted, read-only, but any parents above that appear empty
- `"tree"`: the deepest ancestor below `$HOME` (or `/`) is mounted read-only, e.g. `~/Projects` when standing in `~/Projects/foo/bar`

`$HOME` and `/` themselves are never mounted. Prior to profiles, boxes behaved like `"tree"`; the default is now the more conservative `"none"`.

## This flake exposes

- **apps** for running without installing
- **packages** for installing into flakes
- **overlays.default** — for adding all programs to `pkgs`

## `nix run` without installing

```sh
nix run github:nix-tools/bubblebox#claudebox
nix run github:nix-tools/bubblebox#codexbox
nix run github:nix-tools/bubblebox#opencodebox
nix run github:nix-tools/bubblebox#hermesbox
nix run github:nix-tools/bubblebox#pibox
```

> **Note:** To forward arguments to the wrapped CLI under `nix run`, you need **two** `--`
> separators — the first ends `nix run`'s own arguments, the second is consumed by the box and
> tells it to forward the rest:
>
> ```sh
> nix run github:nix-tools/bubblebox#claudebox -- -- --continue
> nix run github:nix-tools/bubblebox#claudebox -- --allow-ssh-agent -- --resume
> ```

## Adding a new CLI

Add an entry to the `boxes` attrset in `nix/packages.nix`:

```nix
mybox = {
  tool = pkgs.my-cli;
  toolBinary = "my-cli";
  homeBindings = [ ".my-cli" ];
  defaultArgs = [ ];
  toolEnv = { };
  description = "Sandboxed environment for my-cli";
};
```

This produces the corresponding package, app, and overlay attribute
automatically. The builder is `mkBubblebox` in `nix/bubblebox.nix`.

## Add to `environment.systemPackages` via overlay

```nix
{
  nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  inputs.bubblebox.url = "github:nix-tools/bubblebox";
  inputs.bubblebox.inputs.nixpkgs.follows = "nixpkgs";

  outputs = { self, nixpkgs, bubblebox, ... }: {
    nixosConfigurations.example = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ({ pkgs, ... }: {
          nixpkgs.overlays = [ bubblebox.overlays.default ];
          environment.systemPackages = [
            pkgs.claudebox
            pkgs.opencodebox
            pkgs.hermesbox
            pkgs.pibox
          ];
        })
      ];
    };
  };
}
```

## License

MIT.

