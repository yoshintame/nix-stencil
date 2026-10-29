{
  lib,
  stencil,
  context,
  top,
}:
let
  inherit (lib) mkOption types;
  inherit (context) renderedOptions placeholderOf templatePath;
  cfg = top.stencil;

  envModule =
    namespace:
    { config, ... }:
    {
      options = renderedOptions "stencil-env-${namespace}" // {
        enable = lib.mkEnableOption "an env file with every key of the namespace";
        content = mkOption {
          type = types.str;
          readOnly = true;
          internal = true;
          default = stencil.render {
            placeholderOf = placeholderOf namespace;
          } (lib.concatMapStrings (key: "${key}=\${${key}}\n") cfg.namespaces.${namespace}.keys);
        };
        path = mkOption {
          type = types.str;
          readOnly = true;
          default =
            if config.enable then
              templatePath "stencil.namespaces.${namespace}.env.path" config.name
            else
              throw "stencil.namespaces.${namespace}.env.path: env.enable is false";
          defaultText = lib.literalExpression "config.sops.templates.<name>.path";
        };
      };
      config.sopsTemplate = {
        inherit (config) content mode;
      };
    };

  namespaceModule =
    { name, config, ... }:
    let
      scan = stencil.scanSopsFile config.sopsFile;
    in
    {
      options = {
        sopsFile = mkOption {
          type = types.path;
          description = "sops-encrypted YAML file with flat KEY: ENC[...] string entries";
        };
        keys = mkOption {
          type = types.listOf types.str;
          readOnly = true;
          default = scan.keys;
          defaultText = lib.literalExpression "keys of sopsFile";
          description = "Keys of sopsFile, read from the plaintext key names";
        };
        skippedKeys = mkOption {
          type = types.listOf types.attrs;
          readOnly = true;
          internal = true;
          default = scan.skipped;
        };
        env = mkOption {
          type = types.submodule (envModule name);
          default = { };
        };
      };
    };
in
namespaceModule
