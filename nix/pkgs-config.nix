# Imports nixpkgs with allowUnfree (claude-code) for use inside the flake.
# The flake's own overlay is *not* applied here — that overlay is derived
# from `inputs.self.packages.<system>`, which would create a cycle.
{ inputs, ... }:
{
  perSystem =
    { system, ... }:
    {
      _module.args.pkgs = import inputs.nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };
    };
}
