#!/bin/sh

## v0.1 - Robert Jan de Groot - initial version (tested on CENTOS 7.6)

## export DEBUG=TRUE to run debug info

### script starts here
BASEDIR=$(dirname "$0")

prereq () {

  if [ ! -f ${BASEDIR}/generic-functions.sh ]; then
    echo "FATAL! Missing generic-functions.sh"
    echo "exiting"
    exit 1
  elif [[ ! -f ${BASEDIR}/environment.properties ]]; then
    echo "FATAL! Missing generic-functions.sh"
    echo "exiting"
    exit 1
  else
    debug "sourcing generic-functions and properties"
    source ${BASEDIR}/generic-functions.sh
    source ${BASEDIR}/environment.properties
  fi

  logfile="/tmp/deploy-post-$(date +%Y%m%d-%H%M%S).log"
  diagfile="/tmp/deploy-post-$(date +%Y%m%d-%H%M%S)-diagnostic.log"

  if [ ! -f ./environment.properties ]; then
    echo "cannot find property file!"
    exit 1
  fi

## check if oc commandline tool is installed
  if [ "$(command -v oc)" == "" ]; then
    echo "the oc command line tool isnt installed!"
    echo "use prepareBastion.sh -c installCLI and rerun this script"
    exit 1
  fi
}

displayHelp () {
  echo "deploy-post created by Robert Jan de Groot"
  echo ""
  echo "run this script without arguments to run all post-deploy actions"
  echo "or specify the command you need, pick from the list below"
  echo "./deploy-cluster-post.sh -c createPV"
  echo "./deploy-cluster-post.sh -c addTemplates"

}

createPV () {

}

addTemplates () {

}


printResult () {
  echo "--------script completed--------"
  echo "you can find the log in: ${logfile}"
  if [ "${DEBUG}" == "TRUE" ]; then
    echo "you can find the debug log in ${diagfile}"
  fi
}

runAll () {
  prereq;
  createPV
  printResult;
}

## if there are no flags, run all.
## otherwise run a specific command

while getopts 'c:h' flag; do
  case "${flag}" in
    c) command="${OPTARG}" ;;
    h) displayHelp;;
    *) echo "unexpected input"; displayHelp ;;
  esac
done

if [ "${command}" != "" ]; then
  prereq;
  ${command};
  printResult;
else
  runAll;
fi
