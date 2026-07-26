# Mount tests. The testbox is built here and referenced only by the check, so
# it never becomes a flake output. Linux-only: the tests drive bwrap directly.
{
  perSystem =
    {
      pkgs,
      lib,
      mkBubblebox,
      ...
    }:
    {
      # Linux-only: the tests drive bwrap directly. mkIf (not a plain
      # conditional) keeps the module from forcing `pkgs` during merge.
      checks.mounts = lib.mkIf pkgs.stdenv.isLinux (
        let
          # A box wrapping bash so the end-to-end test can run assertions
          # inside the sandbox via `testbox -- -c '<script>'`. Its profiles
          # exercise read-only/read-write mounts, ~ expansion, and each
          # parentMounts mode; paths resolve relative to the test's cwd.
          testbox = mkBubblebox {
            name = "testbox";
            tool = pkgs.bash;
            toolBinary = "bash";
            profiles = {
              default.mounts = [ "d/default" ];
              ro.mounts = [ "d/roA" ];
              rw.mounts = [
                {
                  path = "d/rwA";
                  mode = "rw";
                }
              ];
              tilde.mounts = [ "~/tthome" ];
              parent.parentMounts = "parent";
              tree.parentMounts = "tree";
              e2e.mounts = [
                "d/roA"
                {
                  path = "d/rwA";
                  mode = "rw";
                }
              ];
            };
          };
        in
        pkgs.runCommand "bubblebox-mounts-test"
          {
            nativeBuildInputs = [
              pkgs.nodejs
              pkgs.bubblewrap
              pkgs.openssh # the /etc/ssh test drives the real `ssh -G`
            ];
            BUBBLEBOX_TESTBOX = lib.getExe testbox;
          }
          ''
            export HOME="$(mktemp -d)"
            node --test ${../tests/mounts.test.js}
            touch $out
          ''
      );
    };
}
