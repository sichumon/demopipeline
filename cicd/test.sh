#!/usr/bin/env bash
 
## shell options
set -e
set -u
set -f
 
## magic variables
declare CLUSTER
declare TASK
declare TEST_URL
declare -r -i SUCCESS=0
declare -r -i NO_ARGS=85
declare -r -i BAD_ARGS=86
declare -r -i MISSING_ARGS=87
 
## script functions
function usage() {
  local FILE_NAME
 
  FILE_NAME=$(basename "$0")
 
  printf "Usage: %s [options...]\n" "$FILE_NAME"
  printf " -h\tprint help\n"
  printf " -c\tset esc cluster name uri\n"
  printf " -t\tset esc task name\n"
}
 
function no_args() {
  printf "Error: No arguments were passed\n"
  usage
  exit "$NO_ARGS"
}
 
function bad_args() {
  printf "Error: Wrong arguments supplied\n"
  usage
  exit "$BAD_ARGS"
}
 
function missing_args() {
  printf "Error: Missing argument for: %s\n" "$1"
  usage
  exit "$MISSING_ARGS"
}
 
function get_test_url() {
  local TASK_ARN
  local TASK_ID
  local STATUS
  local HOST_PORT
  local CONTAINER_ARN
  local CONTAINER_ID
  local INSTANCE_ID
  local PUBLIC_IP
 
  # list running task
  TASK_ARN="$(aws ecs list-tasks --cluster "$CLUSTER" --desired-status RUNNING --family "$TASK" | jq -r .taskArns[0])"
  TASK_ID="${TASK_ARN#*:task/}"
 
  # wait for specific container status
  STATUS="PENDING"
  while [ "$STATUS" != "RUNNING" ]; do
    STATUS="$(aws ecs describe-tasks --cluster "$CLUSTER" --task "$TASK_ID" | jq -r .tasks[0].containers[0].lastStatus)"
  done
 
  # get container id
  CONTAINER_ARN="$(aws ecs describe-tasks --cluster "$CLUSTER" --tasks "$TASK_ID" | jq -r .tasks[0].containerInstanceArn)"
  CONTAINER_ID="${CONTAINER_ARN#*:container-instance/}"
 
  # get host port
  HOST_PORT="$(aws ecs describe-tasks --cluster "$CLUSTER" --tasks "$TASK_ID" | jq -r .tasks[0].containers[0].networkBindings[0].hostPort)"
 
  # get instance id
  INSTANCE_ID="$(aws ecs describe-container-instances --cluster "$CLUSTER" --container-instances "$CONTAINER_ID" | jq -r .containerInstances[0].ec2InstanceId)"
 
  # get public IP
  PUBLIC_IP="$(aws ec2 describe-instances --instance-ids "$INSTANCE_ID" | jq -r .Reservations[0].Instances[0].PublicIpAddress)"
 
  TEST_URL="$(printf "http://%s:%d" "$PUBLIC_IP" "$HOST_PORT")"
}
 
function clean_up() {
  # stop container
  if [ "$(docker inspect -f {{.State.Running}} ChromeBrowser)" == "true" ]; then
    docker rm -f ChromeBrowser
  fi
 
  # delete virtualenv
  if [ -d .env ]; then
    rm -fr .env
  fi
}
 
function run_selenium_test() {
  local TEST_TEMPLATE
  local TEST_FILE
 
  # clean up
  clean_up
 
  # pull image (standalone-chrome)
  docker pull selenium/standalone-chrome
 
  # run docker container (standalone-chrome)
  docker run -d -p 4444:4444 --name ChromeBrowser selenium/standalone-chrome
 
  # create and activate virtualenv
  virtualenv .env && source .env/bin/activate
 
  # install Selenium
  pip install -U selenium
 
  # read test template into variable
  TEST_TEMPLATE=$(cat ./test/example.py)
 
  # replace string with URL
  TEST_FILE="${TEST_TEMPLATE/APPLICATION_URL/$TEST_URL}"
 
  # save into final test file
  echo "$TEST_FILE" > ./test/suite.py
 
  # execute test
  python -B ./test/suite.py
 
  # deactivate virtualenv
  deactivate
}
 
## check script arguments
while getopts "hc:t:" OPTION; do
  case "$OPTION" in
    h) usage
       exit "$SUCCESS";;
    c) CLUSTER="$OPTARG";;
    t) TASK="$OPTARG";;
    *) bad_args;;
  esac
done
 
if [ "$OPTIND" -eq 1 ]; then
  no_args
fi
 
if [ -z "$CLUSTER" ]; then
  missing_args '-c'
fi
 
if [ -z "$TASK" ]; then
  missing_args '-t'
fi
 
## run main function
function main() {
  get_test_url
  printf "Test Application URL: %s\n" "$TEST_URL"
 
  run_selenium_test
}
 
main
 
# exit
exit "$SUCCESS"
