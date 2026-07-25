{
  perSystem =
    {
      pkgs,
      lib,
      config,
      ...
    }:
    let
      # Expose this flake's own claudebox under a distinct name so it can be
      # tested alongside a system-pinned `claudebox` without shadowing it.
      # bubblebox doesn't ship profiles, but for its own development we define
      # a "gh" profile mounting the config that gh and ssh authenticate against.
      claudebox-dev = config.packages.claudebox.override {
        profiles.gh.mounts = [
          "~/.config/gh"
          "~/.ssh"
        ];
      };
      claudebox-latest = pkgs.writeShellScriptBin "claudebox-latest" ''
        exec ${lib.getExe claudebox-dev} "$@"
      '';
    in
    {
      devShells.default = pkgs.mkShell {
        packages = [
          pkgs.nodejs
          config.treefmt.build.wrapper
          claudebox-latest
        ];
      };
    };
}
