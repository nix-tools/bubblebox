{ inputs, ... }:
{
  perSystem =
    {
      pkgs,
      system,
      lib,
      mkBubblebox,
      ...
    }:
    let
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
          description = "Sandboxed environment for Claude Code";
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

        hermesbox = {
          tool =
            inputs.hermes-agent.packages.${system}.default
              or (throw "hermes-agent has no package for ${system}");
          toolBinary = "hermes";
          homeBindings = [
            ".hermes"
            ".config/hermes"
          ];
          description = "Sandboxed environment for Hermes Agent";
          homepage = "https://github.com/NousResearch/hermes-agent";
        };
      };

      mkApp = pkg: {
        type = "app";
        program = "${pkg}/bin/${pkg.meta.mainProgram}";
        meta = pkg.meta;
      };
    in
    rec {
      packages = lib.mapAttrs (name: spec: mkBubblebox (spec // { inherit name; })) boxes;
      apps = (lib.mapAttrs (_name: mkApp) packages);
    };
}
