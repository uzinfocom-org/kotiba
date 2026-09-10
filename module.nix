flake:
{ config, lib, pkgs, ... }:
let
  inherit (lib) mkEnableOption mkOption mkIf mkMerge types;

  package = flake.packages.${pkgs.stdenv.hostPlatform.system}.default;
  packageName = package.name;
  cfg = config.services.${packageName};

  caddy =
    lib.mkIf (cfg.enable && cfg.proxy.enable && cfg.proxy.proxy == "caddy") {
      services.caddy.virtualHosts = lib.debug.traceIf (isNull cfg.proxy.domain)
        "proxy.domain can't be null, please specify it properly!" {
          "${cfg.proxy.domain}" = {
            serverAliases = cfg.proxy.aliases;
            extraConfig = ''
              reverse_proxy 127.0.0.1:${toString cfg.port}
            '';
          };
        };
    };

  nginx =
    lib.mkIf (cfg.enable && cfg.proxy.enable && cfg.proxy.proxy == "nginx") {
      services.nginx = {
        virtualHosts = lib.debug.traceIf (isNull cfg.proxy.domain)
          "proxy.domain can't be null, please specify it properly!" {
            "${cfg.proxy.domain}" = {
              addSSL = true;
              enableACME = true;
              serverAliases = cfg.proxy.aliases;
              locations."/" = {
                proxyPass = "http://127.0.0.1:${toString cfg.port}";
                proxyWebsockets = true;
              };
            };
          };
        clientMaxBodySize = "64m";
      };
    };

  service = mkIf cfg.enable {
    users.users.${cfg.user} = {
      description = "${packageName} service user";
      isSystemUser = true;
      group = cfg.group;
      home = cfg.dataDir;
      useDefaultShell = true;
    };

    users.groups.${cfg.group} = { };

    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir}         0770 ${cfg.user} ${cfg.group} -"
      "f /var/log/${packageName}/info.log  0640 ${cfg.user} ${cfg.group} -"
      "f /var/log/${packageName}/error.log 0640 ${cfg.user} ${cfg.group} -"
    ];

    systemd.targets.${packageName} = { };

    systemd.services."${packageName}-config" = {
      wantedBy = [ "multi-user.target" ];
      after = [ "systemd-tmpfiles-setup.service" ];
      requires = [ "systemd-tmpfiles-setup.service" ];

      serviceConfig = {
        Type = "oneshot";
        User = cfg.user;
        Group = cfg.group;
        Restart = "on-failure";
        RestartSec = "2s";
        RemainAfterExit = true;

        ReadWritePaths = [ cfg.dataDir ];

        ExecStartPre = let
          preStartFullPrivileges = ''
            set -o errexit -o pipefail -o nounset
            ${pkgs.coreutils}/bin/install -d -m 0770 -o ${cfg.user} -g ${cfg.group} ${cfg.dataDir}
            ${pkgs.coreutils}/bin/install -d -m 0770 -o ${cfg.user} -g ${cfg.group} ${cfg.tmpDir}
          '';
        in "+${
          pkgs.writeShellScript "${packageName}-pre-start-full-privileges"
          preStartFullPrivileges
        }";

        ExecStart = pkgs.writeShellScript "${packageName}-config" ''
          set -o errexit -o pipefail -o nounset
          shopt -s inherit_errexit
          umask u=rwx,g=rx,o=
          ${pkgs.coreutils}/bin/install -m 0640 -o ${cfg.user} -g ${cfg.group} \
            ${toml-config} ${cfg.dataDir}/config.toml
        '';
      };
    };

    systemd.services.${packageName} = {
      description = "${packageName} — Forgejo webhook bot";

      environment = { };

      after = [ "network.target" "${packageName}-config.service" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      restartTriggers = [ cfg.package toml-config ];
      path = [ cfg.package ];

      serviceConfig = {
        User = cfg.user;
        Group = cfg.group;
        Restart = "always";
        SyslogLevel = "debug";
        StandardOutput = "append:/var/log/${packageName}/info.log";
        StandardError = "append:/var/log/${packageName}/error.log";
        ExecStart =
          "${lib.getBin package}/bin/${cfg.executableName} -c ${toml-config}";
        ExecReload = "${pkgs.coreutils}/bin/kill -s HUP $MAINPID";

        StateDirectory = cfg.user;
        StateDirectoryMode = "0770";
        LogsDirectory = packageName;
        LogsDirectoryMode = "0750";

        ReadWritePaths = [ cfg.dataDir "/var/log/${packageName}" ];

        CapabilityBoundingSet = [ "AF_NETLINK" "AF_INET" "AF_INET6" ];
        LockPersonality = true;
        PrivateDevices = true;
        PrivateTmp = true;
        PrivateUsers = false;
        ProtectClock = true;
        ProtectControlGroups = true;
        ProtectHostname = true;
        ProtectKernelLogs = true;
        ProtectKernelTunables = true;
        ProtectSystem = "strict";
        ReadOnlyPaths = [ "/" ];
        RemoveIPC = true;
        RestrictAddressFamilies =
          [ "AF_NETLINK" "AF_INET" "AF_INET6" "AF_UNIX" ];
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        SystemCallArchitectures = "native";
        UMask = "0027";
      };
    };
  };

  toml = pkgs.formats.toml { };

  toml-config = toml.generate "config.toml" {
    dataDir = cfg.dataDir;
    port = cfg.port;
    database = cfg.database;
    databasePoolSize = cfg.databasePoolSize;
    forgejoUrl = cfg.forgejoUrl;
    forgejoToken = cfg.forgejoToken;
  };

  asserts = lib.mkIf cfg.enable {
    warnings = [
      (lib.mkIf (cfg.proxy.enable && cfg.proxy.domain == null)
        "services.${packageName}.proxy.domain must be set in order to properly generate certificate!")
    ];
  };
in {
  options = with lib; {
    services.${packageName} = {
      enable = mkEnableOption ''
        ${packageName} running.
      '';

      proxy = {
        enable = mkEnableOption ''
          Proxy reversed method of deployment
        '';

        domain = mkOption {
          type = with types; nullOr str;
          default = null;
          example = "kotiba.uz";
          description =
            "Domain to use while adding configurations to web proxy server";
        };

        aliases = mkOption {
          type = with types; listOf str;
          default = [ ];
          example = [ "www.kotiba.uz" ];
          description = "List of domain aliases to add to domain";
        };

        proxy = mkOption {
          type = with types; nullOr (enum [ "nginx" "caddy" ]);
          default = "caddy";
          description = "Proxy reverse software for hosting website";
        };
      };

      host = mkOption {
        type = types.str;
        default = "127.0.0.1";
        description = "Hostname for kotiba to bind";
      };

      port = mkOption {
        type = types.int;
        default = 4343;
        description = "Port for kotiba's webhook HTTP server";
      };

      user = mkOption {
        type = types.str;
        default = "kotiba";
        description = "User for running the service";
      };

      group = mkOption {
        type = types.str;
        default = "kotiba";
        description = "Group for running the service";
      };

      dataDir = mkOption {
        type = types.str;
        default = "/var/lib/kotiba";
        description = ''
          The path where kotiba keeps its config and data.
        '';
      };

      database = mkOption {
        type = types.str;
        default = "postgresql://postgres:postgres@localhost:5432/kotiba";
        example = "postgresql://postgres:postgres@localhost:5432/kotiba";
        description = ''
          Database connection URI, used to store BackportRecord and other state.
        '';
      };

      databasePoolSize = mkOption {
        type = types.int;
        default = 10;
        example = 10;
        description = ''
          Database connection pool size.
        '';
      };

      forgejoUrl = mkOption {
        type = types.str;
        example = "https://forgejo.uzinfocom.uz";
        description = ''
          Base URL of the Forgejo instance kotiba talks to.
        '';
      };

      forgejoToken = mkOption {
        type = types.str;
        description = ''
          API token kotiba uses to authenticate against Forgejo.

          This ends up in a 0640 root:''${cfg.group}-readable file in
          ''${cfg.dataDir}/config.toml, but is otherwise stored in plaintext
          in the Nix store via this option. Prefer passing a path read at
          activation time (e.g. via agenix/sops-nix) over a literal string
          in your configuration.
        '';
      };

      executableName = mkOption {
        type = types.str;
        default = packageName;
        description = ''
          Name of the executable inside the package's bin/ output, in case
          it differs from the derivation name.
        '';
      };

      package = mkOption {
        type = types.package;
        default = package;
        description = ''
          Compiled kotiba package to use with the service.
        '';
      };
    };
  };
  config = mkMerge [ asserts service caddy nginx ];
}
