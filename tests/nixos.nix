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
  failedMessages = config: map (a: a.message) (lib.filter (a: !a.assertion) config.assertions);
  rejects = fragment: modules: lib.any (lib.hasInfix fragment) (failedMessages (eval modules));
in
lib.debug.runTests {
  testSecretPerKey = {
    expr = lib.mapAttrs (_: s: { inherit (s) key sopsFile; }) cfg.sops.secrets;
    expected = {
      "own/SECRET" = {
        key = "SECRET";
        sopsFile = ./fixtures/own.yaml;
      };
      "own/API_TOKEN" = {
        key = "API_TOKEN";
        sopsFile = ./fixtures/own.yaml;
      };
      "peer/TOKEN" = {
        key = "TOKEN";
        sopsFile = ./fixtures/peer.yaml;
      };
    };
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
    expr = cfg.sops.templates."stencil-app-config.json".content;
    expected = ''
      {
        "root": "/srv",
        "secret": "${ph "own/SECRET"}",
        "token": "${ph "peer/TOKEN"}",
        "literal": "''${KEEP}"
      }
    '';
  };

  testTemplateDelivery = {
    expr = {
      inherit (cfg.sops.templates."stencil-app-config.json") owner mode restartUnits;
      inherit (cfg.stencil.files."app/config.json") path;
    };
    expected = {
      owner = "app";
      mode = "0400";
      restartUnits = [ "app.service" ];
      path = "/run/secrets/rendered/stencil-app-config.json";
    };
  };

  testFileWithoutHolesGoesToStore = {
    expr =
      let
        p = cfg.stencil.files."/etc/app/plain.conf".path;
      in
      {
        store = lib.hasPrefix builtins.storeDir p;
        content = builtins.readFile p;
        template = cfg.sops.templates ? "stencil-etc-app-plain.conf";
      };
    expected = {
      store = true;
      content = "port=80\n";
      template = false;
    };
  };

  testEnvFile = {
    expr = {
      inherit (cfg.sops.templates."stencil-own.env") content restartUnits;
      inherit (cfg.stencil.namespaces.own.env) path;
      peer = cfg.sops.templates ? "stencil-peer.env";
    };
    expected = {
      content = "SECRET=${ph "own/SECRET"}\nAPI_TOKEN=${ph "own/API_TOKEN"}\n";
      restartUnits = [ "app.service" ];
      path = "/run/secrets/rendered/stencil-own.env";
      peer = false;
    };
  };

  testValid = {
    expr = failedMessages cfg;
    expected = [ ];
  };

  testRejectsMissingKey = {
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
          "\${NOPE} is absent from"
          "\${peer.MISSING} is absent from"
          "namespaces ghost are not declared"
        ];
    expected = [
      true
      true
      true
    ];
  };

  testRejectsBareHoleWithoutNamespace = {
    expr = rejects "have no namespace" [
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
}
