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

  resolve =
    defaultNamespace: hole:
    let
      namespace = if hole.namespace == null then defaultNamespace else hole.namespace;
    in
    if namespace == null then
      { status = "no namespace; set the namespace of the file"; }
    else if !(cfg.namespaces ? ${namespace}) then
      { status = "namespace ${namespace} is not declared in stencil.namespaces"; }
    else if !lib.elem hole.key cfg.namespaces.${namespace}.keys then
      {
        status = "absent from ${toString cfg.namespaces.${namespace}.sopsFile} (${
          lib.concatStringsSep ", " cfg.namespaces.${namespace}.keys
        })";
      }
    else
      {
        status = "ok";
        secret = stencil.secretName namespace hole.key;
      };

  placeholderOf =
    defaultNamespace: hole:
    let
      r = resolve defaultNamespace hole;
    in
    if r.status == "ok" then
      config.sops.placeholder.${r.secret}
    else
      "<stencil:unresolved:${stencil.holeRef hole}>";

  encode = builtins.replaceStrings [ "%" "/" ] [ "%25" "%2F" ];

  renderedOptions = defaultName: {
    name = mkOption {
      type = types.strMatching "[^/]+";
      default = defaultName;
      description = "File name under the sops-nix rendered directory";
    };
    mode = mkOption {
      type = types.str;
      default = "0400";
    };
    sopsTemplate = mkOption {
      type = types.lazyAttrsOf types.anything;
      internal = true;
      default = { };
    };
  };

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
              top.sops.templates.${config.name}.path
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

  fileModule =
    { name, config, ... }:
    {
      options = renderedOptions "stencil-file-${encode name}" // {
        namespace = mkOption {
          type = types.nullOr (types.strMatching stencil.patterns.namespace);
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
          description = "Literal values for the @var@ holes, substituted at evaluation";
        };
        raw = mkOption {
          type = types.str;
          readOnly = true;
          internal = true;
          default = builtins.readFile config.template;
        };
        hasHoles = mkOption {
          type = types.bool;
          readOnly = true;
          internal = true;
          default = stencil.holesOf config.raw != [ ];
        };
        content = mkOption {
          type = types.str;
          readOnly = true;
          internal = true;
          default = stencil.render {
            inherit (config) vars;
            placeholderOf = placeholderOf config.namespace;
          } config.raw;
        };
        path = mkOption {
          type = types.str;
          readOnly = true;
          default =
            if config.hasHoles then
              top.sops.templates.${config.name}.path
            else
              "${pkgs.writeText (baseNameOf name) config.content}";
          defaultText = lib.literalExpression "a sops-nix template with secret holes, a store file without";
          description = "Rendered file: a sops-nix template with secret holes, a store file without";
        };
      };
      config.sopsTemplate = {
        inherit (config) content mode;
      };
    };

  rendered =
    lib.mapAttrsToList (_: n: n.env) (lib.filterAttrs (_: n: n.env.enable) cfg.namespaces)
    ++ lib.attrValues (lib.filterAttrs (_: f: f.hasHoles) cfg.files);
  names = map (r: r.name) rendered;
  duplicates = lib.unique (lib.filter (n: lib.count (m: m == n) names > 1) names);

  fileAssertions =
    id: f:
    let
      at = "stencil.files.\"${id}\"";
      problems = lib.filter (p: p.status != "ok") (
        map (hole: resolve f.namespace hole // { inherit hole; }) (stencil.holesOf f.raw)
      );
      unusedVars = lib.filter (v: !lib.hasInfix "@${v}@" f.raw) (lib.attrNames f.vars);
    in
    [
      {
        assertion = problems == [ ];
        message = "${at}: ${
          lib.concatMapStringsSep "; " (p: "${stencil.holeRef p.hole} ${p.status}") problems
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

    assertions = [
      {
        assertion = duplicates == [ ];
        message = "stencil: rendered file names ${lib.concatStringsSep ", " duplicates} are used more than once";
      }
    ]
    ++ lib.mapAttrsToList (namespace: _: {
      assertion = stencil.isNamespace namespace;
      message = "stencil.namespaces.${namespace}: a namespace name must match ${stencil.patterns.namespace}";
    }) cfg.namespaces
    ++ lib.mapAttrsToList (namespace: n: {
      assertion = n.keys != [ ];
      message = "stencil.namespaces.${namespace}: ${toString n.sopsFile} has no top-level KEY: ENC[...] string entries";
    }) cfg.namespaces
    ++ lib.concatLists (lib.mapAttrsToList fileAssertions cfg.files);

    warnings =
      lib.concatLists (
        lib.mapAttrsToList (
          namespace: n:
          lib.optional (n.skippedKeys != [ ])
            "stencil.namespaces.${namespace}: skipped keys of ${toString n.sopsFile}: ${
              lib.concatMapStringsSep ", " (s: "${s.key} (${s.reason})") n.skippedKeys
            }"
        ) cfg.namespaces
      )
      ++ lib.concatLists (
        lib.mapAttrsToList (
          id: f:
          lib.optional (
            !f.hasHoles && f.mode != "0400"
          ) "stencil.files.\"${id}\": mode is ignored, a file without secret holes is a store file"
        ) cfg.files
      );
  };
}
