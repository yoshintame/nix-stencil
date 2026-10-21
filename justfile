default:
    @just --list

check:
    nix flake check

fmt:
    nix fmt

update:
    nix flake update
