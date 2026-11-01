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

  isEnvKey = key: builtins.match stencil.patterns.envKey key != null;

  envModule =
    namespace:
    { config, ... }:
    let
      envKeys = lib.partition isEnvKey cfg.namespaces.${namespace}.keys;
    in
    {
      options = renderedOptions "stencil-env-${namespace}" // {
        enable = lib.mkEnableOption "an env file with every key of the namespace that is a variable name";
        content = mkOption {
          type = types.str;
          readOnly = true;
          internal = true;
          default = lib.concatMapStrings (
            key: "${key}=${placeholderOf namespace { inherit namespace key; }}\n"
          ) envKeys.right;
        };
        excludedKeys = mkOption {
          type = types.listOf types.str;
          readOnly = true;
          internal = true;
          default = envKeys.wrong;
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
          description = "sops-encrypted YAML file with flat key: ENC[...] string entries";
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
