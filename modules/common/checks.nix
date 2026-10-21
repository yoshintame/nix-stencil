{ config, lib, ... }:
let
  stencil = import ../../lib { inherit lib; };
  inherit (import ./context.nix { inherit config lib stencil; }) resolve rendered;
  cfg = config.stencil;

  names = map (r: r.name) rendered;
  duplicates = lib.unique (lib.filter (n: lib.count (m: m == n) names > 1) names);

  fileAssertions =
    id: f:
    let
      at = "stencil.files.\"${id}\"";
      problems = lib.filter (p: p.status != "ok") (
        map (hole: resolve f.namespace hole // { inherit hole; }) (stencil.holesOf f.raw)
      );
      unusedVars = lib.filter (v: !lib.hasInfix "@${v}@" f.raw) (lib.attrNames f.vars);
    in
    [
      {
        assertion = problems == [ ];
        message = "${at}: ${
          lib.concatMapStringsSep "; " (p: "${stencil.holeRef p.hole} ${p.status}") problems
        }";
      }
      {
        assertion = unusedVars == [ ];
        message = "${at}: vars ${lib.concatStringsSep ", " unusedVars} do not occur in the template as @var@";
      }
    ];
in
{
  config = {
    assertions = [
      {
        assertion = duplicates == [ ];
        message = "stencil: rendered file names ${lib.concatStringsSep ", " duplicates} are used more than once";
      }
    ]
    ++ lib.mapAttrsToList (namespace: _: {
      assertion = stencil.isNamespace namespace;
      message = "stencil.namespaces.${namespace}: a namespace name must match ${stencil.patterns.namespace}";
    }) cfg.namespaces
    ++ lib.mapAttrsToList (namespace: n: {
      assertion = n.keys != [ ];
      message = "stencil.namespaces.${namespace}: ${toString n.sopsFile} has no top-level KEY: ENC[...] string entries";
    }) cfg.namespaces
    ++ lib.concatLists (lib.mapAttrsToList fileAssertions cfg.files);

    warnings =
      lib.concatLists (
        lib.mapAttrsToList (
          namespace: n:
          lib.optional (n.skippedKeys != [ ])
            "stencil.namespaces.${namespace}: skipped keys of ${toString n.sopsFile}: ${
              lib.concatMapStringsSep ", " (s: "${s.key} (${s.reason})") n.skippedKeys
            }"
        ) cfg.namespaces
      )
      ++ lib.concatLists (
        lib.mapAttrsToList (
          id: f:
          lib.optional (
            !f.hasHoles && f.mode != "0400"
          ) "stencil.files.\"${id}\": mode is ignored, a file without secret holes is a store file"
        ) cfg.files
      );
  };
}
