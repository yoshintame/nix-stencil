{ config, lib, ... }:
let
  inherit (lib) mkOption types;

  delivery =
    { config, ... }:
    {
      options = {
        owner = mkOption {
          type = types.nullOr types.str;
          default = null;
        };
        group = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "Group of the file; null keeps the sops-nix default, the group of the owner";
        };
        restartUnits = mkOption {
          type = types.listOf types.str;
          default = [ ];
          description = "Units restarted when the rendered file changes";
        };
      };
      config.sopsTemplate =
        lib.optionalAttrs (config.owner != null) { inherit (config) owner; }
        // lib.optionalAttrs (config.group != null) { inherit (config) group; }
        // lib.optionalAttrs (config.restartUnits != [ ]) { inherit (config) restartUnits; };
    };
in
{
  imports = [ ./common.nix ];

  options.stencil = {
    namespaces = mkOption {
      type = types.attrsOf (
        types.submodule { options.env = mkOption { type = types.submodule delivery; }; }
      );
    };
    files = mkOption {
      type = types.attrsOf (types.submodule delivery);
    };
  };

  config.warnings = lib.concatLists (
    lib.mapAttrsToList (
      id: f:
      lib.optional (!f.hasHoles && (f.owner != null || f.group != null || f.restartUnits != [ ]))
        "stencil.files.\"${id}\": owner, group and restartUnits are ignored, a file without secret holes is a store file"
    ) config.stencil.files
  );
}
