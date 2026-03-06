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
            ExecStart=${pkgs.openjdk}/bin/java \
              -Xmx4G
              -Dhudson.remoting.Launcher.pingIntervalSec=60 \
              -Dhudson.remoting.Launcher.pingTimeoutSec=120 \
              -Dorg.jenkinsci.remoting.engine.JnlpProtocol3.idleTimeout=600 \
              -jar @JENKINS_AGENT_PATH@ \
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
          agentCleanupScriptTemplate = pkgs.writeShellScriptBin "agent-cleanup" ''
            # 1. Docker Cleanup
            # -a: remove all unused images, not just dangling ones
            # -f: force/don't prompt for confirmation
            # --volumes: remove unused volumes
            echo "Starting Docker cleanup..."
            docker system prune -af --volumes

            # 2. Jenkins Workspace Cleanup
            # Only delete directories older than 7 days to avoid killing active builds
            echo "Cleaning Jenkins workspaces older than 7 days..."
            find "@JENKINS_AGENT_WORK_DIR@/workspace" -mindepth 1 -maxdepth 1 -type d -mtime +7 -exec rm -rf {} +

            echo "Cleanup complete."
          '';
          agentCleanupServiceTemplate = pkgs.writeText "jenkins-agent-cleanup.service" ''
            [Unit]
            Description=Run Docker and Jenkins Workspace Cleanup

            [Service]
            Type=oneshot
            ExecStart=@CLEAN_UP_SCRIPT@

            [Install]
            WantedBy=default.target
          '';
          agentCleanupTimerTemplate = pkgs.writeText "jenkins-agent-cleanup.timer" ''
            [Unit]
            Description=Daily Cleanup of Docker and Jenkins

            [Timer]
            OnCalendar=daily
            # Ensure it runs if the machine was off during the scheduled time
            Persistent=true

            [Install]
            WantedBy=timers.target
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

            cp ${agentCleanupScriptTemplate}/bin/agent-cleanup "$HOME/.config/agent-cleanup.sh"
            sed -i "s|@JENKINS_AGENT_WORK_DIR@|$JENKINS_AGENT_WORK_DIR|g" "$HOME/.config/agent-cleanup.sh"
            chmod +x "$HOME/.config/agent-cleanup.sh"

            cp ${agentCleanupServiceTemplate} "$USER_SYSTEMD_DIR/jenkins-agent-cleanup.service"
            sed -i "s|@CLEAN_UP_SCRIPT@|$HOME/.config/agent-cleanup.sh|g" "$USER_SYSTEMD_DIR/jenkins-agent-cleanup.service"

            cp ${agentCleanupTimerTemplate} "$USER_SYSTEMD_DIR/jenkins-agent-cleanup.timer"

            systemctl --user daemon-reload
            systemctl --user enable jenkins-agent
            systemctl --user restart jenkins-agent
            systemctl --user enable --now jenkins-agent-cleanup.timer

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

