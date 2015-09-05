# Openstew

## Introduction

Openstew is an **Openstack** installer based on installer scripts which deploy a basic single user version of Openstack on a virtual machine and server.

Openstew has the advantages over DevStack:

* faster installation
* not based on screens but on standard restartable system services
* follows the standard installation instructions for the openstack release
* better cross platform support
* possible multi-node deployment

## Supported Versions

* Juno
* Kilo

## Instructions

1. clone this repository
2. select the directory that corresponds to the openstack _flavor_ to be installed
3. select the subdirectory that corresponds to the OS flavor to be installed
4. execute _openstew.sh_

## Vagrant Base Images

For better and easier deployment, it is recommended to use vagrant images.

**notice:** you must update your Vagrantfile to point to the appropriate image name:

Following are some suggested images that can be prepared. The following commands will download an image that can be referenced by the Vagrantfile by its name.

> vagrant box add --name opscode/chef7 http://opscode-vm-bento.s3.amazonaws.com/vagrant/virtualbox/opscode_centos-7.0_chef-provisionerless.box


## References

The installation process is strictly based on the official openstack installation instructions:

Centos / Fedora / RedHad:

  * [Juno](http://docs.openstack.org/juno/install-guide/install/yum/content/)
  * [Kilo](http://docs.openstack.org/kilo/install-guide/install/yum/content/)
