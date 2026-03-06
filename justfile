# List all the just commands
default:
   @just --list

# Fetch the agent.jar
fetch-agent:
  curl -sO ${AGENT_JAR_URL}
  mkdir -p extras
  mv agent.jar extras/agent.jar

# Start the jenkins agent in foreground
start-agent:
  @echo "Starting Jenkins Agent"
  java -jar ${JENKINS_AGENT_PATH} \
    -url ${JENKINS_URL} \
    -secret ${SECRET_KEY} \
    -name ${JENKINS_AGENT_NAME} \
    -webSocket \
    -workDir ${JENKINS_AGENT_WORK_DIR}

# Read systemctl logs
log:
  journalctl --user -u jenkins-agent -f

# systemctl start
start:
  systemctl --user start jenkins-agent.service

# systemctl stop
stop:
  systemctl --user stop jenkins-agent.service

# systemctl restart
restart:
  systemctl --user restart jenkins-agent.service

# systemctl status
status:
  systemctl --user status jenkins-agent.service

# delete service
delete:
  systemctl --user stop jenkins-agent.service
  systemctl --user disable jenkins-agent.service
  systemctl --user stop jenkins-agent-cleanup.timer
  systemctl --user disable jenkins-agent-cleanup.timer
  rm ~/.config/systemd/user/jenkins-agent.service
  rm ~/.config/systemd/user/jenkins-agent-cleanup.service
  rm ~/.config/systemd/user/jenkins-agent-cleanup.timer
  rm ~/.config/jenkins-agent.env
  rm ~/.config/agent-cleanup.sh
  systemctl --user daemon-reload
  systemctl --user reset-failed
