{ config, lib, ... }:
let
  inherit (lib) mkOption types;
  cfg = config.stencil;
  stencil = import ../lib { inherit lib; };

  delivery = {
    owner = mkOption {
      type = types.nullOr types.str;
      default = null;
    };
    group = mkOption {
      type = types.nullOr types.str;
      default = null;
    };
    restartUnits = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "Units restarted when the rendered file changes";
    };
  };
  deliveryOf = d: { inherit (d) owner group restartUnits; };
in
{
  imports = [ ./common.nix ];

  options.stencil = {
    namespaces = mkOption {
      type = types.attrsOf (types.submodule { options.env = delivery; });
    };
    files = mkOption {
      type = types.attrsOf (types.submodule { options = delivery; });
    };
  };

  config.sops.templates =
    lib.mapAttrs' (ns: n: lib.nameValuePair (stencil.envTemplateName ns) (deliveryOf n.env)) (
      lib.filterAttrs (_: n: n.env.enable) cfg.namespaces
    )
    // lib.mapAttrs' (id: f: lib.nameValuePair (stencil.templateName id) (deliveryOf f)) (
      lib.filterAttrs (_: f: f.secret) cfg.files
    );
}
