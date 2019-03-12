#!/bin/sh

## v0.1 - Robert Jan de Groot - initial version (tested on CENTOS 7.6)

## export DEBUG=TRUE to run debug info

### script starts here
BASEDIR=$(dirname "$0")
stageDir="/tmp/deploy-cluster-post-$(date +%s)"

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
    source ${BASEDIR}/generic-functions.sh
    source ${BASEDIR}/environment.properties
    debug "sourced generic-functions and properties"
  fi

  logfile="/tmp/deploy-post-$(date +%Y%m%d-%H%M%S).log"
  diagfile="/tmp/deploy-post-$(date +%Y%m%d-%H%M%S)-diagnostic.log"

  if [ ! -f ${BASEDIR}/environment.properties ]; then
    echo "cannot find property file!"
    exit 1
  fi

## check if oc commandline tool is installed
  if [ "$(command -v oc)" == "" ]; then
    echo "the oc command line tool isnt installed!"
    echo "use prepareBastion.sh -c installCLI and rerun this script"
    exit 1
  fi

  mkdir ${stageDir}
}

displayHelp () {
  echo "deploy-post created by Robert Jan de Groot"
  echo ""
  echo "run this script without arguments to run all post-deploy actions"
  echo "or specify the command you need, pick from the list below"
  echo "./deploy-cluster-post.sh -c createPV"
  echo "./deploy-cluster-post.sh -c addTemplates"
  echo "./deploy-cluster-post.sh -c addRBAC"
  exit 0

}

addRBAC () {
  user=$1
  if [ -z ${user} ]; then
    user=admin
  fi
debug "user set to ${user}"

## add admin rback roles to user admin
oc login ${masterURL} --token=${token}
oc create clusterrolebinding registry-controller --clusterrole=cluster-admin --user=${user}
verifyCommand "setting RBAC roles for user ${user}"
}

createPV () {
  if [ ! -f ${BASEDIR}/templates/create-pv-template.yml ]; then
    echo "cannot find property file!"
    exit 1
  else
    debug "copying pv-template to stage ${stageDir}"
    cp ${BASEDIR}/templates/create-pv-template.yml ${stageDir}/

    pvName="pv001"
    debug "setting name to ${pvName}"
    sed -i "s|__name__|${pvName}|g" ${stageDir}/create-pv-template.yml

    pvCapacity="1Gi"
    debug "setting capacity to ${pvCapacity}"
    sed -i "s|__capacity__|${pvCapacity}|g" ${stageDir}/create-pv-template.yml

    pvPath="/mnt/nfs/${pvName}"
    debug "setting path to ${pvPath}"
    sed -i "s|__path__|${pvPath}|g" ${stageDir}/create-pv-template.yml

    ## create the subfolder on the NFS server if needed
    if [ ! -d ${nfsDir}/${pvName} ]; then
      mkdir ${nfsDir}/${pvName}
    fi

    ## get the bastion current ip
    currentIP=$(hostname --ip-address)
    debug "setting server to ${currentIP}"
    sed -i "s|__server__|${currentIP}|g" ${stageDir}/create-pv-template.yml
    verifyCommand "updating pv template"

    debug "logging in "
    oc login ${masterURL} --token=${token}
    oc create -f ${stageDir}/create-pv-template.yml
    verifyCommand "creating pv ${pvName}"
  fi


}

addTemplates () {
echo "not finished"
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
  addRBAC;
  createPV;
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
