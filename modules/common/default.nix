{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib) mkOption types;
  stencil = import ../../lib { inherit lib; };
  context = import ./context.nix { inherit config lib stencil; };
  inherit (context) rendered secretPath;
  cfg = config.stencil;
  namespaceModule = import ./namespace.nix {
    inherit lib stencil context;
    top = config;
  };
  fileModule = import ./file.nix {
    inherit
      lib
      pkgs
      stencil
      context
      ;
  };
in
{
  imports = [ ./checks.nix ];

  options.stencil = {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = "Declare the secrets and templates in sops-nix; off, paths and refs throw and the checks still run";
    };
    namespaces = mkOption {
      type = types.attrsOf (types.submodule namespaceModule);
      default = { };
      description = "sops files whose keys become secrets named <namespace>/<KEY>";
    };
    files = mkOption {
      type = types.attrsOf (types.submodule fileModule);
      default = { };
      description = "Files rendered from native templates";
    };
    refs = mkOption {
      type = types.attrsOf (types.lazyAttrsOf types.str);
      readOnly = true;
      default = lib.mapAttrs (
        namespace: n:
        lib.genAttrs n.keys (
          key: secretPath "stencil.refs.${namespace}.${key}" (stencil.secretName namespace key)
        )
      ) cfg.namespaces;
      defaultText = lib.literalExpression "refs.<namespace>.<KEY> = path of the secret";
      description = "Path of every secret: refs.<namespace>.<KEY>";
    };
  };

  config = lib.mkMerge [
    {
      stencil.namespaces = lib.mkMerge (
        lib.mapAttrsToList (_: f: { ${f.namespace}.sopsFile = f.sopsFile; }) (
          lib.filterAttrs (_: f: f.sopsFile != null) cfg.files
        )
      );
    }
    (lib.mkIf cfg.enable {
      sops.secrets = lib.mkMerge (
        lib.mapAttrsToList (
          namespace: n:
          lib.listToAttrs (
            map (
              key:
              lib.nameValuePair (stencil.secretName namespace key) {
                inherit (n) sopsFile;
                inherit key;
                format = "yaml";
              }
            ) n.keys
          )
        ) cfg.namespaces
      );

      sops.templates = lib.listToAttrs (map (r: lib.nameValuePair r.name r.sopsTemplate) rendered);
    })
  ];
}
