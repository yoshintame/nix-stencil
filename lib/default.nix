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

  topLevelEntry = builtins.match "([^[:space:]#:][^:]*):[[:space:]]+(.*)";
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

  scanSopsFile =
    file:
    let
      entries = lib.concatMap (
        line:
        let
          m = topLevelEntry line;
        in
        lib.optional (m != null && lib.hasPrefix "ENC[" (lib.elemAt m 1)) {
          key = lib.head m;
          value = lib.elemAt m 1;
        }
      ) (lib.splitString "\n" (builtins.readFile file));
      reasonOf =
        e:
        if builtins.match keyPattern e.key == null then
          "name outside ${keyPattern}"
        else if !lib.hasInfix ",type:str]" e.value then
          "not a string"
        else
          null;
      classified = map (e: e // { reason = reasonOf e; }) entries;
    in
    {
      keys = map (e: e.key) (lib.filter (e: e.reason == null) classified);
      skipped = map (e: { inherit (e) key reason; }) (lib.filter (e: e.reason != null) classified);
    };

  secretName = namespace: key: "${namespace}/${key}";
}
