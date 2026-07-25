{ flake-parts-lib, ... }:
{
  options.perSystem = flake-parts-lib.mkPerSystemOption (
    { lib, ... }:
    {
      options.boxes = lib.mkOption {
        type = lib.types.lazyAttrsOf lib.types.raw;
        default = { };
        description = "Box specs keyed by name; each value is an argument set for mkBubblebox.";
      };
    }
  );

  config.perSystem =
    {
      config,
      pkgs,
      lib,
      mkBubblebox,
      ...
    }:
    let
      mkApp = pkg: {
        type = "app";
        program = "${pkg}/bin/${pkg.meta.mainProgram}";
        meta = pkg.meta;
      };
      packages = lib.mapAttrs (name: spec: mkBubblebox (spec // { inherit name; })) config.boxes;
    in
    {
      boxes = {
        claudebox = {
          tool = pkgs.claude-code;
          toolBinary = "claude";
          homeBindings = [
            ".claude"
            ".claude.json"
          ];
          defaultArgs = [ "--dangerously-skip-permissions" ];
          toolEnv = {
            DISABLE_AUTOUPDATER = "1";
          };
          # Extension point: add mounts here via pkgs.claudebox.override to have
          # them active without --profile.
          profiles.default.mounts = [ ];
          description = "Sandboxed environment for Claude Code";
        };

        codexbox = {
          tool = pkgs.codex;
          toolBinary = "codex";
          homeBindings = [ ".codex" ];
          description = "Sandboxed environment for OpenAI Codex CLI";
        };

        opencodebox = {
          tool = pkgs.opencode;
          toolBinary = "opencode";
          homeBindings = [
            ".local/share/opencode"
            ".config/opencode"
          ];
          description = "Sandboxed environment for opencode";
        };
      };

      inherit packages;
      apps = lib.mapAttrs (_name: mkApp) packages;
    };
}
