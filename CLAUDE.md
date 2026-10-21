# nix-stencil

Library flake: native config templates with secret holes rendered through sops-nix. Consumers: lasthaze-homelab (NixOS module) and dotfiles (home-manager module, not written yet).

- `lib/` holds pure string functions; `modules/common.nix` is flavor-agnostic, `modules/nixos.nix` adds what only NixOS sops-nix has (`owner`, `group`, `restartUnits`).
- Every behavior change comes with a case in `tests/lib.nix` or `tests/nixos.nix`; `just check` must be green before a commit.
- Releases are lightweight tags `vX.Y.Z`; consumers pin them through their flake.lock.
