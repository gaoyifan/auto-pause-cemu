{self}: {
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib) mkEnableOption mkIf mkOption types;
  cfg = config.services.auto-pause-cemu;
in {
  options.services.auto-pause-cemu = {
    enable = mkEnableOption "automatic Cemu pause when a Bluetooth controller disconnects";

    package = mkOption {
      type = types.package;
      default = self.packages.${pkgs.stdenv.hostPlatform.system}.default;
      defaultText = lib.literalExpression "auto-pause-cemu.packages.\${pkgs.system}.default";
      description = "The auto-pause-cemu package to run.";
    };

    interval = mkOption {
      type = types.str;
      default = "2";
      description = "Polling interval in seconds.";
    };

    controllerName = mkOption {
      type = types.str;
      default = "DualSense Wireless Controller";
      description = "Bluetooth HID product name that controls Cemu.";
    };

    vendorID = mkOption {
      type = types.int;
      default = 0 x054c;
      description = "Controller USB vendor ID.";
    };

    productID = mkOption {
      type = types.int;
      default = 0 x0ce6;
      description = "Controller USB product ID.";
    };

    anyGamepad = mkOption {
      type = types.bool;
      default = false;
      description = "Treat any connected Bluetooth gamepad as the controller.";
    };

    cemuBundleID = mkOption {
      type = types.str;
      default = "info.cemu.Cemu";
      description = "Bundle identifier used to find Cemu.";
    };

    cemuExecutable = mkOption {
      type = types.str;
      default = "Cemu";
      description = "Executable name used to find Cemu.";
    };
  };

  config = mkIf cfg.enable {
    launchd.user.agents.auto-pause-cemu.serviceConfig = {
      ProgramArguments =
        [
          (lib.getExe cfg.package)
          "--interval"
          cfg.interval
          "--controller-name"
          cfg.controllerName
          "--vendor-id"
          (toString cfg.vendorID)
          "--product-id"
          (toString cfg.productID)
          "--cemu-bundle-id"
          cfg.cemuBundleID
          "--cemu-executable"
          cfg.cemuExecutable
        ]
        ++ lib.optional cfg.anyGamepad "--any-gamepad";
      RunAtLoad = true;
      KeepAlive = true;
      LimitLoadToSessionType = "Aqua";
      ProcessType = "Background";
      LowPriorityIO = true;
      ExitTimeOut = 5;
      StandardOutPath = "/tmp/auto-pause-cemu.stdout.log";
      StandardErrorPath = "/tmp/auto-pause-cemu.stderr.log";
    };
  };
}
