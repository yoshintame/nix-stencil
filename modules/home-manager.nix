{ config, lib, ... }:
let
  inherit (lib) mkOption types;
  cfg = config.stencil;
  home = config.home.homeDirectory;

  absolute =
    target: if lib.hasPrefix "/" target then target else "${home}/${lib.removePrefix "~/" target}";

  delivery =
    { config, ... }:
    {
      options.target = mkOption {
        type = types.nullOr types.str;
        default = null;
        apply = target: if target == null then null else absolute target;
        description = "Where the file is placed: ~/, absolute or relative to the home directory; null keeps it in the sops-nix rendered directory";
      };
      config.sopsTemplate = lib.optionalAttrs (config.target != null) { path = config.target; };
    };

  linkName = id: "stencil-${id}";
  linked = lib.filterAttrs (_: f: !f.hasHoles && f.target != null) cfg.files;

  placed =
    lib.mapAttrsToList (id: f: {
      at = "stencil.files.\"${id}\"";
      inherit (f) target;
      rendered = f.hasHoles;
    }) (lib.filterAttrs (_: f: f.target != null) cfg.files)
    ++ lib.mapAttrsToList (namespace: n: {
      at = "stencil.namespaces.${namespace}.env";
      inherit (n.env) target;
      rendered = true;
    }) (lib.filterAttrs (_: n: n.env.enable && n.env.target != null) cfg.namespaces);

  targets = map (p: p.target) placed;
  duplicateTargets = lib.unique (lib.filter (t: lib.count (u: u == t) targets > 1) targets);

  foreignTargets = lib.mapAttrsToList (_: f: absolute f.target) (
    lib.filterAttrs (name: _: !(lib.elem name (map linkName (lib.attrNames linked)))) config.home.file
  );
in
{
  imports = [ ./common ];

  options.stencil = {
    namespaces = mkOption {
      type = types.attrsOf (
        types.submodule { options.env = mkOption { type = types.submodule delivery; }; }
      );
    };
    files = mkOption {
      type = types.attrsOf (
        types.submodule (
          { name, ... }:
          {
            imports = [ delivery ];
            target = lib.mkDefault name;
          }
        )
      );
    };
  };

  config = {
    home.file = lib.mapAttrs' (
      id: f:
      lib.nameValuePair (linkName id) {
        inherit (f) target;
        source = f.path;
        force = true;
      }
    ) linked;

    assertions =
      map (p: {
        assertion = lib.hasPrefix "${home}/" p.target;
        message = "${p.at}: target ${p.target} is outside the home directory ${home}";
      }) placed
      ++ [
        {
          assertion = duplicateTargets == [ ];
          message = "stencil: targets ${lib.concatStringsSep ", " duplicateTargets} are used more than once";
        }
      ]
      ++ map (p: {
        assertion = !lib.elem p.target foreignTargets;
        message = "${p.at}: target ${p.target} is also a home.file target";
      }) (lib.filter (p: p.rendered) placed);
  };
}
