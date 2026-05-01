# bubblebox

[Bubblewrap][bubblewrap]/seatbelt-sandboxed launchers for CLIs. Generalizes numtide's
[claudebox][claudebox] over an arbitrary CLI binary, so the same bubblewrap (Linux) / seatbelt
(macOS) wrapping serves multiple CLIs from one builder. Additional CLIs are welcome.

Like numtide's claudebox, each CLI gets a generic NixOS with an isolated `$HOME` and...
- `./` in read-write mode
- `../` in read-only mode
- (e.g.) `~/.claude` in read-write mode 
- `/run/user/$UID` is hidden by default

## Available CLIs

- `claudebox` — Claude Code
- `opencodebox` — [OpenCode](https://github.com/anomalyco/opencode)
- `hermesbox` — [Hermes Agent](https://github.com/nousresearch/hermes-agent)
- `pibox` — [pi agent](https://github.com/badlogic/pi-mono/)

## This flake exposes

- **apps** for running without installing
- **packages** for installing into flakes
- **overlays.default** — for adding all programs to `pkgs`

## `nix run` without installing

```sh
nix run github:nix-tools/bubblebox#claudebox
nix run github:nix-tools/bubblebox#opencodebox
nix run github:nix-tools/bubblebox#hermesbox
nix run github:nix-tools/bubblebox#pibox
```

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

## Forwarding arguments to the wrapped CLI

Each box accepts its own flags (e.g. `--allow-ssh-agent`) and forwards anything
after a literal `--` to the wrapped CLI. So when you invoke a box directly:

```sh
claudebox -- --continue
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

## Add to `environment.systemPackages` via the overlay

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

## Minimal flake with a numtide devshell

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
          pkgs.pibox
        ];
      };
    };
}
```

`direnv allow` then `claudebox`, `opencodebox`, `hermesbox`, or `pibox`.

## License

MIT.

[bubblewrap]: https://github.com/containers/bubblewrap
[claudebox]: https://github.com/numtide/claudebox
