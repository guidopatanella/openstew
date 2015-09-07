#!/bin/sh

set -e

source ./settings.rc
source ./basic-functions.sh

# =============================================================================
# Argument loading and verification
# =============================================================================

 if [ $# -lt 2 ]; then
   echo "ERROR: the following script arguments are required:"
   echo "1) Management IP: the ip address of the management interface e.g. 172.28.128.3"
   echo "2) External Interface Name: the network interface name for the external network. e.g. enp0s8"
   echo "3) Tiers (optional): a space separated list of roles this server will have among the values:"
   echo "    - controller"
   echo "    - compute"
   echo "    - network"
   echo "   when empty, defaults to all: controller compute network"
   echo "Example:"
   echo "./openstew.sh 172.28.128.3 enp0s8"
   echo "For more instructions:"
   echo "https://github.com/guidopatanella/openstew/blob/master/README.md"
   exit 1
 fi

MANAGEMENT_IP=$1
EXTERNAL_INTERFACE_NAME=$2

TIER_CONTROLLER="false"
TIER_COMPUTE="false"
TIER_NETWORK="false"

if [ $# -eq 2 ]; then
  # defaults all tiers (single machine install)
  set_tier "controller"
  set_tier "compute"
  set_tier "network"
else
  # iterate through all arguments and set roles accordingly (the first args are not relevant, but don't hurt)
  for t in "$@"
  do
    echo ${t}
    set_tier ${t}
  done
fi

echo "Installing the following tiers on this node:"
echo " - controller: ${TIER_CONTROLLER}"
echo " - compute: ${TIER_COMPUTE}"
echo " - network: ${TIER_NETWORK}"

#  updates /etc/hosts with references to other nodes in case this server is not
#  including them, considering configuration uses network aliases such as:
#  - SOMEVAR=http://controller:123/blah
set_tier_references

# ==============================================================================
# Base repository and preparation
# ==============================================================================

#  base repositories and utilities
yum install -y epel-release
yum install -y yum-plugin-priorities
yum install -y http://rdo.fedorapeople.org/openstack-juno/rdo-release-juno.rpm

# ==============================================================================
# OS upgrade
# ==============================================================================
yum -y upgrade

# ==============================================================================
# Required tools and utilities
# ==============================================================================
yum install -y openstack-selinux
yum install -y ntp
systemctl enable ntpd.service
systemctl start ntpd.service
# iptables
yum install -y iptables
yum install -y iptables-services
# systemctl enable iptables.service
# systemctl start iptables.service
# used for mysql modal prompt automation
yum install -y expect


# ==============================================================================
# NFS: in some cases this is used to ensure vagrant mounts can get better
# synchronization support
# ==============================================================================
yum install -y nfs-utils nfs-utils-lib
systemctl start  rpcbind.service
systemctl start  nfs.service


if [ ${TIER_CONTROLLER} == "true" ]; then
  source ./os-controller.sh
fi

if [ ${TIER_COMPUTE} == "true" ]; then
  source ./os-compute.sh
fi
