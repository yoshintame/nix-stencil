# nix-stencil

Library flake: native config templates with secret holes rendered through sops-nix. Consumers: lasthaze-homelab (NixOS module) and dotfiles (home-manager module).

- `lib/holes.nix` is the hole grammar and rendering, `lib/sops.nix` the only part that knows the sops file format.
- `modules/common/` is flavor-agnostic: `context.nix` resolves holes and lists the rendered files, `namespace.nix` and `file.nix` are the submodules, `checks.nix` the assertions and warnings. `modules/nixos.nix` adds what only NixOS sops-nix has (`owner`, `group`, `restartUnits`), `modules/home-manager.nix` the `target` of a file.
- Every behavior change comes with a case in `tests/lib.nix`, `tests/nixos.nix` or `tests/home-manager.nix`; `just check` must be green before a commit.
- Releases are lightweight tags `vX.Y.Z`; consumers pin them through their flake.lock.
