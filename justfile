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
  java -jar extras/agent.jar \
    -url ${JENKINS_URL} \
    -secret ${SECRET_KEY} \
    -name ${JENKINS_AGENT_NAME} \
    -webSocket \
    -workDir ${JENKINS_AGENT_WORK_DIR}

