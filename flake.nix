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
        let
          serviceTemplate = pkgs.writeText "jenkins-agent.service" ''
            [Unit]
            Description=Jenkins Agent (Configured via .envrc)
            After=network.target

            [Service]
            Type=simple
            EnvironmentFile=%h/.config/jenkins-agent.env
            WorkingDirectory=@JENKINS_AGENT_WORK_DIR@
            ExecStart=${pkgs.openjdk}/bin/java -jar @JENKINS_AGENT_PATH@ \
              -url @JENKINS_URL@ \
              -secret @SECRET_KEY@ \
              -name @JENKINS_AGENT_NAME@ \
              -webSocket \
              -workDir @JENKINS_AGENT_WORK_DIR@
            Restart=always
            RestartSec=10

            [Install]
            WantedBy=default.target
          '';
          installAgent = pkgs.writeShellScriptBin "install-agent" ''
            echo "Syncing .envrc to systemd environment..."

            USER_SYSTEMD_DIR="$HOME/.config/systemd/user"
            mkdir -p "$USER_SYSTEMD_DIR"

            cp ${serviceTemplate} "$USER_SYSTEMD_DIR/jenkins-agent.service"

            sed -i "s|@JENKINS_AGENT_WORK_DIR@|$JENKINS_AGENT_WORK_DIR|g" "$USER_SYSTEMD_DIR/jenkins-agent.service"
            sed -i "s|@JENKINS_AGENT_PATH@|$JENKINS_AGENT_PATH|g" "$USER_SYSTEMD_DIR/jenkins-agent.service"
            sed -i "s|@JENKINS_URL@|$JENKINS_URL|g" "$USER_SYSTEMD_DIR/jenkins-agent.service"
            sed -i "s|@SECRET_KEY@|$SECRET_KEY|g" "$USER_SYSTEMD_DIR/jenkins-agent.service"
            sed -i "s|@JENKINS_AGENT_NAME@|$JENKINS_AGENT_NAME|g" "$USER_SYSTEMD_DIR/jenkins-agent.service"

            echo "PATH=$PATH" > "$HOME/.config/jenkins-agent.env"

            systemctl --user daemon-reload
            systemctl --user enable jenkins-agent
            systemctl --user restart jenkins-agent

            echo "Agent started using variables from your devshell!"
          '';
        in
        {

          apps.default = {
            type = "app";
            program = "${installAgent}/bin/install-agent";
          };

          devShells.default =
            pkgs.stdenv.mkDerivation {
              name = "jenkins-agent-ci";
              buildInputs = with pkgs; [
                openjdk
                just
                awscli2
                trivy
              ];
            };
        };
    };
}

