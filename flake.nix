{
  description = ''
    Examples of NixOS systems' configuration for Raspberry Pi boards
    using nixos-raspberrypi
  '';

  nixConfig = {
    bash-prompt = "\[nixos-raspberrypi-demo\] ➜ ";
    extra-substituters = [
      "https://nixos-raspberrypi.cachix.org"
    ];
    extra-trusted-public-keys = [
      "nixos-raspberrypi.cachix.org-1:4iMO9LXa8BqhU+Rpg6LQKiGa2lsNh/j2oiYLNOQ5sPI="
    ];
    connect-timeout = 5;
  };

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixos-raspberrypi = {
      url = "github:nvmd/nixos-raspberrypi/main";
    };
    meshcoretomqtt = {
      url = "github:tbaumann/meshcoretomqtt";
      inputs.nixpkgs.follows = "nixos-raspberrypi/nixpkgs";
    };

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixos-raspberrypi/nixpkgs";
    };

    nixos-anywhere = {
      url = "github:nix-community/nixos-anywhere";
    };
  };

  outputs = {
    self,
    nixpkgs,
    nixos-raspberrypi,
    disko,
    nixos-anywhere,
    meshcoretomqtt,
    ...
  } @ inputs: {
    nixosConfigurations = let
      users-config-stub = {config, ...}: {
        # This is identical to what nixos installer does in
        # (modulesPash + "profiles/installation-device.nix")

        # Use less privileged nixos user
        users.users.nixos = {
          isNormalUser = true;
          extraGroups = [
            "wheel"
            "networkmanager"
            "video"
          ];
          # Allow the graphical user to login without password
          initialHashedPassword = "";
        };

        # Allow the user to log in as root without a password.
        users.users.root.initialHashedPassword = "";

        # Don't require sudo/root to `reboot` or `poweroff`.
        security.polkit.enable = true;

        # Allow passwordless sudo from nixos user
        security.sudo = {
          enable = true;
          wheelNeedsPassword = false;
        };

        # Automatically log in at the virtual consoles.
        services.getty.autologinUser = "nixos";

        # We run sshd by default. Login is only possible after adding a
        # password via "passwd" or by adding a ssh key to ~/.ssh/authorized_keys.
        # The latter one is particular useful if keys are manually added to
        # installation device for head-less systems i.e. arm boards by manually
        # mounting the storage in a different system.
        services.openssh = {
          enable = true;
          settings.PermitRootLogin = "yes";
        };

        # allow nix-copy to live system
        nix.settings.trusted-users = ["nixos"];

        # We are stateless, so just default to latest.
        system.stateVersion = config.system.nixos.release;
      };

      network-config = {
        networking.firewall.enable = false;
        networking.wireless.enable = true;
        networking.wireless.networks."LJF HOMESweetHOME 2,4" = {
          psk = "271026022807838515JFL";
        };
        networking.hostName = "meshcoremqttbridge";
        services.avahi = {
          enable = true;
          nssmdns4 = true;
          publish = {
            enable = true;
            workstation = true;
            addresses = true;
            userServices = true;
          };
        };
      };

      meshcoretomqtt-config = {
        imports = [meshcoretomqtt.nixosModules.default];
        services.mctomqtt = {
          enable = true;
          iata = "KSF";
          serialPorts = ["/dev/ttyUSB0"];

          # Disable defaults if you like.
          # Defaults are used if nothing is specified
          defaults = {
            letsmesh-us.enable = true;
            letsmesh-eu.enable = true;
          };
        };
      };
      # Disk configuration
      # Assumes the system will continue to reside on the installation media (sd-card),
      # as there're hardly other feasible options on RPi02.
      # (see also https://github.com/nvmd/nixos-raspberrypi/issues/8#issuecomment-2804912881)
      # `sd-image` has lots of dependencies unnecessary for the installed system,
      # replicating its disk layout
      sd-disk-config = {
        config,
        pkgs,
        ...
      }: {
        fileSystems = {
          "/boot/firmware" = {
            device = "/dev/disk/by-label/FIRMWARE";
            fsType = "vfat";
            options = [
              "noatime"
              "noauto"
              "x-systemd.automount"
              "x-systemd.idle-timeout=1min"
            ];
          };
          "/" = {
            device = "/dev/disk/by-label/NIXOS_SD";
            fsType = "ext4";
            options = ["noatime"];
          };
        };
      };

      common-user-config = {
        config,
        pkgs,
        ...
      }: {
        imports = [
          ./modules/nice-looking-console.nix
          users-config-stub
          network-config
          meshcoretomqtt-config
        ];

        time.timeZone = "UTC";

        services.udev.extraRules = ''
          # Ignore partitions with "Required Partition" GPT partition attribute
          # On our RPis this is firmware (/boot/firmware) partition
          ENV{ID_PART_ENTRY_SCHEME}=="gpt", \
            ENV{ID_PART_ENTRY_FLAGS}=="0x1", \
            ENV{UDISKS_IGNORE}="1"
        '';

        environment.systemPackages = with pkgs; [
          tree
        ];

        users.users.nixos.openssh.authorizedKeys.keys = [
          "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDHV2grChMteVSJYEfW4mHagZlcyAtTszKd2AfK++/6l5FLpPMdP+Ly8kLP2YO8jc3ThDBxMxhNO/SuALkcS3A/3NkswE/khyqYJFgR5gIbMNwFPerrDc7jEmSzHFIbsGOv73OEjnjiyDklYWHZYl/S5gKMLIKJEP+ou8OmmqAWmhFtd3kpkzkKgt9TMwLqcUvskyA4qzRtG0Sc9ED70lLMsLD2ymbYMDLkZTb4+KPtqJl+RTHaex6zG+WYKSWJ0J+jof4SaeITiIUaTAICx0LFYctEzwKEJ0skoDkhmi5N+UJloOIjvtdH0jNFgeju5rYFCOzmYoqiPdzAxn3Rp1Ffo9qIYDcoSWI0/K+ETw0YymoKlZS7vk4Q7kj+GiLcqCipjiMd+eKvHGdZe/6zP984DDxZo25vHRZ15VhmpEGQn4TmNcaPZTJBvy6S2RHmcnfbna/0KS2WjdEfR04x941iChDxAOi88YisT0SKBi4F8iE+pRdpydd8gdfYRQbFUnk= tilli@zuse-klappi"
        ];
        users.users.root.openssh.authorizedKeys.keys = [
          "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDHV2grChMteVSJYEfW4mHagZlcyAtTszKd2AfK++/6l5FLpPMdP+Ly8kLP2YO8jc3ThDBxMxhNO/SuALkcS3A/3NkswE/khyqYJFgR5gIbMNwFPerrDc7jEmSzHFIbsGOv73OEjnjiyDklYWHZYl/S5gKMLIKJEP+ou8OmmqAWmhFtd3kpkzkKgt9TMwLqcUvskyA4qzRtG0Sc9ED70lLMsLD2ymbYMDLkZTb4+KPtqJl+RTHaex6zG+WYKSWJ0J+jof4SaeITiIUaTAICx0LFYctEzwKEJ0skoDkhmi5N+UJloOIjvtdH0jNFgeju5rYFCOzmYoqiPdzAxn3Rp1Ffo9qIYDcoSWI0/K+ETw0YymoKlZS7vk4Q7kj+GiLcqCipjiMd+eKvHGdZe/6zP984DDxZo25vHRZ15VhmpEGQn4TmNcaPZTJBvy6S2RHmcnfbna/0KS2WjdEfR04x941iChDxAOi88YisT0SKBi4F8iE+pRdpydd8gdfYRQbFUnk= tilli@zuse-klappi"
        ];

        system.nixos.tags = let
          cfg = config.boot.loader.raspberryPi;
        in [
          "raspberry-pi-${cfg.variant}"
          cfg.bootloader
          config.boot.kernelPackages.kernel.version
        ];
      };
    in {
      rpi02 = nixos-raspberrypi.lib.nixosSystemFull {
        specialArgs = inputs;
        modules = [
          ({
            config,
            pkgs,
            lib,
            nixos-raspberrypi,
            ...
          }: {
            imports = with nixos-raspberrypi.nixosModules; [
              # Hardware configuration
              raspberry-pi-02.base
              usb-gadget-ethernet
              # config.txt example
              ./pi02-configtxt.nix
            ];
          })
          # Further user configuration
          common-user-config
          sd-disk-config
          ({
            config,
            pkgs,
            ...
          }: {
            hardware.i2c.enable = true;
            environment.systemPackages = with pkgs; [
              i2c-tools
            ];
          })
        ];
      };
      rpi3 = nixos-raspberrypi.lib.nixosSystem {
        specialArgs = inputs;
        modules = [
          ({
            config,
            pkgs,
            lib,
            nixos-raspberrypi,
            ...
          }: {
            imports = with nixos-raspberrypi.nixosModules; [
              # Hardware configuration
              raspberry-pi-3.base
            ];
          })
          common-user-config
          sd-disk-config
          {
            boot.tmp.useTmpfs = true;
          }
        ];
      };

      rpi4 = nixos-raspberrypi.lib.nixosSystem {
        specialArgs = inputs;
        modules = [
          ({
            config,
            pkgs,
            lib,
            nixos-raspberrypi,
            ...
          }: {
            imports = with nixos-raspberrypi.nixosModules; [
              # Hardware configuration
              raspberry-pi-4.base
            ];
          })
          # Further user configuration
          common-user-config
          sd-disk-config
          {
            boot.tmp.useTmpfs = true;
          }
        ];
      };

      rpi5 = nixos-raspberrypi.lib.nixosSystemFull {
        specialArgs = inputs;
        modules = [
          ({
            config,
            pkgs,
            lib,
            nixos-raspberrypi,
            ...
          }: {
            imports = with nixos-raspberrypi.nixosModules; [
              # Hardware configuration
              raspberry-pi-5.base
              raspberry-pi-5.page-size-16k
              ./pi5-configtxt.nix
              sd-image
            ];
          })
          # Further user configuration
          common-user-config
          sd-disk-config
          {
            boot.tmp.useTmpfs = true;
          }

          # Advanced: Use non-default kernel from kernel-firmware bundle
          ({
            config,
            pkgs,
            lib,
            ...
          }: let
            kernelBundle = pkgs.linuxAndFirmware.v6_6_31;
          in {
            boot = {
              loader.raspberryPi.firmwarePackage = kernelBundle.raspberrypifw;
              loader.raspberryPi.bootloader = "kernel";
              kernelPackages = kernelBundle.linuxPackages_rpi5;
            };

            nixpkgs.overlays = lib.mkAfter [
              (self: super: {
                # This is used in (modulesPath + "/hardware/all-firmware.nix") when at least
                # enableRedistributableFirmware is enabled
                # I know no easier way to override this package
                inherit (kernelBundle) raspberrypiWirelessFirmware;
                # Some derivations want to use it as an input,
                # e.g. raspberrypi-dtbs, omxplayer, sd-image-* modules
                inherit (kernelBundle) raspberrypifw;
              })
            ];
          })
        ];
      };
    };
  };
}
