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

  ## todo: this is a bad solution, to grab the first host after the [masters] section in the ansible inventory file
  master=$(grep -A1 "masters" /etc/ansible/hosts | tail -n 1 | cut -f 1 -d ' ')
  debug "master node set to ${master}"
  if [ -z "${master}" ]; then
    echo "no master host found in /etc/ansible/hosts !"
    exit 1
  fi
  }
}

displayHelp () {
  echo "deploy-post created by Robert Jan de Groot"
  echo ""
  echo "run this script without arguments to run all post-deploy actions"
  echo "or specify the command you need, pick from the list below"
  echo "./deploy-cluster-post.sh -c createPV -n pv001 -s 1Gi"
  echo "./deploy-cluster-post.sh -c addTemplates"
  echo "./deploy-cluster-post.sh -c addRBAC"
  exit 0

}

remoteOC () {
  command=${1}
  ssh -i ~/.ssh/id_rsa ${master} ${command}
}

copyStage () {
  scp -rp -i ~/.ssh/id_rsa ${stageDir} ${master}:${stageDir}
  verifyCommand "transfer of stagedir"
}

addRBAC () {
  user=$1
  if [ -z ${user} ]; then
    user=admin
  fi
debug "user set to ${user}"

remoteOC "oc create clusterrolebinding registry-controller --clusterrole=cluster-admin --user=${user}"
verifyCommand "setting RBAC roles for user ${user}"
}

createPV () {
  if [ ! -f ${BASEDIR}/templates/create-pv-template.yml ]; then
    echo "cannot find property file!"
    exit 1
  else
    debug "copying pv-template to stage ${stageDir}"
    cp ${BASEDIR}/templates/create-pv-template.yml ${stageDir}/

    if [ -z ${nflag} ]; then
      ## use default name if nothing is set
      pvName="pv001"
    fi
    debug "setting name to ${pvName}"
    sed -i "s|__name__|${pvName}|g" ${stageDir}/create-pv-template.yml

    if [ -z ${sflag} ]; then
      ## use default size if nothing is set
      pvCapacity="1Gi"
    fi

    debug "setting capacity to ${pvCapacity}"
    sed -i "s|__capacity__|${pvCapacity}|g" ${stageDir}/create-pv-template.yml

    pvPath="${nfsDir}/${pvName}"
    debug "setting path to ${pvPath}"
    sed -i "s|__path__|${pvPath}|g" ${stageDir}/create-pv-template.yml

    ## create the subfolder on the NFS server if needed
    if [ ! -d ${nfsDir}/${pvName} ]; then
      mkdir ${nfsDir}/${pvName}
      chmod 777 ${nfsDir}/${pvName}
    fi

    if [ "${oflag}" == "true" ]; then
      ## use the given servername
      debug "setting server to ${pvServer}"
      sed -i "s|__server__|${pvServer}|g" ${stageDir}/create-pv-template.yml
      verifyCommand "setting given IP ${pvServer} in pv template"
    else
      ## get the bastion current ip
      currentIP=$(hostname --ip-address)
      debug "setting server to ${currentIP}"
      sed -i "s|__server__|${currentIP}|g" ${stageDir}/create-pv-template.yml
      verifyCommand "setting local IP in pv template"
    fi

    debug "copying stage dir"
    ## put our template file on the master node
    copyStage;
    remoteOC "oc create -f ${stageDir}/create-pv-template.yml"
    verifyCommand "creating pv ${pvName}"
  fi


}

addTemplates () {
  cp ${BASEDIR}/templates/FISimageStreams.sh ${stageDir}
  cp ${BASEDIR}/templates/addFuseTemplates.sh ${stageDir}
  copyStage;

  remoteOC "${stageDir}/FISimageStreams.sh"
  verifyCommand "preparing image streams"

  remoteOC "${stageDir}/addFuseTemplates.sh"
  verifyCommand "adding templates"

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
  addTemplates
  printResult;
}

sflag=''
nflag=''
oflag=''

## if there are no flags, run all.
## otherwise run a specific command

while getopts 'c:hs:n:o:' flag; do
  case "${flag}" in
    c) command="${OPTARG}" ;;
    h) displayHelp;;
    s) sflag=true; pvCapacity=${OPTARG} ;;
    n) nflag=true; pvName=${OPTARG} ;;
    o) oflag=true; pvServer=${OPTARG} ;;
    *) echo "ERROR! unexpected input!"; echo ""; displayHelp ;;
  esac
done

if [ "${command}" != "" ]; then
  prereq;
  ${command};
  printResult;
else
  runAll;
fi
