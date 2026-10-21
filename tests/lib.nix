{ lib, stencil }:
let
  placeholderOf = hole: "<${toString hole.namespace}/${hole.key}>";
  render = stencil.render { inherit placeholderOf; };
in
lib.debug.runTests {
  testBareHole = {
    expr = render "a=\${SECRET}";
    expected = "a=</SECRET>";
  };
  testNamespacedHole = {
    expr = render "a=\${peer-1.TOKEN}";
    expected = "a=<peer-1/TOKEN>";
  };
  testEscapedHoleIsLiteral = {
    expr = render "a=$\${LITERAL} b=$\${peer.LITERAL}";
    expected = "a=\${LITERAL} b=\${peer.LITERAL}";
  };
  testEscapedAndSecretInOneTemplate = {
    expr = render "a=$\${X} b=\${X}";
    expected = "a=\${X} b=</X>";
  };
  testTripleDollarKeepsOneDollar = {
    expr = render "a=$$\${X}";
    expected = "a=$\${X}";
  };
  testNotHoles = {
    expr = render "a=$X b=\${lower} c=\${Mixed_Case} d=\${1X} e=\${PEER.X} f=\${my_app.X}";
    expected = "a=$X b=\${lower} c=\${Mixed_Case} d=\${1X} e=\${PEER.X} f=\${my_app.X}";
  };
  testVars = {
    expr = stencil.render {
      inherit placeholderOf;
      vars = {
        root = "/srv";
        port = "80";
      };
    } "path=@root@/x port=@port@ keep=@other@";
    expected = "path=/srv/x port=80 keep=@other@";
  };
  testVarsAreLiteral = {
    expr = stencil.render {
      inherit placeholderOf;
      vars = {
        cmd = "echo \${HOME}";
        dollar = "$";
      };
    } "cmd=@cmd@ s=@dollar@\${KEY}";
    expected = "cmd=echo \${HOME} s=$</KEY>";
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
  testScanSopsFile = {
    expr = stencil.scanSopsFile ./fixtures/own.yaml;
    expected = {
      keys = [
        "SECRET"
        "API_TOKEN"
      ];
      skipped = [
        {
          key = "PORT";
          reason = "not a string";
        }
        {
          key = "legacy-env";
          reason = "name outside ${stencil.patterns.key}";
        }
      ];
    };
  };
  testIsNamespace = {
    expr = map stencil.isNamespace [
      "own"
      "peer-1"
      "my_app"
      "App"
    ];
    expected = [
      true
      true
      false
      false
    ];
  };
  testHoleRef = {
    expr = map stencil.holeRef [
      {
        namespace = null;
        key = "A";
      }
      {
        namespace = "ns";
        key = "B";
      }
    ];
    expected = [
      "\${A}"
      "\${ns.B}"
    ];
  };
}
