# Confirms that boxes living behind the "agents" flake-parts partition
# (hermesbox, pibox) still reach a downstream consumer through the overlay.
#
# `packages`/`apps` are partitioned (see partitions.nix), but `overlays.default`
# is not — it re-exports `inputs.self.packages`. The open question was whether a
# consumer who only applies overlays.default gets `pkgs.pibox`, or whether the
# partition keeps it out of self.packages. This applies the overlay to a fresh
# nixpkgs exactly as a consumer would and asserts each partitioned box arrives
# as a real derivation. If it does, `pkgs.pibox` needs no extra input wiring;
# if partitioning dropped it, the check throws with the missing name.
#
# The check forces evaluation (instantiation) of the boxes, not their build:
# only their names are referenced by the runCommand, so the heavy agent inputs
# resolve but nothing is compiled.
{ inputs, ... }:
{
  perSystem =
    {
      pkgs,
      lib,
      system,
      ...
    }:
    {
      checks.partitioned-boxes-via-overlay =
        let
          overlaid = import inputs.nixpkgs {
            inherit system;
            overlays = [ inputs.self.overlays.default ];
          };
          confirm =
            name:
            if !(overlaid ? ${name}) then
              throw "overlay is missing partitioned box '${name}'; consumer needs extra wiring"
            else if !(lib.isDerivation overlaid.${name}) then
              throw "overlay attribute '${name}' did not resolve to a derivation"
            else
              name;
          boxes = map confirm [
            "hermesbox"
            "pibox"
          ];
        in
        pkgs.runCommand "partitioned-boxes-via-overlay" { } ''
          echo "overlay surfaces partitioned boxes: ${toString boxes}" > $out
        '';
    };
}
