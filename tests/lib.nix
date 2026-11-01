{ lib, stencil }:
let
  placeholderOf = hole: "<${toString hole.namespace}/${hole.key}>";
  render = stencil.render { inherit placeholderOf; };
in
lib.debug.runTests {
  testBareHole = {
    expr = render "a=~{{SECRET}}";
    expected = "a=</SECRET>";
  };
  testNamespacedHole = {
    expr = render "a=~{{peer-1/TOKEN}}";
    expected = "a=<peer-1/TOKEN>";
  };
  testKeyIsAnyName = {
    expr = render "a=~{{restic-b2-key.id}} b=~{{infra/cf api token}} c=~{{lower_Case}}";
    expected = "a=</restic-b2-key.id> b=<infra/cf api token> c=</lower_Case>";
  };
  testNamespaceEndsAtFirstSlash = {
    expr = stencil.holesOf "a=~{{ns/a/b}} b=~{{/x}} c=~{{ns/}}";
    expected = [
      {
        namespace = "ns";
        key = "a/b";
      }
      {
        namespace = null;
        key = "/x";
      }
      {
        namespace = null;
        key = "ns/";
      }
    ];
  };
  testParseRef = {
    expr = map stencil.parseRef [
      "KEY"
      "infra/restic-b2-key-id"
    ];
    expected = [
      {
        namespace = null;
        key = "KEY";
      }
      {
        namespace = "infra";
        key = "restic-b2-key-id";
      }
    ];
  };
  testUnclosedHoleKeepsTheNextOne = {
    expr = render "a=~{{oops b=~{{KEY}}";
    expected = "a=~{{oops b=</KEY>";
  };
  testFormatRef = {
    expr = map stencil.formatRef [
      {
        namespace = null;
        key = "A";
      }
      {
        namespace = "ns";
        key = "b-c";
      }
    ];
    expected = [
      "A"
      "ns/b-c"
    ];
  };
  testEscapedHoleIsLiteral = {
    expr = render "a=~~{{LITERAL}} b=~~{{peer/literal}}";
    expected = "a=~{{LITERAL}} b=~{{peer/literal}}";
  };
  testEscapedAndSecretInOneTemplate = {
    expr = render "a=~~{{X}} b=~{{X}}";
    expected = "a=~{{X}} b=</X>";
  };
  testTripleTildeKeepsOneTilde = {
    expr = render "a=~~~{{X}}";
    expected = "a=~~{{X}}";
  };
  testNotHoles = {
    expr = render "a=\${X} b=$\${X} c=~{X} d=~{{}} e=~ {{X}} f=~{{X\n}} g=~/x h=~{{unclosed} i={{ .Env.X }} j=~{{a}b}} k=~{{a{b}}";
    expected = "a=\${X} b=$\${X} c=~{X} d=~{{}} e=~ {{X}} f=~{{X\n}} g=~/x h=~{{unclosed} i={{ .Env.X }} j=~{{a}b}} k=~{{a{b}}";
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
        cmd = "echo ~{{HOME}}";
        tilde = "~";
      };
    } "cmd=@cmd@ s=@tilde@~{{KEY}}";
    expected = "cmd=echo ~{{HOME}} s=~</KEY>";
  };
  testHolesOf = {
    expr = stencil.holesOf "a=~{{X}} b=~~{{Y}} c=~{{peer/Z}} d=~{{X}}";
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
        "legacy-env"
      ];
      skipped = [
        {
          key = "PORT";
          reason = "not a string";
        }
        {
          key = "nested/key";
          reason = "sops-nix reads / in a key as nesting";
        }
        {
          key = "\"123\"";
          reason = "quoted key";
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
        key = "b-c";
      }
    ];
    expected = [
      "~{{A}}"
      "~{{ns/b-c}}"
    ];
  };
}
