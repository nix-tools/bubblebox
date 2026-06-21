# List available just commands
list:
    @just --list --unsorted

# Update both the root flake lock and the agents partition flake lock.
update:
    nix flake update
    nix flake update --flake ./nix/agents/_inputs
