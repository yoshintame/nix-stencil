{
  config,
  lib,
  stencil,
}:
let
  inherit (lib) mkOption types;
  cfg = config.stencil;

  resolve =
    defaultNamespace: hole:
    let
      namespace = if hole.namespace == null then defaultNamespace else hole.namespace;
    in
    if namespace == null then
      { status = "no namespace; set the namespace or the sopsFile of the file"; }
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

  whenEnabled = what: value: if cfg.enable then value else throw "${what}: stencil.enable is false";

  secretPath = what: name: whenEnabled what config.sops.secrets.${name}.path;

  templatePath = what: name: whenEnabled what config.sops.templates.${name}.path;

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

  rendered =
    lib.mapAttrsToList (_: n: n.env) (lib.filterAttrs (_: n: n.env.enable) cfg.namespaces)
    ++ lib.attrValues (lib.filterAttrs (_: f: f.hasHoles) cfg.files);
in
{
  inherit
    resolve
    placeholderOf
    secretPath
    templatePath
    renderedOptions
    rendered
    ;
}
