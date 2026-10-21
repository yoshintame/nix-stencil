{ lib }:
let
  keyPattern = "[A-Z_][A-Z0-9_]*";
  namespacePattern = "[a-z0-9-]+";
  holePattern = "(\\$?)\\$\\{((${namespacePattern})\\.)?(${keyPattern})}";

  parse =
    text:
    map (
      part:
      if lib.isList part then
        {
          escaped = lib.elemAt part 0 == "$";
          namespace = lib.elemAt part 2;
          key = lib.elemAt part 3;
        }
      else
        part
    ) (builtins.split holePattern text);

  holeRef =
    hole: "\${${lib.optionalString (hole.namespace != null) "${hole.namespace}."}${hole.key}}";

  fillVars =
    vars: text:
    builtins.replaceStrings (map (name: "@${name}@") (lib.attrNames vars)) (lib.attrValues vars) text;

in
{
  inherit holeRef;

  patterns = {
    key = keyPattern;
    namespace = namespacePattern;
  };

  isNamespace = namespace: builtins.match namespacePattern namespace != null;

  holesOf =
    text:
    lib.unique (
      map (hole: { inherit (hole) namespace key; }) (
        lib.filter (part: lib.isAttrs part && !part.escaped) (parse text)
      )
    );

  render =
    {
      vars ? { },
      placeholderOf,
    }:
    text:
    lib.concatMapStrings (
      part:
      if !lib.isAttrs part then
        fillVars vars part
      else if part.escaped then
        holeRef part
      else
        placeholderOf { inherit (part) namespace key; }
    ) (parse text);
}
