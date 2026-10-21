{ lib, stencil }:
let
  placeholderOf = namespace: key: "<${namespace}/${key}>";
  fill = stencil.fillHoles {
    namespace = "own";
    inherit placeholderOf;
  };
in
lib.debug.runTests {
  testOwnHole = {
    expr = fill "a=\${SECRET}";
    expected = "a=<own/SECRET>";
  };
  testNamespacedHole = {
    expr = fill "a=\${peer-1.TOKEN}";
    expected = "a=<peer-1/TOKEN>";
  };
  testEscapedHoleIsLiteral = {
    expr = fill "a=$\${LITERAL} b=$\${peer.LITERAL}";
    expected = "a=\${LITERAL} b=\${peer.LITERAL}";
  };
  testEscapedAndSecretInOneTemplate = {
    expr = fill "a=$\${X} b=\${X}";
    expected = "a=\${X} b=<own/X>";
  };
  testTripleDollarKeepsOneDollar = {
    expr = fill "a=$$\${X}";
    expected = "a=$\${X}";
  };
  testNotHoles = {
    expr = fill "a=$X b=\${lower} c=\${Mixed_Case} d=\${1X} e=\${PEER.X}";
    expected = "a=$X b=\${lower} c=\${Mixed_Case} d=\${1X} e=\${PEER.X}";
  };
  testHolesOf = {
    expr = stencil.holesOf "a=\${X} b=$\${Y} c=\${peer.Z} d=\${X}";
    expected = [
      {
        namespace = null;
        key = "X";
      }
      {
        namespace = "peer";
        key = "Z";
      }
    ];
  };
  testHasHoles = {
    expr = map stencil.hasHoles [
      "a=@path@"
      "a=$\${X}"
      "a=\${X}"
    ];
    expected = [
      false
      false
      true
    ];
  };
  testFillVars = {
    expr = stencil.fillVars {
      root = "/srv";
      port = "80";
    } "path=@root@/x port=@port@ keep=@other@";
    expected = "path=/srv/x port=80 keep=@other@";
  };
  testSecretKeys = {
    expr = stencil.secretKeys ./fixtures/own.yaml;
    expected = [
      "SECRET"
      "API_TOKEN"
    ];
  };
  testEnvLines = {
    expr = stencil.envLines placeholderOf "own" [
      "A"
      "B"
    ];
    expected = "A=<own/A>\nB=<own/B>\n";
  };
}
