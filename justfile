system := `nix eval --impure --raw --expr builtins.currentSystem`

# List available just commands
list:
    @just --list --unsorted

# Run the mount tests (also covered by `nix flake check`).
test:
    nix build --no-link --print-build-logs '.#checks.{{ system }}.mounts'

# Run CI checks locally.
ci: test

# Update both the root flake lock and the agents partition flake lock.
update:
    nix flake update
    nix flake update --flake ./nix/agents/_inputs
