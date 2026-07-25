{ inputs, ... }:
{
  perSystem =
    { system, ... }:
    {
      boxes.pibox = {
        tool =
          inputs.llm-agents.packages.${system}.pi or (throw "llm-agents has no pi package for ${system}");
        toolBinary = "pi";
        homeBindings = [ ".pi" ];
        description = "Sandboxed environment for Pi agent";
        homepage = "https://github.com/earendil-works/pi";
      };
    };
}
