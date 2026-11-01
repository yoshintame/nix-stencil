# nix-stencil

Render native config files with secret holes through [sops-nix](https://github.com/Mic92/sops-nix).

A stencil is the config file of an application as it is, with `~{{key}}` holes where secrets go. nix-stencil replaces the holes with sops-nix placeholders at evaluation, and sops-nix writes the real values at activation. No secret enters the Nix store, and no renderer of its own runs on the machine.

## Holes

| Hole | Becomes |
|---|---|
| `~{{key}}` | secret `key` of the file's namespace |
| `~{{ns/key}}` | secret `key` of namespace `ns` |
| `~~{{key}}` | literal `~{{key}}` |
| `@var@` | Nix value from `vars`, substituted at evaluation |

A key is any name of the sops file, written as is: `~{{API_TOKEN}}`, `~{{infra/restic-b2-key-id}}`. The part before the first `/` is the namespace. A hole stays on one line and has no `{` or `}` inside; spaces belong to the key, so `~{{ key }}` names ` key `. `~{{a}b}}`, `${KEY}`, `~{KEY}` and `~{{}}` stay as is, and a key with a brace is reachable only through `refs`.

`~{{` is taken by no common config format: `${…}` belongs to shell, JS templates, compose and terraform, `{{…}}` to Go templates and Jinja, `%{…}` to grok and Apache, `#{…}` starts a comment, and `%`, `!`, `&` and `*` are indicators at the start of a YAML value. Secret scanners read a value with `{{` in it as a placeholder, so `PASSWORD=~{{key}}` needs no allowlist in betterleaks. Secrets and `vars` keep separate sigils, so a review sees what reaches the Nix store: a `vars` value is in the store, a secret only in the rendered file.

Holes are found in the template as written: a `vars` value is literal text and never becomes a hole. A `@var@` without a value in `vars` stays as is, so a config may keep literal `@name@` text.

Values are inserted verbatim: there is no escaping for the target format. A secret that may contain quotes or backslashes belongs in a file of its own, read by path (`stencil.refs`).

## Namespaces

A namespace is a sops-encrypted YAML file with flat string keys:

```yaml
RD_API_KEY: ENC[AES256_GCM,...]
grafana-admin-password: ENC[AES256_GCM,...]
```

Key names in a sops file are plaintext, so nix-stencil reads them at evaluation. Each top-level string key becomes the sops-nix secret `<namespace>/<key>`, and a hole that names a missing key fails `nix flake check` instead of the activation. Three kinds of keys are skipped with a warning: a non-string value (`type:int`, `type:bool`), since sops-nix cannot install it as a secret, a key with `/`, which sops-nix reads as a path into nested maps, and a quoted key such as `"123"`, which sops writes for a name that YAML would read as a number or a boolean.

A namespace name matches `[a-z0-9-]+`, the namespace part of a `~{{ns/key}}` hole.

A file may declare its namespace itself: `sopsFile = ./secrets.yaml` registers the sops file as the namespace `namespace`, which defaults to the name of the directory of the sops file (`modules/rclone/secrets.yaml` is `rclone`). Files and `stencil.namespaces` naming one namespace with one sops file share it; two sops files under one namespace name fail evaluation, and the fix is an explicit `namespace`. Since `stencil.namespaces` is built from `stencil.files`, a `stencil.files` computed from `stencil.namespaces` is an infinite recursion.

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

### home-manager

```nix
{
  # in a home-manager configuration, next to sops-nix.homeManagerModules.sops
  imports = [ inputs.nix-stencil.homeManagerModules.default ];
}
```

```nix
{ config, lib, ... }:
{
  stencil.files."~/.config/resticprofile/profiles.yaml" = {
    sopsFile = ./secrets.yaml;
    template = ./config/profiles.yaml;
    vars.endpoint = "http://monitor:8080";
  };

  stencil.namespaces.rclone.sopsFile = ./rclone.yaml;

  programs.rclone.remotes.gdrive.secrets = lib.mkIf config.stencil.enable {
    token = config.stencil.refs.rclone.RCLONE_GDRIVE_TOKEN;
  };
}
```

The id of a file is its `target`, where the file is placed: `~/` and relative paths start at the home directory, and a target outside the home directory fails evaluation. A rendered file is a symlink sops-nix keeps at the target and replaces whatever was there; a store file is linked by `home.file` with `force`, so a file that loses its last secret hole takes over the symlink sops-nix left. Two files with one target, or a rendered file at a `home.file` target, fail evaluation. `target = null` keeps a rendered file in the sops-nix rendered directory and does not place a store file anywhere.

`stencil.enable = false` declares no secrets and no templates, for example on the first switch of a machine without its age key; `path` and `refs` throw then, and the checks still run. The policy stays with the host. A check of the key file reads the disk of the evaluating machine and needs `--impure`: in pure evaluation `builtins.pathExists` of a path outside the store is always false.

```nix
stencil.enable = builtins.pathExists config.sops.age.keyFile;
```

## Options

| Option | Meaning |
|---|---|
| `stencil.enable` | declare the secrets and templates in sops-nix (default `true`) |
| `stencil.namespaces.<ns>.sopsFile` | sops YAML file of the namespace |
| `stencil.namespaces.<ns>.keys` | keys found in the file (read-only) |
| `stencil.namespaces.<ns>.env.{enable,name,mode,owner,group,restartUnits}` | env file with every key of the namespace that is a variable name |
| `stencil.namespaces.<ns>.env.path` | path of the env file (read-only) |
| `stencil.files.<id>.{namespace,sopsFile,template,vars,name,mode,owner,group,restartUnits,target}` | file rendered from a template |
| `stencil.files.<id>.path` | rendered file (read-only): a sops-nix template with secret holes, a store path without |
| `stencil.refs.<ns>.<key>` | path of a single secret (read-only) |

`target` exists in the home-manager module, on files (default: the id) and on env files (default: `null`). `owner`, `group` and `restartUnits` exist in the NixOS module; a `null` group keeps the sops-nix default, the group of the owner. A rendered file follows sops-nix: it is rewritten at activation and on secret rotation. A consumer that needs a writable copy, for example an application that rewrites its config on exit, copies `path` before start.

An env file holds the keys that are variable names, `patterns.envKey` (`[A-Za-z_][A-Za-z0-9_]*`); with `env.enable`, the other keys of the namespace give a warning and stay reachable through holes and `refs`.

A file without secret holes is a store file: `mode`, `owner`, `group` and `restartUnits` do not apply to it, and setting them gives a warning.

`name` is the file name under the sops-nix rendered directory, `/run/secrets/rendered/<name>` on NixOS and `~/.config/sops-nix/secrets/rendered/<name>` in home-manager. It defaults to `stencil-env-<ns>` for env files and to `stencil-file-<id>` for files, with `%` and `/` of the id percent-encoded, so `app/config.json` becomes `stencil-file-app%2Fconfig.json`. Two rendered files with one name fail evaluation.

`lib` exposes the pure parts: `render`, `holesOf`, `holeRef`, `parseRef`, `formatRef`, `scanSopsFile`, `secretName`, `isNamespace` and `patterns`.

## Upgrading from v0.3

v0.4 replaces the holes: `${KEY}` is `~{{KEY}}` and `${ns.KEY}` is `~{{ns/KEY}}`. `${…}` is no longer a hole, so the escape `$${KEY}` becomes plain `${KEY}`. One substitution rewrites a template, and the rendered output stays the same:

```sh
perl -pi -e 's/(\$?)\$\{(?:([a-z0-9-]+)\.)?([A-Z_][A-Z0-9_]*)\}/$1 ? "\${" . ($2 ? "$2." : "") . "$3}" : "~{{" . ($2 ? "$2\/" : "") . "$3}}"/ge' <templates>
```

A literal `~{{` in a v0.3 template becomes a hole in v0.4 and needs `~~{{`. A literal `~` right before a v0.3 hole, as in `~${TOKEN}`, turns into the escape `~~{{TOKEN}}`; v0.4 writes that `~` through a var: `@tilde@~{{TOKEN}}` with `vars.tilde = "~"`.

## Development

```sh
just check   # nix flake check: formatting, lib unit tests, NixOS and home-manager module eval tests
just fmt
```
