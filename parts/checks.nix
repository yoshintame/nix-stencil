{ inputs, lib, ... }:
let
  stencil = import ../lib { inherit lib; };
  report =
    area: failed:
    throw "nix-stencil ${area} tests failed:\n${
      lib.concatMapStringsSep "\n" (
        c:
        "- ${c.name}\n    expected: ${builtins.toJSON c.expected}\n    actual:   ${builtins.toJSON c.result}"
      ) failed
    }";
  suite =
    pkgs: area: failed:
    if failed == [ ] then
      pkgs.runCommandLocal "nix-stencil-${area}-tests" { } "touch $out"
    else
      report area failed;
in
{
  perSystem =
    { pkgs, ... }:
    {
      checks.lib = suite pkgs "lib" (import ../tests/lib.nix { inherit lib stencil; });
      checks.nixos = suite pkgs "nixos" (
        import ../tests/nixos.nix {
          inherit lib inputs;
          nixosModule = ../modules/nixos.nix;
        }
      );
      checks.home-manager = suite pkgs "home-manager" (
        import ../tests/home-manager.nix {
          inherit lib inputs;
          homeManagerModule = ../modules/home-manager.nix;
        }
      );
    };
}
