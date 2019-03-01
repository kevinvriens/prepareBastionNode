#!/bin/sh

## v0.1 - Robert Jan de Groot - initial version (tested on CENTOS 7.6)


# set your openshift branch here
# this should match the branch name on https://github.com/openshift/openshift-ansible
openshiftRelease="release-3.11"
nfsDir="/export/nfs"
wheelUser="centos"
subnet="10.0.21.0/24"

## export DEBUG=TRUE to run debug info
debug () {
message=$1
if [ "${DEBUG}" = "TRUE" ]; then
  echo "  [DEBUG] ${message}" | tee --append ${diagfile}
fi
}


prereq () {

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

if [ ! -f ./package.lst ]; then
  echo "cannot find property file!"
  exit 1
fi

}

verifyCommand () {
lastExit=$?
command=$1
if [ ${lastExit} -eq 0 ]; then
  echo "${command} succeeded" | tee --append ${logfile}
else
  echo "${command} failed!" | tee --append ${logfile}
  exit 1
fi

}

installPackages () {
cat ./package.lst | grep -v '#'| while read package
do
  echo "installing ${package}"
  ${prefix} yum -y install ${package}
  verifyCommand "installing ${package}"
done

}

installNFS () {
  echo "opening firewall"
  ${prefix} firewall-cmd --permanent --zone=public --add-service=ssh
  ${prefix} firewall-cmd --permanent --zone=public --add-service=nfs
  verifyCommand "adding nfs to firewall"
  ${prefix} firewall-cmd --reload

  echo "installing NFS"
  ${prefix} systemctl start rpcbind
  verifyCommand "starting RPC bind"
  ${prefix} systemctl enable rpcbind
  ${prefix} systemctl enable nfs-server

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

    debug "formatting disk ${disk}1"
    ${prefix} mkfs.xfs ${disk}1
    verifyCommand "formatting partition ${disk}1"
    UUID=$(${prefix} blkid ${disk}1 | awk '{ print $2 }' | sed -e 's/"//g')
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

   ${prefix} systemctl enable nfs-server
   verifyCommand "starting nfs server"
}

generateKey () {
  if [ ! -d ~/.ssh ]; then
    mkdir ~/.ssh
  fi

  cd ~/.ssh
  ssh-keygen -t rsa -N "" -f cloudformationKey
  verifyCommand "creation of keypair"
  mkdir ${nfsDir}/keys
  verifyCommand "creation of key folder"
  cp ./cloudformationKey.pub ${nfsDir}/keys/

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

printResult () {
  echo "--------script completed--------"
  echo "you can find the log in: ${logfile}"
  if [ "${DEBUG}" == "TRUE" ]; then
    echo "you can find the debug log in ${diagfile}"
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
  printResult;
}

runAll;
