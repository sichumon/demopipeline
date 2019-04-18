#!/usr/bin/env bash

## shell options
set -e
set -u
set -f

## magic variables
declare ECR
declare CLUSTER
declare TASK
declare BUILD_NUMBER
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
  printf " -e\tset ecr repository uri\n"
  printf " -c\tset esc cluster name uri\n"
  printf " -t\tset esc task name\n"
  printf " -b\tset build number\n "
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

## check script arguments
while getopts "he:c:t:b:" OPTION; do
  case "$OPTION" in
    h) usage
       exit "$SUCCESS";;
    e) ECR="$OPTARG";;
    c) CLUSTER="$OPTARG";;
    t) TASK="$OPTARG";;
    b) BUILD_NUMBER="$OPTARG";;
    *) bad_args;;
  esac
done

if [ "$OPTIND" -eq 1 ]; then
  no_args
fi

if [ -z "$ECR" ]; then
  missing_args '-e'
fi

if [ -z "$CLUSTER" ]; then
  missing_args '-c'
fi

if [ -z "$TASK" ]; then
  missing_args '-t'
fi

if [ -z "$BUILD_NUMBER" ]; then
  missing_args '-b'
fi

## run main function
function main() {
  local TASK_ARN
  local TASK_ID
  local ACTIVE_TASK_DEF
  local TASK_DEFINITION
  local TASK_DEF_ARN

  # list running task
  TASK_ARN="$(aws ecs list-tasks --cluster "$CLUSTER" --desired-status RUNNING --family "$TASK" | jq -r .taskArns[0])"
  TASK_ID="${TASK_ARN#*:task/}"

  # stop running task
  if [ -n "$TASK_ID" ] && [ "$TASK_ID" != "null" ]; then
    printf "INFO: Stop Task %s\n" "$TASK_ID"
    aws ecs stop-task --cluster "$CLUSTER" --task "$TASK_ID"
  fi

  # list active task definition
  ACTIVE_TASK_DEF="$(aws ecs list-task-definitions --family-prefix "$TASK" --status ACTIVE | jq -r .taskDefinitionArns[0])"

  # derigister task definition
  if [ -n "$ACTIVE_TASK_DEF" ]; then
    printf "INFO: Deregister Task Definition %s\n" "$ACTIVE_TASK_DEF"
    aws ecs deregister-task-definition --task-definition "$ACTIVE_TASK_DEF"
  fi

  # read task definition template
  TASK_DEFINITION=$(cat ./cicd/task_definition.json)

  # create new task definition file
  TASK_DEFINITION="${TASK_DEFINITION/URI/$ECR}"
  echo "${TASK_DEFINITION/NUMBER/$BUILD_NUMBER}" > ecs_task_definition.json

  # register new task definition
  TASK_DEF_ARN="$(aws ecs register-task-definition --cli-input-json file://ecs_task_definition.json | jq -r .taskDefinition.taskDefinitionArn)"

  # run task by task definition
  aws ecs run-task --task-definition "$TASK_DEF_ARN" --cluster "$CLUSTER"
}

main

# exit
exit "$SUCCESS"
