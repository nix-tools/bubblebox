# Mirror every flake package (except `default`) onto pkgs, so adding a new
# box in packages.nix is automatically picked up here.
{ inputs, ... }:
{
  # Index self.packages by `prev`'s system, not `final`'s: this overlay's key
  # set is computed dynamically, so forcing `final.stdenv` here would recurse
  # through the very overlay being built. `prev` is the pre-overlay pkgs.
  flake.overlays.default =
    _final: prev:
    builtins.removeAttrs inputs.self.packages.${prev.stdenv.hostPlatform.system} [ "default" ];
}
