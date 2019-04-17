#!/bin/sh

## v0.1 - Robert Jan de Groot - initial version (tested on CENTOS 7.6)
## v0.2 - Robert Jan de Groot - moved generic functions to generic-functions.sh and properties to environment file

## export DEBUG=TRUE to run debug info

### script starts here ###
BASEDIR=$(dirname "$0")

displayHelp () {
  echo "prepareBastion created by Robert Jan de Groot"
  echo ""
  echo "run this script without arguments to run all Bastion Installation actions"
  echo "or specify the command you need, pick from the list below"
  echo ""
  echo "installPackages"
  echo "installNFS"
  echo "mountDisk"
  echo "exposeNFS"
  echo "generateKey"
  echo "installEPEL"
  echo "getAnsibleScripts"
  echo "installCLI"
  echo ""
  echo "e.g."
  echo "./prepareBastion.sh -c installNFS"
  exit 0
}

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

logfile="/tmp/prepareNode-$(date +%Y%m%d-%H%M%S).log"
diagfile="/tmp/prepareNode-$(date +%Y%m%d-%H%M%S)-diagnostic.log"

if [ "$(whoami)" = "root" ]; then
  prefix=""
  debug "user is root"
else
  prefix="sudo"
  debug "user is not root"
  id=$(id)
  if [ $(echo ${id}|grep -c wheel) -eq 0 ]; then
    echo "you are not root and you're not in the wheel group"
    echo "not enought privileges!"
    exit 1
  fi
fi

debug "prefix set to ${prefix}"

if [ ! -f ${BASEDIR}/package.lst ]; then
  echo "cannot find property file!"
  exit 1
fi

}

installPackages () {
cat ${BASEDIR}/package.lst | grep -v '#'| while read package
do
  echo "installing ${package}"
  ${prefix} yum -y install ${package}
  verifyCommand "installing ${package}"
done

}

installNFS () {
  echo "opening firewall"
  ${prefix} systemctl start firewalld.service
  ${prefix} systemctl enable firewalld.service

  ${prefix} firewall-cmd --permanent --zone=public --add-service=ssh
  ${prefix} firewall-cmd --permanent --zone=public --add-service=nfs
  ${prefix} firewall-cmd --permanent --zone=public --add-service=mountd
  ${prefix} firewall-cmd --permanent --zone=public --add-service=rpc-bind
  verifyCommand "adding nfs to firewall"
  ${prefix} firewall-cmd --reload

  echo "installing NFS"
  ${prefix} systemctl start rpcbind
  verifyCommand "starting RPC bind"
  ${prefix} systemctl enable rpcbind
  ${prefix} systemctl enable nfs-server
  ${prefix} systemctl enable nfs-lock
  ${prefix} systemctl enable nfs-idmap

}

mountDisk () {
  ## this contains a dangerous assumption that the empty docker disk is the last one in lsblk
  disk=`lsblk -p | tail -n 1 | awk '{ print $1 }'`
  debug "disk set to ${disk}"
  if [ $(df -h | grep ${nfsDir} | wc -l) -gt 0 ]; then
    echo "disk already mounted, nothing to do"
  else
    ${prefix} mkdir -p ${nfsDir}

    sed -e 's/\s*\([\+0-9a-zA-Z]*\).*/\1/' << EOF | ${prefix} fdisk ${disk}
    n # new partition
    p # primary partition
    1 # partition number 1
 # default initial
 # default end
    p # print the in-memory partition table
    w # write the partition table
    q # and we're done
EOF
    verifyCommand "creating partition"
    diskPart=`${prefix} fdisk -l | tail -n 1 | awk '{print $1 }`
    debug "formatting disk ${diskPart}"
    ${prefix} mkfs.xfs ${diskPart}
    verifyCommand "formatting partition ${diskPart}"
    UUID=$(${prefix} blkid ${diskPart} | awk '{ print $2 }' | sed -e 's/"//g')
    debug "uuid set to ${UUID}"
    echo "${UUID} ${nfsDir} xfs defaults 0 0" | ${prefix} tee --append /etc/fstab
    verifyCommand "adding disk to fstab"
    ${prefix} mount ${nfsDir}
    verifyCommand "mounting disk to ${nfsDir}"
  fi

  ${prefix} chown ${wheelUser} ${nfsDir}
}

exposeNFS () {
  debug "adding ${nfsDir} on subnet ${subnet}"
   echo "${nfsDir} ${subnet}(rw,sync,no_root_squash)" | ${prefix} tee --append /etc/exports
   verifyCommand "adding nfs share to /etc/exports"

   ${prefix} systemctl start nfs-server
   verifyCommand "starting nfs server"
   ${prefix} systemctl start nfs-lock
   ${prefix} systemctl start nfs-idmap
}

generateKey () {
  if [ ! -d ~/.ssh ]; then
    mkdir ~/.ssh
  fi

  cd ~/.ssh
  ssh-keygen -t rsa -N "" -f cloudformationKey
  verifyCommand "creation of keypair"

  if [ -d ${nfsDir} ]; then
    mkdir ${nfsDir}/keys
    verifyCommand "creation of key folder"
    cp ./cloudformationKey.pub ${nfsDir}/keys/
  else
    echo "Warning, no dir found: ${nfsDir}"
  fi

}

installEPEL () {

  ${prefix} yum -y install https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm
  verifyCommand "setting up the EPEL release"
  ${prefix} sed -i -e "s/^enabled=1/enabled=0/" /etc/yum.repos.d/epel.repo
  verifyCommand "disabling the EPEL repo"
  ${prefix} yum -y --enablerepo=epel install ansible pyOpenSSL
  verifyCommand "installing Ansible"
}

getAnsibleScripts () {
  echo "openshiftRelease set to ${openshiftRelease}"
  cd ~
  git clone https://github.com/openshift/openshift-ansible
  verifyCommand "clone ansible git"
  cd openshift-ansible
  git checkout ${openshiftRelease}
  verifyCommand "switching to ${openshiftRelease} branch"
}

installCLI () {
  if [ "$(command -v oc)" == "" ]; then
    echo "installing OC client"
    mkdir /tmp/cli
    wget -O /tmp/oc-client.tar.gz ${cli}
    tar --wildcards -C /tmp/cli -zxvf /tmp/oc-client.tar.gz openshift-origin-client-tools*/oc
    verifyCommand "downloading cli"
    ${prefix} cp /tmp/cli/openshift-origin-client-tools*/oc /usr/local/bin/
    verifyCommand "adding CLI to PATH"
  else
    echo "oc cli already installed"
  fi
}

runAll () {
  prereq;
  installPackages;
  installNFS;
  mountDisk;
  exposeNFS;
  generateKey;
  installEPEL;
  getAnsibleScripts;
  installCLI;
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
