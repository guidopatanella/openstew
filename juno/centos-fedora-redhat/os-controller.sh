

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
rabbitmqctl change_password ${RABBIT_USER} ${RABBIT_PASS}
systemctl restart rabbitmq-server.service

# ==============================================================================
# Keystone
# ==============================================================================

yum install -y openstack-keystone python-keystoneclient
# update configuration
CONFIG_FILE=/etc/keystone/keystone.conf
mv ${CONFIG_FILE} ${CONFIG_FILE}.original
echo "[DEFAULT]" > ${CONFIG_FILE}
echo "public_bind_host=0.0.0.0" >> ${CONFIG_FILE}
echo "public_port=5000" >> ${CONFIG_FILE}
echo "admin_bind_host=0.0.0.0" >> ${CONFIG_FILE}
echo "admin_port=35357" >> ${CONFIG_FILE}
echo "admin_token = ${KEYSTONE_ADMIN_TOKEN}" >> ${CONFIG_FILE}
echo "rpc_backend = rabbit" >> ${CONFIG_FILE}
echo "rabbit_userid=${RABBIT_USER}" >> ${CONFIG_FILE}
echo "rabbit_password=${RABBIT_PASS}" >> ${CONFIG_FILE}
echo "[database]" >> ${CONFIG_FILE}
echo "connection = mysql://keystone:${KEYSTONE_DBPASS}@controller/keystone" >> ${CONFIG_FILE}
echo "[token]" >> ${CONFIG_FILE}
echo "provider = keystone.token.providers.uuid.Provider" >> ${CONFIG_FILE}
echo "driver = keystone.token.persistence.backends.sql.Token" >> ${CONFIG_FILE}
echo "[revoke]" >> ${CONFIG_FILE}
echo "driver = keystone.contrib.revoke.backends.sql.Revoke" >> ${CONFIG_FILE}

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
CONFIG_FILE=/etc/glance/glance-api.conf
mv ${CONFIG_FILE} ${CONFIG_FILE}.original
echo "[DEFAULT]" > ${CONFIG_FILE}
echo "bind_host=0.0.0.0" >> ${CONFIG_FILE}
echo "bind_port=9292" >> ${CONFIG_FILE}
echo "registry_host=0.0.0.0" >> ${CONFIG_FILE}
echo "registry_port=9191" >> ${CONFIG_FILE}
echo "rpc_backend = rabbit" >> ${CONFIG_FILE}
echo "rabbit_userid=${RABBIT_USER}" >> ${CONFIG_FILE}
echo "rabbit_password=${RABBIT_PASS}" >> ${CONFIG_FILE}
echo "notification_driver = noop" >> ${CONFIG_FILE}
echo "[database]" >> ${CONFIG_FILE}
echo "connection = mysql://glance:${GLANCE_DBPASS}@controller/glance" >> ${CONFIG_FILE}
echo "[keystone_authtoken]" >> ${CONFIG_FILE}
echo "auth_uri = http://controller:5000/v2.0" >> ${CONFIG_FILE}
echo "identity_uri = http://controller:35357" >> ${CONFIG_FILE}
echo "admin_tenant_name = service" >> ${CONFIG_FILE}
echo "admin_user = glance" >> ${CONFIG_FILE}
echo "admin_password = ${GLANCE_PASS}" >> ${CONFIG_FILE}
echo "[paste_deploy]" >> ${CONFIG_FILE}
echo "flavor = keystone" >> ${CONFIG_FILE}
echo "[glance_store]" >> ${CONFIG_FILE}
echo "default_store = file" >> ${CONFIG_FILE}
echo "filesystem_store_datadir = /var/lib/glance/images/" >> ${CONFIG_FILE}

CONFIG_FILE=/etc/glance/glance-registry.conf
mv ${CONFIG_FILE} ${CONFIG_FILE}.original
echo "[DEFAULT]" > ${CONFIG_FILE}
echo "bind_host=0.0.0.0" >> ${CONFIG_FILE}
echo "bind_port=9191" >> ${CONFIG_FILE}
echo "rpc_backend = rabbit" >> ${CONFIG_FILE}
echo "rabbit_userid=${RABBIT_USER}" >> ${CONFIG_FILE}
echo "rabbit_password=${RABBIT_PASS}" >> ${CONFIG_FILE}
echo "notification_driver = noop" >> ${CONFIG_FILE}
echo "[database]" >> ${CONFIG_FILE}
echo "connection = mysql://glance:${GLANCE_DBPASS}@controller/glance" >> ${CONFIG_FILE}
echo "[keystone_authtoken]" >> ${CONFIG_FILE}
echo "auth_uri = http://controller:5000/v2.0" >> ${CONFIG_FILE}
echo "identity_uri = http://controller:35357" >> ${CONFIG_FILE}
echo "admin_tenant_name = service" >> ${CONFIG_FILE}
echo "admin_user = glance" >> ${CONFIG_FILE}
echo "admin_password = ${GLANCE_PASS}" >> ${CONFIG_FILE}
echo "[paste_deploy]" >> ${CONFIG_FILE}
echo "flavor = keystone" >> ${CONFIG_FILE}

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
CONFIG_FILE="/etc/nova/nova.conf"
mv ${CONFIG_FILE} ${CONFIG_FILE}.controller.original
echo "[DEFAULT]" > ${CONFIG_FILE}
echo "auth_strategy = keystone" >> ${CONFIG_FILE}
echo "my_ip = ${MANAGEMENT_IP}" >> ${CONFIG_FILE}
echo "vnc_enabled = True" >> ${CONFIG_FILE}
echo "vncserver_listen = 0.0.0.0" >> ${CONFIG_FILE}
echo "vncserver_proxyclient_address = ${MANAGEMENT_IP}" >> ${CONFIG_FILE}
echo "novncproxy_base_url = http://controller:6080/vnc_auto.html" >> ${CONFIG_FILE}
echo "ec2_listen=0.0.0.0" >> ${CONFIG_FILE}
echo "ec2_listen_port=8773" >> ${CONFIG_FILE}
echo "osapi_compute_listen=0.0.0.0"  >> ${CONFIG_FILE}
echo "osapi_compute_listen_port=8774" >> ${CONFIG_FILE}
echo "metadata_listen=0.0.0.0" >> ${CONFIG_FILE}
echo "metadata_listen_port=2775" >> ${CONFIG_FILE}
echo "rpc_backend = rabbit" >> ${CONFIG_FILE}
echo "rabbit_port=5672" >> ${CONFIG_FILE}
echo "rabbit_host = controller" >> ${CONFIG_FILE}
echo "rabbit_userid=${RABBIT_USER}" >> ${CONFIG_FILE}
echo "rabbit_password = ${RABBIT_PASS}" >> ${CONFIG_FILE}
# required for legacy-networking on controller
echo "network_api_class = nova.network.api.API" >> ${CONFIG_FILE}
echo "security_group_api = nova" >> ${CONFIG_FILE}
# required for legacy-networking on compute node ( on top of the legacy-networking on controller )
echo "firewall_driver = nova.virt.firewall.NoopFirewallDriver" >> ${CONFIG_FILE}
echo "network_manager = nova.network.manager.FlatDHCPManager" >> ${CONFIG_FILE}
echo "network_size = 254" >> ${CONFIG_FILE}
echo "allow_same_net_traffic = False" >> ${CONFIG_FILE}
echo "multi_host = True" >> ${CONFIG_FILE}
echo "send_arp_for_ha = True" >> ${CONFIG_FILE}
echo "share_dhcp_address = True" >> ${CONFIG_FILE}
echo "force_dhcp_release = True" >> ${CONFIG_FILE}
echo "flat_network_bridge = br100" >> ${CONFIG_FILE}
echo "flat_interface = ${EXTERNAL_INTERFACE_NAME}" >> ${CONFIG_FILE}
echo "public_interface = ${EXTERNAL_INTERFACE_NAME}" >> ${CONFIG_FILE}
echo "metadata_host=127.0.0.1" >> ${CONFIG_FILE} # nova-network fails to start when using 'controller'
echo "metadata_port=2775" >> ${CONFIG_FILE} # changed from default 8775 avoiding conflict with nova api port
echo "[database]" >> ${CONFIG_FILE}
echo "connection = mysql://nova:${NOVA_DBPASS}@controller/nova" >> ${CONFIG_FILE}
echo "[keystone_authtoken]" >> ${CONFIG_FILE}
echo "auth_uri = http://controller:5000/v2.0" >> ${CONFIG_FILE}
echo "identity_uri = http://controller:35357" >> ${CONFIG_FILE}
echo "admin_tenant_name = service" >> ${CONFIG_FILE}
echo "admin_user = nova" >> ${CONFIG_FILE}
echo "admin_password = ${NOVA_PASS}" >> ${CONFIG_FILE}
echo "auth_host=127.0.0.1" >> ${CONFIG_FILE}
echo "auth_port = 35357" >> ${CONFIG_FILE}
echo "[glance]" >> ${CONFIG_FILE}
echo "host = controller" >> ${CONFIG_FILE}
echo "port=9292" >> ${CONFIG_FILE}
echo "[libvirt]" >> ${CONFIG_FILE}
echo "virt_type = qemu" >> ${CONFIG_FILE}

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
# Openstack Nova Legacy Network
# ==============================================================================

yum install -y openstack-nova-network

systemctl enable openstack-nova-network.service
systemctl start openstack-nova-network.service
# disabling due to conflicts still being reported even after port change
# systemctl enable openstack-nova-metadata-api.service
# systemctl start openstack-nova-metadata-api.service

nova network-create ${NETWORK_NAME} --bridge ${NETWORK_BRIDGE_ID} --multi-host T --fixed-range-v4 ${NETWORK_FIXED_RANGE_CIDR}

# verify
nova net-list

# ==============================================================================
# Openstach Dashboard
# ==============================================================================

yum install -y openstack-dashboard httpd mod_wsgi memcached python-memcached

sed -i -e '/OPENSTACK_HOST.*=/s/=.*/=\x27controller\x27/' /etc/openstack-dashboard/local_settings
sed -i -e '/ALLOWED_HOSTS.*=/s/=.*/=[\x27*\x27]/' /etc/openstack-dashboard/local_settings

setsebool -P httpd_can_network_connect on
chown -R apache:apache /usr/share/openstack-dashboard/static

systemctl enable httpd.service
systemctl enable memcached.service
systemctl start httpd.service
systemctl start memcached.service


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
