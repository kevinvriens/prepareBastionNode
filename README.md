# prepareBastionNode
Used to get an AWS instance to our openshift bastion level

### Usage:

To install all components on the AWS Bastion node (for an openshift cluster)
```
./prepareBastion.sh
```

this will execute the following sub commands:
* installPackages  (installs all package in packages.lst)
* installNFS       (sets up nfs server including firewall)
* mountDisk        (mounts a second AWS block device for NFS)
* exposeNFS        (set the /etc/export file)
* generateKey      (generate a key for AWS cluster)
* installEPEL      (add the EPEL release for Ansible)
* getAnsibleScripts (gets the OC installation repository based on the specified version)
* installCLI         (installs the OC commandline)

you can run these steps individually by running:
```
./prepareBastion.sh -c <subcommand>
```

### after you installed the openshift cluster

use the following script to post-configure your openshift cluster
```
./deploy-cluster-post.sh
```

This will execute the following sub commands:
* addRBAC (add the admin user to the cluster-admin RBAC role)
* createPV (create a PV called 'pv001' with 1Gi as physical volume)
* addTemplates (adds all JBoss Fuse templates to the catalog)

```
./deploy-cluster-post.sh -c <subcommand> (optionally add -s xGi -n pv002 to add Physical Volumes)
```
