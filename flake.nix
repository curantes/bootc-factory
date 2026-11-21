{
  description = "bootc-factory developer shell";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { nixpkgs, ... }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});

      # bcvk for boot tests: the release CI uses, with the same checksum, read
      # from scripts/ci-setup.sh (Renovate updates it there). Kept as the
      # unpatched upstream binary: bcvk bind-mounts itself into the VM
      # container, where /nix/store does not exist.
      bcvkFor =
        pkgs:
        let
          inherit (pkgs) lib;
          lines = lib.splitString "\n" (builtins.readFile ./scripts/ci-setup.sh);
          pin =
            name:
            lib.removePrefix "${name}=" (
              lib.findFirst (lib.hasPrefix "${name}=") (throw "scripts/ci-setup.sh: no ${name}") lines
            );
          tag = pin "BCVK_VERSION";
        in
        pkgs.stdenvNoCC.mkDerivation {
          pname = "bcvk";
          version = lib.removePrefix "v" tag;
          src = pkgs.fetchurl {
            url = "https://github.com/bootc-dev/bcvk/releases/download/${tag}/bcvk-x86_64-unknown-linux-gnu.tar.gz";
            sha256 = pin "BCVK_SHA256_X86_64";
          };
          sourceRoot = ".";
          dontConfigure = true;
          dontBuild = true;
          dontFixup = true; # no patchelf/strip: see above
          installPhase = "install -Dm755 bcvk-x86_64-unknown-linux-gnu $out/bin/bcvk";
          meta.platforms = [ "x86_64-linux" ];
        };
    in
    {
      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShellNoCC {
          # podman is taken from the host: builds run rootful (`sudo podman`),
          # which needs the distribution's podman/conmon/crun setup.
          packages =
            with pkgs;
            [
              just
              jq
              yq-go
              python3
              skopeo
              cosign # local `just dev-key` only; CI pins cosign 2.x for signing
              gh # scripts/setup-wizard.sh
              shellcheck
              actionlint
              zizmor
            ]
            ++ pkgs.lib.optional (pkgs.stdenv.hostPlatform.system == "x86_64-linux") (bcvkFor pkgs);
          # QEMU and virtiofsd must come from the host: bcvk mounts the host's
          # /usr into the container that runs them.
          shellHook = ''
            command -v podman >/dev/null || echo "warning: podman not found on the host"
            [ -x /usr/bin/qemu-system-x86_64 ] ||
              echo "note: boot tests need host QEMU + virtiofsd: sudo apt install qemu-system-x86 qemu-utils virtiofsd"
          '';
        };
      });

      formatter = forAllSystems (pkgs: pkgs.nixfmt-rfc-style);
    };
}
