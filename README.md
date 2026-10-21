# nix-stencil

Render native config files with secret holes through [sops-nix](https://github.com/Mic92/sops-nix).

A stencil is the config file of an application as it is, with `${KEY}` holes where secrets go. nix-stencil replaces the holes with sops-nix placeholders at evaluation, and sops-nix writes the real values at activation. No secret enters the Nix store, and no renderer of its own runs on the machine.

## Holes

| Hole | Becomes |
|---|---|
| `${KEY}` | secret `KEY` of the file's namespace |
| `${ns.KEY}` | secret `KEY` of namespace `ns` |
| `$${KEY}` | literal `${KEY}` |
| `@var@` | Nix value from `vars`, substituted at evaluation |

`KEY` is `[A-Z_][A-Z0-9_]*`, a namespace is `[a-z0-9-]+`. Anything else, such as `$KEY` or `${lower}`, stays as is.

Values are inserted verbatim: there is no escaping for the target format. A secret that may contain quotes or backslashes belongs in a file of its own, read by path (`stencil.refs`).

## Namespaces

A namespace is a sops-encrypted YAML file with flat keys:

```yaml
RD_API_KEY: ENC[AES256_GCM,...]
API_TOKEN: ENC[AES256_GCM,...]
```

Key names in a sops file are plaintext, so nix-stencil reads them at evaluation. Each key becomes the sops-nix secret `<namespace>/<KEY>`, and a hole that names a missing key fails `nix flake check` instead of the activation.

## Usage

```nix
{
  inputs.nix-stencil.url = "github:yoshintame/nix-stencil";

  # in a NixOS configuration, next to sops-nix.nixosModules.sops
  imports = [ inputs.nix-stencil.nixosModules.default ];
}
```

```nix
{ config, ... }:
{
  stencil.namespaces.decypharr = {
    sopsFile = ./secrets.yaml;
    env = {
      enable = true;
      restartUnits = [ "podman-decypharr.service" ];
    };
  };

  stencil.files."decypharr/config.json" = {
    namespace = "decypharr";
    template = ./config/config.json;
    vars.downloadFolder = "/srv/media";
    restartUnits = [ "podman-decypharr.service" ];
  };

  virtualisation.oci-containers.containers.decypharr = {
    environmentFiles = [ config.stencil.namespaces.decypharr.env.path ];
    volumes = [ "${config.stencil.files."decypharr/config.json".path}:/app/config.json:ro" ];
  };

  services.foo.passwordFile = config.stencil.refs.decypharr.API_TOKEN;
}
```

## Options

| Option | Meaning |
|---|---|
| `stencil.namespaces.<ns>.sopsFile` | sops YAML file of the namespace |
| `stencil.namespaces.<ns>.keys` | keys found in the file (read-only) |
| `stencil.namespaces.<ns>.env.{enable,mode,owner,group,restartUnits}` | env file with every key of the namespace |
| `stencil.namespaces.<ns>.env.path` | path of the env file (read-only) |
| `stencil.files.<id>.{namespace,template,vars,mode,owner,group,restartUnits}` | file rendered from a template |
| `stencil.files.<id>.path` | rendered file (read-only): `/run/secrets/rendered/stencil-<id>` with secret holes, a store path without |
| `stencil.refs.<ns>.<KEY>` | path of a single secret (read-only) |

`owner`, `group` and `restartUnits` exist in the NixOS module. A rendered file follows sops-nix: it is rewritten at activation and on secret rotation. A consumer that needs a writable copy, for example an application that rewrites its config on exit, copies `path` before start.

`lib` exposes the pure parts: `holesOf`, `fillHoles`, `fillVars`, `secretKeys`, `secretName`, `templateName`.

## Development

```sh
just check   # nix flake check: formatting, lib unit tests, NixOS module eval tests
just fmt
```
