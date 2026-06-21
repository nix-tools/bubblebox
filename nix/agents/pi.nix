{ inputs, ... }:
{
  perSystem =
    { pkgs, ... }:
    let
      pi-agent = pkgs.buildNpmPackage {
        pname = "pi";
        version = "0.71.0";

        src = inputs.pi-mono;

        nodejs = pkgs.nodejs_22;

        npmDepsHash = "sha256-3W2YMBaUe704Y78Zw13o9dC9lwwHri+4OwFwCpq2drA=";

        NODE_OPTIONS = "--max-old-space-size=4096";

        nativeBuildInputs = with pkgs; [
          python3
          pkg-config
        ];

        buildInputs = with pkgs; [
          cairo
          giflib
          libjpeg
          libpng
          librsvg
          pango
          pixman
          vips
        ];

        # tsgo is stricter in the Nix sandbox than in dev; --noCheck still emits JS.
        preBuild = ''
          for f in packages/*/package.json; do
            sed -i 's/tsgo -p/tsgo --noCheck -p/g' "$f"
          done
        '';

        npmBuildScript = "build";

        # npmInstallHook reinstalls with --omit=dev, dropping build artifacts; save and restore them.
        preInstall = ''
          for pkg in tui ai agent coding-agent mom web-ui pods; do
            if [ -d "packages/$pkg/dist" ]; then
              cp -r "packages/$pkg/dist" "packages/$pkg/dist-save"
            fi
          done
        '';

        postInstall = ''
          local libdir="$out/lib/node_modules/pi-monorepo"

          for pkg in tui ai agent coding-agent mom web-ui pods; do
            if [ -d "packages/$pkg/dist-save" ]; then
              cp -r "packages/$pkg/dist-save" "$libdir/packages/$pkg/dist"
            fi
          done

          for pkg in tui ai agent coding-agent mom web-ui pods; do
            rm -rf "$libdir/packages/$pkg/dist-save"
          done

          rm -f "$out/bin/pi"
          mkdir -p "$out/bin"
          ln -s "$libdir/packages/coding-agent/dist/cli.js" "$out/bin/pi"
        '';

        meta = with pkgs.lib; {
          description = "Coding agent CLI with read, bash, edit, write tools and session management";
          homepage = "https://github.com/badlogic/pi-mono";
          license = licenses.mit;
          mainProgram = "pi";
        };
      };
    in
    {
      boxes.pibox = {
        tool = pi-agent;
        toolBinary = "pi";
        homeBindings = [ ".pi" ];
        description = "Sandboxed environment for Pi agent";
        homepage = "https://github.com/badlogic/pi-mono";
      };
    };
}
