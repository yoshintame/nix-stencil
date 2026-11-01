{ lib }:
import ./holes.nix { inherit lib; } // import ./sops.nix { inherit lib; }
