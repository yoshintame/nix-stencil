{
  lib,
  inputs,
  nixosModule,
}:
let
  eval =
    modules:
    (inputs.nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        inputs.sops-nix.nixosModules.sops
        nixosModule
        {
          boot.loader.grub.enable = false;
          fileSystems."/" = {
            device = "none";
            fsType = "tmpfs";
          };
          system.stateVersion = "25.05";
          sops.age.keyFile = "/var/lib/sops-nix/key.txt";
          users.groups.appgrp = { };
          users.users.app = {
            isSystemUser = true;
            group = "appgrp";
          };
        }
      ]
      ++ modules;
    }).config;

  base = {
    stencil.namespaces = {
      own = {
        sopsFile = ./fixtures/own.yaml;
        env = {
          enable = true;
          restartUnits = [ "app.service" ];
        };
      };
      peer.sopsFile = ./fixtures/peer.yaml;
    };
    stencil.files = {
      "app/config.json" = {
        namespace = "own";
        template = ./fixtures/app.json;
        vars.root = "/srv";
        owner = "app";
        mode = "0440";
        restartUnits = [ "app.service" ];
      };
      "/etc/app/plain.conf" = {
        template = ./fixtures/plain.conf;
        vars.port = "80";
      };
    };
  };

  cfg = eval [ base ];
  ph = name: cfg.sops.placeholder.${name};
  appTemplate = cfg.sops.templates."stencil-file-app%2Fconfig.json";
  failedMessages = config: map (a: a.message) (lib.filter (a: !a.assertion) config.assertions);
  rejects = fragment: modules: lib.any (lib.hasInfix fragment) (failedMessages (eval modules));
  warns = fragment: modules: lib.any (lib.hasInfix fragment) (eval modules).warnings;
in
lib.debug.runTests {
  testSecretPerStringKey = {
    expr = lib.mapAttrs (_: s: { inherit (s) key sopsFile format; }) cfg.sops.secrets;
    expected = {
      "own/SECRET" = {
        key = "SECRET";
        sopsFile = ./fixtures/own.yaml;
        format = "yaml";
      };
      "own/API_TOKEN" = {
        key = "API_TOKEN";
        sopsFile = ./fixtures/own.yaml;
        format = "yaml";
      };
      "peer/TOKEN" = {
        key = "TOKEN";
        sopsFile = ./fixtures/peer.yaml;
        format = "yaml";
      };
    };
  };

  testFormatIgnoresDefaultSopsFormat = {
    expr =
      (eval [
        base
        { sops.defaultSopsFormat = "json"; }
      ]).sops.secrets."own/SECRET".format;
    expected = "yaml";
  };

  testRefs = {
    expr = cfg.stencil.refs;
    expected = {
      own = {
        SECRET = "/run/secrets/own/SECRET";
        API_TOKEN = "/run/secrets/own/API_TOKEN";
      };
      peer.TOKEN = "/run/secrets/peer/TOKEN";
    };
  };

  testTemplateFillsVarsAndHoles = {
    expr = appTemplate.content;
    expected = ''
      {
        "root": "/srv",
        "secret": "${ph "own/SECRET"}",
        "token": "${ph "peer/TOKEN"}",
        "literal": "''${KEEP}"
      }
    '';
  };

  testTemplateDeliveryKeepsOwnerGroup = {
    expr = {
      inherit (appTemplate)
        owner
        group
        mode
        restartUnits
        ;
      inherit (cfg.stencil.files."app/config.json") path;
    };
    expected = {
      owner = "app";
      group = "appgrp";
      mode = "0440";
      restartUnits = [ "app.service" ];
      path = "/run/secrets/rendered/stencil-file-app%2Fconfig.json";
    };
  };

  testFileWithoutHolesGoesToStore = {
    expr =
      let
        f = cfg.stencil.files."/etc/app/plain.conf";
      in
      {
        store = lib.hasPrefix builtins.storeDir f.path;
        inherit (f) content;
        template = cfg.sops.templates ? ${f.name};
      };
    expected = {
      store = true;
      content = "port=80\n";
      template = false;
    };
  };

  testEscapedHoleInStoreFile = {
    expr =
      (eval [
        base
        {
          stencil.files.escaped = {
            template = ./fixtures/escaped.conf;
            vars.port = "1";
          };
        }
      ]).stencil.files.escaped.content;
    expected = "a=\${HOME} port=1\n";
  };

  testVarsAreNotHoles = {
    expr =
      let
        c = eval [
          base
          {
            stencil.files.vars = {
              template = ./fixtures/plain.conf;
              vars.port = "\${HOME}";
            };
          }
        ];
      in
      {
        inherit (c.stencil.files.vars) hasHoles content;
        failed = failedMessages c;
      };
    expected = {
      hasHoles = false;
      content = "port=\${HOME}\n";
      failed = [ ];
    };
  };

  testEnvFile = {
    expr = {
      inherit (cfg.sops.templates."stencil-env-own") content restartUnits;
      inherit (cfg.stencil.namespaces.own.env) path;
      peer = cfg.sops.templates ? "stencil-env-peer";
    };
    expected = {
      content = "SECRET=${ph "own/SECRET"}\nAPI_TOKEN=${ph "own/API_TOKEN"}\n";
      restartUnits = [ "app.service" ];
      path = "/run/secrets/rendered/stencil-env-own";
      peer = false;
    };
  };

  testDisabledEnvPathThrows = {
    expr = (builtins.tryEval cfg.stencil.namespaces.peer.env.path).success;
    expected = false;
  };

  testNamesDoNotCollide = {
    expr =
      let
        c = eval [
          base
          {
            stencil.files = {
              "a/b" = {
                namespace = "own";
                template = ./fixtures/bare.conf;
              };
              "a-b" = {
                namespace = "own";
                template = ./fixtures/bare.conf;
              };
              "own.env" = {
                namespace = "own";
                template = ./fixtures/bare.conf;
              };
            };
          }
        ];
      in
      {
        names = map (f: f.name) (lib.attrValues c.stencil.files);
        env = lib.hasPrefix "SECRET=" c.sops.templates."stencil-env-own".content;
        failed = failedMessages c;
      };
    expected = {
      names = [
        "stencil-file-%2Fetc%2Fapp%2Fplain.conf"
        "stencil-file-a-b"
        "stencil-file-a%2Fb"
        "stencil-file-app%2Fconfig.json"
        "stencil-file-own.env"
      ];
      env = true;
      failed = [ ];
    };
  };

  testWarnsSkippedKeys = {
    expr = warns "skipped keys of" [ base ] && warns "PORT (not a string)" [ base ];
    expected = true;
  };

  testWarnsIgnoredDeliveryOfStoreFile = {
    expr = warns "owner, group and restartUnits are ignored" [
      base
      {
        stencil.files.plain = {
          template = ./fixtures/plain.conf;
          vars.port = "1";
          restartUnits = [ "x.service" ];
        };
      }
    ];
    expected = true;
  };

  testValid = {
    expr = failedMessages cfg;
    expected = [ ];
  };

  testRejectsUnresolvedHoles = {
    expr =
      map
        (
          f:
          rejects f [
            base
            {
              stencil.files.broken = {
                namespace = "own";
                template = ./fixtures/broken.conf;
              };
            }
          ]
        )
        [
          "\${NOPE} absent from"
          "\${peer.MISSING} absent from"
          "\${ghost.X} namespace ghost is not declared"
        ];
    expected = [
      true
      true
      true
    ];
  };

  testRejectsBareHoleWithoutNamespace = {
    expr = rejects "\${SECRET} no namespace" [
      base
      { stencil.files.bare.template = ./fixtures/bare.conf; }
    ];
    expected = true;
  };

  testRejectsUnusedVar = {
    expr = rejects "vars nope do not occur" [
      base
      {
        stencil.files.plain = {
          template = ./fixtures/plain.conf;
          vars = {
            port = "80";
            nope = "x";
          };
        };
      }
    ];
    expected = true;
  };

  testRejectsNamespaceWithoutKeys = {
    expr = rejects "has no top-level KEY: ENC" [
      base
      { stencil.namespaces.empty.sopsFile = ./fixtures/plain.conf; }
    ];
    expected = true;
  };

  testRejectsInvalidNamespaceName = {
    expr = rejects "a namespace name must match" [
      base
      { stencil.namespaces.my_app.sopsFile = ./fixtures/peer.yaml; }
    ];
    expected = true;
  };

  testRejectsDuplicateNames = {
    expr = rejects "are used more than once" [
      base
      {
        stencil.files.dup = {
          namespace = "own";
          template = ./fixtures/bare.conf;
          name = "stencil-env-own";
        };
      }
    ];
    expected = true;
  };
}
