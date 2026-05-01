# Generic builder for "<tool>box" — wraps a CLI in a bwrap/seatbelt sandbox.
#
# Each box is a thin makeWrapper around node + a launcher script (bubblebox.js)
# parameterized by a JSON config that names the tool, its binary, the home
# paths to bind through, default args, and any env to set.
#
# Exposed as `mkBubblebox` (perSystem _module.arg) so packages.nix can call:
#
#   mkBubblebox { name = "claudebox"; tool = pkgs.claude-code; ... }
{
  perSystem =
    { pkgs, lib, ... }:
    let
      mkBubblebox =
        {
          # Name of the produced wrapper, e.g. "claudebox".
          name,
          # The CLI derivation being wrapped, e.g. pkgs.claude-code.
          tool,
          # Binary inside `tool` to invoke; defaults to its meta.mainProgram.
          toolBinary ? tool.meta.mainProgram or name,
          # Paths under $HOME to bind through into the sandbox, e.g.
          # [ ".claude" ".claude.json" ]. Created on the host if missing.
          homeBindings ? [ ],
          # Args always passed to the wrapped tool (before any user args).
          defaultArgs ? [ ],
          # Extra env vars set on the wrapped tool (inside the sandbox).
          toolEnv ? { },
          description ? "Sandboxed environment for ${name}",
          homepage ? "https://github.com/sshine/bubblebox",
          # Launcher source dir; overridable for vendoring.
          sourceDir ? ../src,
        }:
        let
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
            inherit name homeBindings defaultArgs;
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
          '';
    in
    {
      _module.args.mkBubblebox = mkBubblebox;
    };
}
