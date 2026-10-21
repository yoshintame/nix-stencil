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
  inherit (context) rendered;
  cfg = config.stencil;
  args = {
    inherit lib stencil context;
    top = config;
  };
  namespaceModule = import ./namespace.nix args;
  fileModule = import ./file.nix (args // { inherit pkgs; });
in
{
  imports = [ ./checks.nix ];

  options.stencil = {
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
      type = types.attrsOf (types.attrsOf types.str);
      readOnly = true;
      default = lib.mapAttrs (
        namespace: n:
        lib.genAttrs n.keys (key: config.sops.secrets.${stencil.secretName namespace key}.path)
      ) cfg.namespaces;
      defaultText = lib.literalExpression "refs.<namespace>.<KEY> = path of the secret";
      description = "Path of every secret: refs.<namespace>.<KEY>";
    };
  };

  config = {
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
  };
}
