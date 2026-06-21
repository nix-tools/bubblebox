{ inputs, ... }:
{
  imports = [ inputs.flake-parts.flakeModules.partitions ];

  partitionedAttrs = {
    packages = "agents";
    apps = "agents";
  };

  partitions.agents.extraInputsFlake = ./agents/_inputs;
}
