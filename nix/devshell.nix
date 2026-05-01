{
  perSystem =
    { pkgs, config, ... }:
    {
      devShells.default = pkgs.mkShell {
        packages = [
          pkgs.nodejs
          config.treefmt.build.wrapper
        ];
      };
    };
}
