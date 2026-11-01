{ lib }:
let
  topLevelEntry = builtins.match "([^[:space:]#:][^:]*):[[:space:]]+(.*)";
in
{
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
        if lib.hasPrefix "\"" e.key || lib.hasPrefix "'" e.key then
          "quoted key"
        else if lib.hasInfix "/" e.key then
          "sops-nix reads / in a key as nesting"
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
