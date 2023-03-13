{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.minio;

  legacyCredentials = cfg: pkgs.writeText "minio-legacy-credentials" ''
    MINIO_ROOT_USER=${cfg.accessKey}
    MINIO_ROOT_PASSWORD=${cfg.secretKey}
  '';
in
{
  meta.maintainers = [ maintainers.bachp ];

  options.services.minio = {
    enable = mkEnableOption (lib.mdDoc "Minio Object Storage");

    listenAddress = mkOption {
      default = ":9000";
      type = types.str;
      description = lib.mdDoc "IP address and port of the server.";
    };

    consoleAddress = mkOption {
      default = ":9001";
      type = types.str;
      description = lib.mdDoc "IP address and port of the web UI (console).";
    };

    dataDir = mkOption {
      default = [ "/var/lib/minio/data" ];
      type = types.listOf types.path;
      description = lib.mdDoc "The list of data directories for storing the objects. Use one path for regular operation and the minimum of 4 endpoints for Erasure Code mode.";
    };

    configDir = mkOption {
      default = "/var/lib/minio/config";
      type = types.path;
      description = lib.mdDoc "The config directory, for the access keys and other settings.";
    };

    accessKey = mkOption {
      default = "";
      type = types.str;
      description = lib.mdDoc ''
        Access key of 5 to 20 characters in length that clients use to access the server.
        This overrides the access key that is generated by minio on first startup and stored inside the
        `configDir` directory.
      '';
    };

    secretKey = mkOption {
      default = "";
      type = types.str;
      description = lib.mdDoc ''
        Specify the Secret key of 8 to 40 characters in length that clients use to access the server.
        This overrides the secret key that is generated by minio on first startup and stored inside the
        `configDir` directory.
      '';
    };

    rootCredentialsFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = lib.mdDoc ''
        File containing the MINIO_ROOT_USER, default is "minioadmin", and
        MINIO_ROOT_PASSWORD (length >= 8), default is "minioadmin"; in the format of
        an EnvironmentFile=, as described by systemd.exec(5).
      '';
      example = "/etc/nixos/minio-root-credentials";
    };

    region = mkOption {
      default = "us-east-1";
      type = types.str;
      description = lib.mdDoc ''
        The physical location of the server. By default it is set to us-east-1, which is same as AWS S3's and Minio's default region.
      '';
    };

    browser = mkOption {
      default = true;
      type = types.bool;
      description = lib.mdDoc "Enable or disable access to web UI.";
    };

    package = mkOption {
      default = pkgs.minio;
      defaultText = literalExpression "pkgs.minio";
      type = types.package;
      description = lib.mdDoc "Minio package to use.";
    };
  };

  config = mkIf cfg.enable {
    warnings = optional ((cfg.accessKey != "") || (cfg.secretKey != "")) "services.minio.`accessKey` and services.minio.`secretKey` are deprecated, please use services.minio.`rootCredentialsFile` instead.";

    systemd = lib.mkMerge [{
      tmpfiles.rules = [
        "d '${cfg.configDir}' - minio minio - -"
      ] ++ (map (x: "d '" + x + "' - minio minio - - ") cfg.dataDir);

      services.minio = {
        description = "Minio Object Storage";
        after = [ "network-online.target" ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          ExecStart = "${cfg.package}/bin/minio server --json --address ${cfg.listenAddress} --console-address ${cfg.consoleAddress} --config-dir=${cfg.configDir} ${toString cfg.dataDir}";
          Type = "simple";
          User = "minio";
          Group = "minio";
          LimitNOFILE = 65536;
          EnvironmentFile =
            if (cfg.rootCredentialsFile != null) then cfg.rootCredentialsFile
            else if ((cfg.accessKey != "") || (cfg.secretKey != "")) then (legacyCredentials cfg)
            else null;
        };
        environment = {
          MINIO_REGION = "${cfg.region}";
          MINIO_BROWSER = "${if cfg.browser then "on" else "off"}";
        };
      };
    }

      (lib.mkIf (cfg.rootCredentialsFile != null) {
        services.minio.unitConfig.ConditionPathExists = cfg.rootCredentialsFile;

        paths.minio-root-credentials = {
          wantedBy = [ "multi-user.target" ];

          pathConfig = {
            PathChanged = [ cfg.rootCredentialsFile ];
            Unit = "minio-restart.service";
          };
        };

        services.minio-restart = {
          description = "Restart MinIO";

          script = ''
            systemctl restart minio.service
          '';

          serviceConfig = {
            Type = "oneshot";
            Restart = "on-failure";
            RestartSec = 5;
          };
        };
      })];

    users.users.minio = {
      group = "minio";
      uid = config.ids.uids.minio;
    };

    users.groups.minio.gid = config.ids.uids.minio;
  };
}
