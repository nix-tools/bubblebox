# Mirror every flake package (except `default`) onto pkgs, so adding a new
# box in packages.nix is automatically picked up here.
{ inputs, ... }:
{
  flake.overlays.default =
    final: _prev:
    builtins.removeAttrs inputs.self.packages.${final.stdenv.hostPlatform.system} [ "default" ];
}
