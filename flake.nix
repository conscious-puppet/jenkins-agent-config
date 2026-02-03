{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.11";
    flake-parts.url = "github:hercules-ci/flake-parts";
  };

  outputs =
    inputs@{ self, nixpkgs, flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = nixpkgs.lib.systems.flakeExposed;
      imports = [ ];
      perSystem = { self', system, pkgs, devShells, ... }:
        {
          devShells.default =
            pkgs.stdenv.mkDerivation {
              name = "jenkins-agent-ci";
              buildInputs = with pkgs; [
                openjdk
                just
              ];
            };
        };
    };
}

