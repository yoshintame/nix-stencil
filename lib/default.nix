{ lib }:
let
  holes = import ./holes.nix { inherit lib; };
in
holes
// import ./sops.nix {
  inherit lib;
  inherit (holes) patterns;
}
