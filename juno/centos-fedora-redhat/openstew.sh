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
# used for mysql modal prompt automation
yum install -y expect


# ==============================================================================
# NFS: in some cases this is used to ensure vagrant mounts can get better
# synchronization support
# ==============================================================================
yum install -y nfs-utils nfs-utils-lib
systemctl start  rpcbind.service
systemctl start  nfs.service

# ==============================================================================
# MYSQL DATABASE
# ==============================================================================
yum install -y mariadb mariadb-server MySQL-python
systemctl enable mariadb.service
systemctl start mariadb.service
# set MYSQL password
expect ./mysql.expected
# create ahead all database schemas at once
mysql -u root -p${MYSQL_ROOT} -A -e "source ./schemas.sql;"

# ==============================================================================
# Message Queue: RabbitMQ
# ==============================================================================
yum install -y rabbitmq-server
systemctl enable rabbitmq-server.service
systemctl start rabbitmq-server.service
rabbitmqctl change_password guest ${RABBIT_PASS}
systemctl restart rabbitmq-server.service

# ==============================================================================
# Keystone
# ==============================================================================

yum install -y openstack-keystone python-keystoneclient
# update configuration
mv /etc/keystone/keystone.conf /etc/keystone/keystone.conf.original
echo "[DEFAULT]" > /etc/keystone/keystone.conf
echo "admin_token = ${KEYSTONE_ADMIN_TOKEN}" >> /etc/keystone/keystone.conf
echo "[database]" >> /etc/keystone/keystone.conf
echo "connection = mysql://keystone:${KEYSTONE_DBPASS}@controller/keystone" >> /etc/keystone/keystone.conf
echo "[token]" >> /etc/keystone/keystone.conf
echo "provider = keystone.token.providers.uuid.Provider" >> /etc/keystone/keystone.conf
echo "driver = keystone.token.persistence.backends.sql.Token" >> /etc/keystone/keystone.conf
echo "[revoke]" >> /etc/keystone/keystone.conf
echo "driver = keystone.contrib.revoke.backends.sql.Revoke" >> /etc/keystone/keystone.conf

keystone-manage pki_setup --keystone-user keystone --keystone-group keystone
chown -R keystone:keystone /var/log/keystone
chown -R keystone:keystone /etc/keystone/ssl
chmod -R o-rwx /etc/keystone/ssl

su -s /bin/sh -c "keystone-manage db_sync" keystone

systemctl enable openstack-keystone.service
systemctl start openstack-keystone.service


# Keystone related openstack user identities
keystone tenant-create --name admin --description "Admin Tenant"
keystone user-create --name admin --pass ${ADMIN_PASS}
keystone role-create --name admin
keystone user-role-add --user admin --tenant admin --role admin
keystone tenant-create --name demo --description "Demo Tenant"
keystone user-create --name demo --tenant demo --pass ${DEMO_PASS}
keystone tenant-create --name service --description "Service Tenant"

#  keystone service endpoint creation
keystone service-create --name keystone --type identity --description "OpenStack Identity"
keystone endpoint-create \
  --service-id $(keystone service-list | awk '/ identity / {print $2}') \
  --publicurl http://controller:5000/v2.0 \
  --internalurl http://controller:5000/v2.0 \
  --adminurl http://controller:35357/v2.0 \
  --region regionOne


# ==============================================================================
# RC environment files for administrative and demo users ( CLI use only )
# ==============================================================================

echo "export OS_TENANT_NAME=admin" > /root/adminrc
echo "export OS_USERNAME=admin" >> /root/adminrc
echo "export OS_PASSWORD=${ADMIN_PASS}" >> /root/adminrc
echo "export OS_AUTH_URL=http://controller:35357/v2.0" >> /root/adminrc

echo "export OS_TENANT_NAME=demo" > /root/demorc
echo "export OS_USERNAME=demo" >> /root/demorc
echo "export OS_PASSWORD=${DEMO_PASS}" >> /root/demorc
echo "export OS_AUTH_URL=http://controller:35357/v2.0" >> /root/demorc

unset OS_SERVICE_TOKEN
unset OS_SERVICE_ENDPOINT
source /root/adminrc

# ==============================================================================
# Openstack Glance - image store
# ==============================================================================

keystone user-create --name glance --pass ${GLANCE_PASS}
keystone user-role-add --user glance --tenant service --role admin
keystone service-create --name glance --type image  --description "OpenStack Image Service"
keystone endpoint-create \
  --service-id $(keystone service-list | awk '/ image / {print $2}') \
  --publicurl http://controller:9292 \
  --internalurl http://controller:9292 \
  --adminurl http://controller:9292 \
  --region regionOne

yum install -y openstack-glance python-glanceclient

# update configuration
mv /etc/glance/glance-api.conf /etc/glance/glance-api.conf.original
mv /etc/glance/glance-registry.conf /etc/glance/glance-registry.conf.original
echo "[DEFAULT]" > /etc/glance/glance-api.conf
echo "notification_driver = noop" >> /etc/glance/glance-api.conf
echo "[database]" >> /etc/glance/glance-api.conf
echo "connection = mysql://glance:${GLANCE_DBPASS}@controller/glance" >> /etc/glance/glance-api.conf
echo "[keystone_authtoken]" >> /etc/glance/glance-api.conf
echo "auth_uri = http://controller:5000/v2.0" >> /etc/glance/glance-api.conf
echo "identity_uri = http://controller:35357" >> /etc/glance/glance-api.conf
echo "admin_tenant_name = service" >> /etc/glance/glance-api.conf
echo "admin_user = glance" >> /etc/glance/glance-api.conf
echo "admin_password = ${GLANCE_PASS}" >> /etc/glance/glance-api.conf
echo "[paste_deploy]" >> /etc/glance/glance-api.conf
echo "flavor = keystone" >> /etc/glance/glance-api.conf
echo "[glance_store]" >> /etc/glance/glance-api.conf
echo "default_store = file" >> /etc/glance/glance-api.conf
echo "filesystem_store_datadir = /var/lib/glance/images/" >> /etc/glance/glance-api.conf

echo "[DEFAULT]" > /etc/glance/glance-registry.conf
echo "notification_driver = noop" >> /etc/glance/glance-registry.conf
echo "[database]" >> /etc/glance/glance-registry.conf
echo "connection = mysql://glance:${GLANCE_DBPASS}@controller/glance" >> /etc/glance/glance-registry.conf
echo "[keystone_authtoken]" >> /etc/glance/glance-registry.conf
echo "auth_uri = http://controller:5000/v2.0" >> /etc/glance/glance-registry.conf
echo "identity_uri = http://controller:35357" >> /etc/glance/glance-registry.conf
echo "admin_tenant_name = service" >> /etc/glance/glance-registry.conf
echo "admin_user = glance" >> /etc/glance/glance-registry.conf
echo "admin_password = ${GLANCE_PASS}" >> /etc/glance/glance-registry.conf
echo "[paste_deploy]" >> /etc/glance/glance-registry.conf
echo "flavor = keystone" >> /etc/glance/glance-registry.conf

su -s /bin/sh -c "glance-manage db_sync" glance

systemctl enable openstack-glance-api.service openstack-glance-registry.service
systemctl start openstack-glance-api.service openstack-glance-registry.service

# upload cirros image in glance
mkdir /tmp/images
wget -P /tmp/images http://download.cirros-cloud.net/0.3.3/cirros-0.3.3-x86_64-disk.img
glance image-create --name "cirros-0.3.3-x86_64" --file /tmp/images/cirros-0.3.3-x86_64-disk.img \
  --disk-format qcow2 --container-format bare --is-public True --progress
rm -rf /tmp/images

# test
glance image-list


# ==============================================================================
# Openstack Nova Controller / Scheduler
# ==============================================================================

keystone user-create --name nova --pass ${NOVA_PASS}
keystone user-role-add --user nova --tenant service --role admin
keystone service-create --name nova --type compute --description "OpenStack Compute"
keystone endpoint-create \
  --service-id $(keystone service-list | awk '/ compute / {print $2}') \
  --publicurl http://controller:8774/v2/%\(tenant_id\)s \
  --internalurl http://controller:8774/v2/%\(tenant_id\)s \
  --adminurl http://controller:8774/v2/%\(tenant_id\)s \
  --region regionOne

yum install -y openstack-nova-api openstack-nova-cert openstack-nova-conductor \
openstack-nova-console openstack-nova-novncproxy openstack-nova-scheduler \
python-novaclient

# update configuration
mv /etc/nova/nova.conf /etc/nova/nova.conf.original
echo "[DEFAULT]" > /etc/nova/nova.conf
echo "rpc_backend = rabbit" >> /etc/nova/nova.conf
echo "rabbit_host = controller" >> /etc/nova/nova.conf
echo "rabbit_password = ${RABBIT_PASS}" >> /etc/nova/nova.conf
echo "auth_strategy = keystone" >> /etc/nova/nova.conf
echo "my_ip = ${MANAGEMENT_IP}" >> /etc/nova/nova.conf
echo "vnc_enabled = True" >> /etc/nova/nova.conf
echo "vncserver_listen = 0.0.0.0" >> /etc/nova/nova.conf
echo "vncserver_proxyclient_address = ${MANAGEMENT_IP}" >> /etc/nova/nova.conf
echo "novncproxy_base_url = http://controller:6080/vnc_auto.html" >> /etc/nova/nova.conf
# required for legacy-networking on controller
echo "network_api_class = nova.network.api.API" >> /etc/nova/nova.conf
echo "security_group_api = nova" >> /etc/nova/nova.conf
# required for legacy-networking on compute node ( on top of the legacy-networking on controller )
echo "firewall_driver = nova.virt.libvirt.firewall.IptablesFirewallDriver" >> /etc/nova/nova.conf
echo "network_manager = nova.network.manager.FlatDHCPManager" >> /etc/nova/nova.conf
echo "network_size = 254" >> /etc/nova/nova.conf
echo "allow_same_net_traffic = False" >> /etc/nova/nova.conf
echo "multi_host = True" >> /etc/nova/nova.conf
echo "send_arp_for_ha = True" >> /etc/nova/nova.conf
echo "share_dhcp_address = True" >> /etc/nova/nova.conf
echo "force_dhcp_release = True" >> /etc/nova/nova.conf
echo "flat_network_bridge = br100" >> /etc/nova/nova.conf
echo "flat_interface = ${EXTERNAL_INTERFACE_NAME}" >> /etc/nova/nova.conf
echo "public_interface = ${EXTERNAL_INTERFACE_NAME}" >> /etc/nova/nova.conf
echo "[database]" >> /etc/nova/nova.conf
echo "connection = mysql://nova:${NOVA_DBPASS}@controller/nova" >> /etc/nova/nova.conf
echo "[keystone_authtoken]" >> /etc/nova/nova.conf
echo "auth_uri = http://controller:5000/v2.0" >> /etc/nova/nova.conf
echo "identity_uri = http://controller:35357" >> /etc/nova/nova.conf
echo "admin_tenant_name = service" >> /etc/nova/nova.conf
echo "admin_user = nova" >> /etc/nova/nova.conf
echo "admin_password = ${NOVA_PASS}" >> /etc/nova/nova.conf
echo "[glance]" >> /etc/nova/nova.conf
echo "host = controller" >> /etc/nova/nova.conf
echo "[libvirt]" >> /etc/nova/nova.conf
echo "virt_type = qemu" >> /etc/nova/nova.conf

su -s /bin/sh -c "nova-manage db sync" nova

systemctl enable openstack-nova-api.service
systemctl enable openstack-nova-cert.service
systemctl enable openstack-nova-consoleauth.service
systemctl enable openstack-nova-scheduler.service
systemctl enable openstack-nova-conductor.service
systemctl enable openstack-nova-novncproxy.service
systemctl start openstack-nova-api.service
systemctl start openstack-nova-cert.service
systemctl start openstack-nova-consoleauth.service
systemctl start openstack-nova-scheduler.service
systemctl start openstack-nova-conductor.service
systemctl start openstack-nova-novncproxy.service

# test
nova service-list


# ==============================================================================
# Openstack Nova Compute
# ==============================================================================

yum install -y openstack-nova-compute sysfsutils
# workaround for missing libvirt-daemon-config-nwfilter
yum install -y libvirt-daemon-config-nwfilter

systemctl enable libvirtd.service
systemctl enable openstack-nova-compute.service
systemctl start libvirtd.service
systemctl start openstack-nova-compute.service

# test
nova service-list


# ==============================================================================
# Openstack Nova Legacy Network
# ==============================================================================

yum install -y openstack-nova-network
yum install -y openstack-nova-api

systemctl enable openstack-nova-network.service
systemctl start openstack-nova-network.service
# the following conflicts on 8775 with nova-api
# systemctl enable openstack-nova-metadata-api.service
# systemctl start openstack-nova-metadata-api.service

# vi /var/log/nova/nova-api-metadata.log
# SEE: http://egonzalez.org/openstack-nova-api-start-error-could-not-bind-to-0-0-0-0-address-already-in-use/

nova network-create ${NETWORK_NAME} --bridge ${NETWORK_BRIDGE_ID} --multi-host T --fixed-range-v4 ${NETWORK_FIXED_RANGE_CIDR}

# verify
nova net-list


# ==============================================================================
# Openstach Dashboard


yum install -y openstack-dashboard httpd mod_wsgi memcached python-memcached

sed -i -e '/OPENSTACK_HOST.*=/s/=.*/=\x27controller\x27/' /etc/openstack-dashboard/local_settings
sed -i -e '/ALLOWED_HOSTS.*=/s/=.*/=[\x27*\x27]/' /etc/openstack-dashboard/local_settings

setsebool -P httpd_can_network_connect on
chown -R apache:apache /usr/share/openstack-dashboard/static

systemctl enable httpd.service
systemctl enable memcached.service
systemctl start httpd.service
systemctl start memcached.service
systemctl disable iptables
systemctl stop iptables


# ==============================================================================
# test dashboard
# ==============================================================================

echo "=========================================================================="
echo "[ SUCCESS ]"
echo "=========================================================================="
echo "Openstack CLI access:"
echo "- on the os controller node:"
echo "  source /root/adminrc"
echo "  nova service-list"
echo "  glance image-list"
echo "  keystone tenant-list"
echo "=========================================================================="
echo "Openstack Dashboard UI access:"
echo "- credentials: admin/{$ADMIN_PASS}"
echo "- on controller node: http://localhost/dashboard"
echo "- on vagrant host with port forwarding (check during vagrant-up operation):\
 http://localhost:2200/dashboard"
echo "=========================================================================="
