
# ==============================================================================
# RC environment files for administrative and demo users ( CLI use only )
# ==============================================================================

echo "export OS_TENANT_NAME=admin" > /root/adminrc
echo "export OS_USERNAME=admin" >> /root/adminrc
echo "export OS_PASSWORD=${ADMIN_PASS}" >> /root/adminrc
echo "export OS_AUTH_URL=http://controller:35357/v2.0" >> /root/adminrc

source /root/adminrc

# ==============================================================================
# Openstack Nova Compute
# ==============================================================================

yum install -y openstack-nova-compute sysfsutils
# workaround for missing libvirt-daemon-config-nwfilter
yum install -y libvirt-daemon-config-nwfilter


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
echo "metadata_listen_port=9775" >> ${CONFIG_FILE}
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


systemctl enable libvirtd.service
systemctl enable openstack-nova-compute.service
systemctl start libvirtd.service
systemctl start openstack-nova-compute.service

# test
nova service-list
