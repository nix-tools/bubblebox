# bubblebox

Sandboxed launchers for CLI agents. Generalizes [numtide/claudebox][claudebox] over an arbitrary CLI
binary, so the same bubblewrap (Linux) / seatbelt (macOS) wrapping serves `claude`, `opencode`, and
`hermes` from one builder. Additional CLIs are welcome.

Like claudebox, each box gets its own isolated `$HOME`, only the agent's config files are bound
through, the project parent is read-only, the project itself is read-write, and `/run/user/$UID` is
hidden by default.

## What the flake exposes

- **apps** — sandboxed launchers for each CLI
- **packages** — underlying derivations for each CLI
- **overlays.default** — Nixpkgs overlay adding all boxes as top-level attributes

Available CLIs:

- `claudebox` — Claude Code
- `opencodebox` — opencode
- `hermesbox` — Hermes Agent

## Run one with `nix run`

```sh
nix run github:nix-tools/bubblebox#claudebox
nix run github:nix-tools/bubblebox#opencodebox
nix run github:nix-tools/bubblebox#hermesbox
```

## Forwarding arguments to the wrapped CLI

Each box accepts its own flags (e.g. `--allow-ssh-agent`) and forwards anything
after a literal `--` to the wrapped CLI. So when you invoke a box directly:

```sh
claudebox -- --continue
claudebox --allow-ssh-agent -- --resume
opencodebox -- run "fix the tests"
```

Under `nix run` you need **two** `--` separators: the first one ends `nix run`'s
own arguments, the second one is consumed by the box and tells it to forward
the rest:

```sh
nix run github:nix-tools/bubblebox#claudebox -- -- --continue
nix run github:nix-tools/bubblebox#claudebox -- --allow-ssh-agent -- --resume
nix run github:nix-tools/bubblebox#opencodebox -- -- run "fix the tests"
```

The same applies to `nix shell -c` and friends — anything that itself
interprets `--` consumes one before the box ever sees it.

## Add to `environment.systemPackages` via the overlay

```nix
{
  inputs.bubblebox.url = "github:nix-tools/bubblebox";

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
          ];
        })
      ];
    };
  };
}
```

## Minimal flake with a numtide devshell containing all three

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    devshell.url = "github:numtide/devshell";
    flake-parts.url = "github:hercules-ci/flake-parts";
    bubblebox.url = "github:nix-tools/bubblebox";
  };

  outputs = inputs:
    inputs.flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" ];
      imports = [ inputs.devshell.flakeModule ];
      perSystem = { pkgs, system, ... }: {
        _module.args.pkgs = import inputs.nixpkgs {
          inherit system;
          config.allowUnfree = true;
          overlays = [ inputs.bubblebox.overlays.default ];
        };
        devshells.default.packages = [
          pkgs.claudebox
          pkgs.opencodebox
          pkgs.hermesbox
        ];
      };
    };
}
```

`direnv allow` then `claudebox`, `opencodebox`, or `hermesbox`.

## Adding a new box

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

## License

MIT.

[claudebox]: https://github.com/numtide/claudebox
