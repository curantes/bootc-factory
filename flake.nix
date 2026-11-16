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
    in
    {
      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShellNoCC {
          # podman is taken from the host: builds run rootful (`sudo podman`),
          # which needs the distribution's podman/conmon/crun setup.
          packages = with pkgs; [
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
          ];
          shellHook = ''
            command -v podman >/dev/null || echo "warning: podman not found on the host"
            command -v bcvk >/dev/null || echo "note: bcvk not installed; 'just boot-test' / 'just vm' unavailable"
          '';
        };
      });

      formatter = forAllSystems (pkgs: pkgs.nixfmt-rfc-style);
    };
}
