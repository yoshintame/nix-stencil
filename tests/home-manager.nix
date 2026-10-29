{
  lib,
  inputs,
  homeManagerModule,
}:
let
  home = "/home/u";

  evalOn =
    system: homeDirectory: modules:
    let
      pkgs = inputs.nixpkgs.legacyPackages.${system};
      hmLib = import "${inputs.home-manager}/modules/lib/stdlib-extended.nix" pkgs.lib;
    in
    (hmLib.evalModules {
      class = "homeManager";
      specialArgs.modulesPath = "${inputs.home-manager}/modules";
      modules =
        import "${inputs.home-manager}/modules/modules.nix" {
          inherit pkgs;
          lib = hmLib;
        }
        ++ [
          inputs.sops-nix.homeManagerModules.sops
          homeManagerModule
          {
            home = {
              username = "u";
              inherit homeDirectory;
              stateVersion = "25.05";
            };
            sops.age.keyFile = "${homeDirectory}/.config/sops/age/keys.txt";
          }
        ]
        ++ modules;
    }).config;

  eval = evalOn "x86_64-linux" home;

  base = {
    stencil.namespaces = {
      own.sopsFile = ./fixtures/own.yaml;
      peer.sopsFile = ./fixtures/peer.yaml;
    };
    stencil.files = {
      "~/.config/app/config.json" = {
        namespace = "own";
        template = ./fixtures/app.json;
        vars.root = "/srv";
      };
      "/home/u/abs.conf" = {
        namespace = "own";
        template = ./fixtures/bare.conf;
      };
      "rel/x.conf" = {
        namespace = "own";
        template = ./fixtures/bare.conf;
      };
      kept = {
        namespace = "own";
        template = ./fixtures/bare.conf;
        target = null;
      };
      "~/.config/app/plain.conf" = {
        template = ./fixtures/plain.conf;
        vars.port = "80";
      };
    };
  };

  cfg = eval [ base ];
  inherit (import ./support.nix { inherit lib; } eval) failedMessages rejects;
in
lib.debug.runTests {
  testTargetDefaultsToId = {
    expr = lib.mapAttrs (_: f: f.path) (lib.filterAttrs (_: f: f.hasHoles) cfg.stencil.files);
    expected = {
      "~/.config/app/config.json" = "${home}/.config/app/config.json";
      "/home/u/abs.conf" = "${home}/abs.conf";
      "rel/x.conf" = "${home}/rel/x.conf";
      kept = "${home}/.config/sops-nix/secrets/rendered/stencil-file-kept";
    };
  };

  testTemplatePlacedAtTarget = {
    expr = cfg.sops.templates."stencil-file-~%2F.config%2Fapp%2Fconfig.json".path;
    expected = "${home}/.config/app/config.json";
  };

  testRefs = {
    expr = cfg.stencil.refs.peer;
    expected.TOKEN = "${home}/.config/sops-nix/secrets/peer/TOKEN";
  };

  testEnvTarget = {
    expr =
      let
        c = eval [
          base
          {
            stencil.namespaces.own.env.enable = true;
            stencil.namespaces.peer.env = {
              enable = true;
              target = "~/.config/peer.env";
            };
          }
        ];
      in
      map (ns: c.stencil.namespaces.${ns}.env.path) [
        "own"
        "peer"
      ];
    expected = [
      "${home}/.config/sops-nix/secrets/rendered/stencil-env-own"
      "${home}/.config/peer.env"
    ];
  };

  testStoreFileLinkedThroughHomeFile = {
    expr =
      let
        f = cfg.stencil.files."~/.config/app/plain.conf";
        link = cfg.home.file."stencil-~/.config/app/plain.conf";
      in
      {
        inherit (link) target force;
        source = toString link.source == f.path;
        template = cfg.sops.templates ? ${f.name};
        links = lib.filter (lib.hasPrefix "stencil-") (lib.attrNames cfg.home.file);
      };
    expected = {
      target = ".config/app/plain.conf";
      force = true;
      source = true;
      template = false;
      links = [ "stencil-~/.config/app/plain.conf" ];
    };
  };

  testSopsFileWithTarget =
    let
      c = eval [
        {
          stencil.files."~/.config/tool/key" = {
            sopsFile = ./fixtures/own.yaml;
            template = ./fixtures/bare.conf;
          };
        }
      ];
      t = c.sops.templates."stencil-file-~%2F.config%2Ftool%2Fkey";
    in
    {
      expr = {
        inherit (t) path content;
        failed = failedMessages c;
      };
      expected = {
        path = "${home}/.config/tool/key";
        content = "v=${c.sops.placeholder."fixtures/SECRET"}\n";
        failed = [ ];
      };
    };

  testRejectsTargetOutsideHome = {
    expr =
      map
        (
          fragment:
          rejects fragment [
            base
            {
              stencil.files."/etc/app.conf" = {
                namespace = "own";
                template = ./fixtures/bare.conf;
              };
              stencil.namespaces.peer.env = {
                enable = true;
                target = "/etc/peer.env";
              };
            }
          ]
        )
        [
          "stencil.files.\"/etc/app.conf\": target /etc/app.conf is outside"
          "stencil.namespaces.peer.env: target /etc/peer.env is outside"
        ];
    expected = [
      true
      true
    ];
  };

  testRejectsDuplicateTargets = {
    expr = rejects "targets ${home}/.npmrc are used more than once" [
      base
      {
        stencil.files = {
          ".npmrc" = {
            namespace = "own";
            template = ./fixtures/bare.conf;
          };
          "~/.npmrc" = {
            namespace = "own";
            template = ./fixtures/bare.conf;
            name = "npmrc";
          };
        };
      }
    ];
    expected = true;
  };

  testRejectsTemplateOverHomeFile = {
    expr = rejects "target ${home}/.npmrc is also a home.file target" [
      base
      {
        home.file.".npmrc".text = "registry=x";
        stencil.files."~/.npmrc" = {
          namespace = "own";
          template = ./fixtures/bare.conf;
        };
      }
    ];
    expected = true;
  };

  testDarwinAgentFollowsEnable = {
    expr =
      map
        (
          enable:
          (evalOn "aarch64-darwin" "/Users/u" [
            {
              stencil.enable = enable;
              stencil.files."~/.config/app/key" = {
                sopsFile = ./fixtures/own.yaml;
                template = ./fixtures/bare.conf;
              };
            }
          ]).launchd.agents
            ? sops-nix
        )
        [
          true
          false
        ];
    expected = [
      true
      false
    ];
  };

  testValid = {
    expr = failedMessages cfg;
    expected = [ ];
  };
}
