{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib) mkOption types;
  stencil = import ../lib { inherit lib; };
  top = config;
  cfg = config.stencil;

  known = ns: key: ns != null && cfg.namespaces ? ${ns} && lib.elem key cfg.namespaces.${ns}.keys;
  placeholderOf =
    ns: key:
    if known ns key then
      config.sops.placeholder.${stencil.secretName ns key}
    else
      "<stencil:missing:${toString ns}.${key}>";
  inherit (stencil) templateName;
  envName = stencil.envTemplateName;

  namespaceModule =
    { name, config, ... }:
    {
      options = {
        sopsFile = mkOption {
          type = types.path;
          description = "sops-encrypted YAML file with flat KEY: ENC[...] entries";
        };
        keys = mkOption {
          type = types.listOf types.str;
          readOnly = true;
          default = stencil.secretKeys config.sopsFile;
          description = "Keys found in sopsFile, read from the plaintext key names";
        };
        env = {
          enable = lib.mkEnableOption "an env file with every key of the namespace";
          mode = mkOption {
            type = types.str;
            default = "0400";
          };
          path = mkOption {
            type = types.str;
            readOnly = true;
            default = top.sops.templates.${envName name}.path;
          };
        };
      };
    };

  fileModule =
    { name, config, ... }:
    {
      options = {
        namespace = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "Namespace of the bare \${KEY} holes";
        };
        template = mkOption {
          type = types.path;
          description = "Native config file with \${KEY}, \${namespace.KEY}, $\${LITERAL} and @var@ holes";
        };
        vars = mkOption {
          type = types.attrsOf types.str;
          default = { };
          description = "Values for the @var@ holes, substituted at evaluation";
        };
        mode = mkOption {
          type = types.str;
          default = "0400";
        };
        text = mkOption {
          type = types.str;
          readOnly = true;
          internal = true;
          default = stencil.fillVars config.vars (builtins.readFile config.template);
        };
        secret = mkOption {
          type = types.bool;
          readOnly = true;
          internal = true;
          default = stencil.hasHoles config.text;
        };
        path = mkOption {
          type = types.str;
          readOnly = true;
          default =
            if config.secret then
              top.sops.templates.${templateName name}.path
            else
              "${pkgs.writeText (baseNameOf name) config.text}";
          description = "Rendered file: a sops-nix template with secret holes, a store file without";
        };
      };
    };

  secretFiles = lib.filterAttrs (_: f: f.secret) cfg.files;

  fileAssertions =
    id: f:
    let
      at = "stencil.files.\"${id}\"";
      holes = stencil.holesOf f.text;
      nsOf = h: if h.namespace == null then f.namespace else h.namespace;
      ref = h: "\${${lib.optionalString (h.namespace != null) "${h.namespace}."}${h.key}}";
      bare = lib.filter (h: h.namespace == null) holes;
      unknownNs = lib.unique (
        lib.filter (ns: ns != null && !(cfg.namespaces ? ${ns})) (map nsOf holes ++ [ f.namespace ])
      );
      missing = lib.filter (
        h: nsOf h != null && cfg.namespaces ? ${nsOf h} && !known (nsOf h) h.key
      ) holes;
      text = builtins.readFile f.template;
      unusedVars = lib.filter (v: !lib.hasInfix "@${v}@" text) (lib.attrNames f.vars);
    in
    [
      {
        assertion = f.namespace != null || bare == [ ];
        message = "${at}: holes ${
          lib.concatMapStringsSep ", " ref bare
        } have no namespace; set ${at}.namespace";
      }
      {
        assertion = unknownNs == [ ];
        message = "${at}: namespaces ${lib.concatStringsSep ", " unknownNs} are not declared in stencil.namespaces";
      }
      {
        assertion = missing == [ ];
        message = "${at}: ${
          lib.concatMapStringsSep "; " (
            h:
            "${ref h} is absent from ${toString cfg.namespaces.${nsOf h}.sopsFile} (${
              lib.concatStringsSep ", " cfg.namespaces.${nsOf h}.keys
            })"
          ) missing
        }";
      }
      {
        assertion = unusedVars == [ ];
        message = "${at}: vars ${lib.concatStringsSep ", " unusedVars} do not occur in the template as @var@";
      }
    ];
in
{
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
        ns: n: lib.genAttrs n.keys (key: config.sops.secrets.${stencil.secretName ns key}.path)
      ) cfg.namespaces;
      description = "Path of every secret: refs.<namespace>.<KEY>";
    };
  };

  config = {
    sops.secrets = lib.mkMerge (
      lib.mapAttrsToList (
        ns: n:
        lib.listToAttrs (
          map (
            key:
            lib.nameValuePair (stencil.secretName ns key) {
              inherit (n) sopsFile;
              inherit key;
            }
          ) n.keys
        )
      ) cfg.namespaces
    );

    sops.templates =
      lib.mapAttrs' (
        ns: n:
        lib.nameValuePair (envName ns) {
          content = stencil.envLines placeholderOf ns n.keys;
          inherit (n.env) mode;
        }
      ) (lib.filterAttrs (_: n: n.env.enable) cfg.namespaces)
      // lib.mapAttrs' (
        id: f:
        lib.nameValuePair (templateName id) {
          content = stencil.fillHoles {
            inherit (f) namespace;
            inherit placeholderOf;
          } f.text;
          inherit (f) mode;
        }
      ) secretFiles;

    assertions =
      lib.mapAttrsToList (ns: n: {
        assertion = n.keys != [ ];
        message = "stencil.namespaces.${ns}: ${toString n.sopsFile} has no top-level KEY: ENC[...] entries";
      }) cfg.namespaces
      ++ lib.concatLists (lib.mapAttrsToList fileAssertions cfg.files);
  };
}
