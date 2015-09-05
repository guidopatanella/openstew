
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


systemctl enable libvirtd.service
systemctl enable openstack-nova-compute.service
systemctl start libvirtd.service
systemctl start openstack-nova-compute.service

# test
nova service-list
