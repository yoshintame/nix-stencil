{
  lib,
  pkgs,
  stencil,
  context,
  top,
}:
let
  inherit (lib) mkOption types;
  inherit (context) renderedOptions placeholderOf;

  encode = builtins.replaceStrings [ "%" "/" ] [ "%25" "%2F" ];

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
in
fileModule
