# Builds the Pi agent CLI from github:badlogic/pi-mono and exposes it as a
# per-system module argument (`pi-agent`), so packages.nix can wrap it
# without falling back to `import` — which import-tree would mis-treat as
# a flake-parts module.
{ inputs, ... }:
{
  perSystem =
    { pkgs, ... }:
    {
      _module.args.pi-agent = pkgs.buildNpmPackage {
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

        # tsgo in the Nix sandbox produces stricter type errors than in the
        # dev environment. Use --noCheck to skip type-checking while still
        # emitting JS.
        preBuild = ''
          for f in packages/*/package.json; do
            sed -i 's/tsgo -p/tsgo --noCheck -p/g' "$f"
          done
        '';

        npmBuildScript = "build";

        # npmInstallHook re-runs npm install with --omit=dev, which drops
        # workspace build artifacts. Save them before install, restore after.
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
    };
}
