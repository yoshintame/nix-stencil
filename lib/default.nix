{ lib }:
let
  hole = "(\\$?)\\$\\{(([a-z0-9-]+)\\.)?([A-Z_][A-Z0-9_]*)}";

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
    ) (builtins.split hole text);

  literal = h: "\${${lib.optionalString (h.namespace != null) "${h.namespace}."}${h.key}}";
in
rec {
  holesOf =
    text:
    lib.unique (
      map (h: { inherit (h) namespace key; }) (lib.filter (h: lib.isAttrs h && !h.escaped) (parse text))
    );

  fillHoles =
    { namespace, placeholderOf }:
    text:
    lib.concatMapStrings (
      h:
      if !lib.isAttrs h then
        h
      else if h.escaped then
        literal h
      else
        placeholderOf (if h.namespace == null then namespace else h.namespace) h.key
    ) (parse text);

  fillVars =
    vars: text:
    builtins.replaceStrings (map (name: "@${name}@") (lib.attrNames vars)) (lib.attrValues vars) text;

  secretKeys =
    file:
    lib.concatMap (
      line:
      let
        m = builtins.match "([A-Z_][A-Z0-9_]*):[[:space:]]+ENC\\[.*" line;
      in
      lib.optional (m != null) (lib.head m)
    ) (lib.splitString "\n" (builtins.readFile file));

  secretName = namespace: key: "${namespace}/${key}";

  templateName = id: "stencil-${lib.replaceStrings [ "/" ] [ "-" ] (lib.removePrefix "/" id)}";

  envTemplateName = namespace: "stencil-${namespace}.env";

  envLines =
    placeholderOf: namespace: keys:
    lib.concatMapStrings (key: "${key}=${placeholderOf namespace key}\n") keys;

  hasHoles = text: holesOf text != [ ];
}
