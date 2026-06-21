{ inputs, ... }:
{
  perSystem =
    { system, ... }:
    {
      boxes.hermesbox = {
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
}
