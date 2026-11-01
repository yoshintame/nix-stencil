{
  lib,
  pkgs,
  stencil,
  context,
}:
let
  inherit (lib) mkOption types;
  inherit (context) renderedOptions placeholderOf templatePath;

  encode = builtins.replaceStrings [ "%" "/" ] [ "%25" "%2F" ];

  directoryNamespace =
    file:
    lib.concatMapStrings (c: if builtins.match stencil.patterns.namespace c != null then c else "-") (
      lib.stringToCharacters (lib.toLower (baseNameOf (dirOf (toString file))))
    );

  fileModule =
    { name, config, ... }:
    {
      options = renderedOptions "stencil-file-${encode name}" // {
        namespace = mkOption {
          type = types.nullOr (types.strMatching stencil.patterns.namespace);
          default = null;
          description = "Namespace of the bare ~{{key}} holes; with sopsFile, defaults to the directory of sopsFile";
        };
        sopsFile = mkOption {
          type = types.nullOr types.path;
          default = null;
          description = "sops file that the file declares as its namespace";
        };
        template = mkOption {
          type = types.path;
          description = "Native config file with ~{{key}}, ~{{namespace/key}}, ~~{{literal}} and @var@ holes";
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
              templatePath "stencil.files.\"${name}\".path" config.name
            else
              "${pkgs.writeText (baseNameOf name) config.content}";
          defaultText = lib.literalExpression "a sops-nix template with secret holes, a store file without";
          description = "Rendered file: a sops-nix template with secret holes, a store file without";
        };
      };
      config = {
        namespace = lib.mkIf (config.sopsFile != null) (lib.mkDefault (directoryNamespace config.sopsFile));
        sopsTemplate = {
          inherit (config) content mode;
        };
      };
    };
in
fileModule
