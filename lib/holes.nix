{ lib }:
let
  namespacePattern = "[a-z0-9-]+";
  holePattern = "(~?)~\\{\\{([^{}\n]+)}}";

  parseRef =
    ref:
    let
      m = builtins.match "([^/]+)/(.+)" ref;
    in
    if m == null then
      {
        namespace = null;
        key = ref;
      }
    else
      {
        namespace = lib.elemAt m 0;
        key = lib.elemAt m 1;
      };

  parse =
    text:
    map (
      part:
      if lib.isList part then
        { escaped = lib.elemAt part 0 == "~"; } // parseRef (lib.elemAt part 1)
      else
        part
    ) (builtins.split holePattern text);

  formatRef = hole: "${lib.optionalString (hole.namespace != null) "${hole.namespace}/"}${hole.key}";

  holeRef = hole: "~{{${formatRef hole}}}";

  fillVars =
    vars: text:
    builtins.replaceStrings (map (name: "@${name}@") (lib.attrNames vars)) (lib.attrValues vars) text;

in
{
  inherit holeRef parseRef formatRef;

  patterns = {
    namespace = namespacePattern;
    envKey = "[A-Za-z_][A-Za-z0-9_]*";
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
