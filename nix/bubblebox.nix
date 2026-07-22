# Generic builder for "<tool>box" — wraps a CLI in a bwrap/seatbelt sandbox.
#
# Each box is a thin makeWrapper around node + a launcher script (bubblebox.js)
# parameterized by a JSON config that names the tool, its binary, the home
# paths to bind through, default args, mount profiles, and any env to set.
#
# Exposed as `mkBubblebox` (perSystem _module.arg) so packages.nix can call:
#
#   mkBubblebox { name = "claudebox"; tool = pkgs.claude-code; ... }
#
# Arguments are validated through the module system, so a mistyped setting
# (wrong enum value, wrong field name) fails at Nix eval time. The builder is
# makeOverridable, so consumers can tweak an installed box:
#
#   pkgs.claudebox.override {
#     profiles.default.mounts = [ "~/.config/gh" ];
#   }
{
  perSystem =
    { pkgs, lib, ... }:
    let
      # A mount is either a plain path string (read-only) or an attrset
      # { path; mode = "ro"|"rw"; }. Paths may start with "~/" (expanded to
      # $HOME at runtime) and are skipped if missing on the host.
      mountType =
        let
          mountSubmodule = lib.types.submodule {
            options = {
              path = lib.mkOption {
                type = lib.types.str;
                description = "Host path to bind into the sandbox; \"~/\" expands to \$HOME at runtime.";
              };
              mode = lib.mkOption {
                type = lib.types.enum [
                  "ro"
                  "rw"
                ];
                default = "ro";
                description = "Whether the path is bound read-only or read-write.";
              };
            };
          };
        in
        lib.types.coercedTo lib.types.str (path: { inherit path; }) mountSubmodule;

      parentMountsType = lib.types.enum [
        "none"
        "parent"
        "tree"
      ];

      profileType = lib.types.submodule {
        options = {
          mounts = lib.mkOption {
            type = lib.types.listOf mountType;
            default = [ ];
            description = "Extra host paths bound into the sandbox when this profile is active.";
          };
          parentMounts = lib.mkOption {
            type = lib.types.nullOr parentMountsType;
            default = null;
            description = "Override the box-level parentMounts setting for this profile.";
          };
        };
      };

      mkBoxOptions = args: {
        options = {
          # Name of the produced wrapper, e.g. "claudebox".
          name = lib.mkOption { type = lib.types.str; };

          # The CLI derivation being wrapped, e.g. pkgs.claude-code.
          tool = lib.mkOption { type = lib.types.package; };

          # Binary inside `tool` to invoke; defaults to its meta.mainProgram.
          toolBinary = lib.mkOption {
            type = lib.types.str;
            default = args.tool.meta.mainProgram or args.name;
          };

          # Paths under $HOME to bind through into the sandbox, e.g.
          # [ ".claude" ".claude.json" ]. Created on the host if missing.
          homeBindings = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ ];
          };

          # Args always passed to the wrapped tool (before any user args).
          defaultArgs = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ ];
          };

          # Extra env vars set on the wrapped tool (inside the sandbox).
          toolEnv = lib.mkOption {
            type = lib.types.attrsOf lib.types.str;
            default = { };
          };

          # Named mount profiles, selected at runtime with --profile NAME.
          # A profile named "default" is active when no --profile is given.
          profiles = lib.mkOption {
            type = lib.types.attrsOf profileType;
            default = { };
          };

          # How much of the working tree's ancestry to bind read-only:
          #   "none"   — only the working tree itself (read-write)
          #   "parent" — also the immediate parent directory, read-only
          #   "tree"   — also the deepest ancestor below $HOME (or /), read-only
          parentMounts = lib.mkOption {
            type = parentMountsType;
            default = "none";
          };

          description = lib.mkOption {
            type = lib.types.str;
            default = "Sandboxed environment for ${args.name}";
          };

          homepage = lib.mkOption {
            type = lib.types.str;
            default = "https://github.com/sshine/bubblebox";
          };

          # Launcher source dir; overridable for vendoring.
          sourceDir = lib.mkOption {
            type = lib.types.path;
            default = ../src;
          };
        };
      };

      mkBubblebox = lib.makeOverridable (
        args:
        let
          box =
            (lib.evalModules {
              modules = [
                (mkBoxOptions args)
                { config = args; }
              ];
            }).config;

          inherit (box)
            name
            tool
            toolBinary
            description
            homepage
            sourceDir
            toolEnv
            ;

          inherit (pkgs.stdenv) isLinux isDarwin;

          tools = pkgs.buildEnv {
            name = "${name}-tools";
            paths = with pkgs; [
              git
              ripgrep
              fd
              coreutils
              gnugrep
              gnused
              gawk
              findutils
              which
              tree
              curl
              wget
              jq
              less
              zsh
              nix
            ];
          };

          sandboxTools = lib.optional isLinux pkgs.bubblewrap;

          config = {
            inherit (box)
              name
              homeBindings
              defaultArgs
              profiles
              parentMounts
              ;
            tool = toolBinary;
            env = toolEnv;
          };

          configFile = pkgs.writeText "${name}-config.json" (builtins.toJSON config);

          seatbeltProfile = "${sourceDir}/seatbelt.sbpl";
        in
        pkgs.runCommand name
          {
            nativeBuildInputs = [ pkgs.makeWrapper ];
            passthru = { inherit config; };
            meta = {
              mainProgram = name;
              inherit description homepage;
              sourceProvenance = with lib.sourceTypes; [ fromSource ];
              platforms = lib.platforms.linux ++ lib.platforms.darwin;
              license = lib.licenses.mit;
            };
          }
          ''
            mkdir -p $out/bin $out/share/${name} $out/libexec/${name}

            cp ${sourceDir}/bubblebox.js $out/libexec/${name}/bubblebox.js
            cp ${configFile}             $out/share/${name}/config.json
            cp ${seatbeltProfile}        $out/share/${name}/seatbelt.sbpl

            makeWrapper ${pkgs.nodejs}/bin/node $out/bin/${name} \
              --add-flags $out/libexec/${name}/bubblebox.js \
              --set BUBBLEBOX_CONFIG $out/share/${name}/config.json \
              --prefix PATH : $out/libexec/${name} \
              --prefix PATH : ${
                lib.makeBinPath (
                  [
                    pkgs.bashInteractive
                    tools
                  ]
                  ++ sandboxTools
                )
              } \
              ${lib.optionalString isDarwin "--set BUBBLEBOX_SEATBELT_PROFILE $out/share/${name}/seatbelt.sbpl"}

            # Wrapped tool exposed inside the sandbox under its plain name on PATH.
            makeWrapper ${tool}/bin/${toolBinary} $out/libexec/${name}/${toolBinary} \
              ${
                lib.concatStringsSep " " (
                  lib.mapAttrsToList (
                    k: v: "--set ${lib.escapeShellArg k} ${lib.escapeShellArg (toString v)}"
                  ) toolEnv
                )
              } \
              --inherit-argv0
          ''
      );
    in
    {
      _module.args.mkBubblebox = mkBubblebox;
    };
}
