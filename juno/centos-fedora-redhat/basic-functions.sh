

# sets role variables that indicate how openstack tiers are being deployed
function set_tier {

  local role=$1
  if [ ${role} == "controller" ]; then
    TIER_CONTROLLER="true"
    echo "127.0.0.1  controller" >> /etc/hosts
  fi
  if [ ${role} == "compute" ]; then
    TIER_COMPUTE="true"
    echo "127.0.0.1  compute" >> /etc/hosts
  fi
  if [ ${role} == "network" ]; then
    TIER_NETWORK="true"
    echo "127.0.0.1  network" >> /etc/hosts
  fi

}


function set_tier_references {

if [ ${TIER_CONTROLLER} == "false" ]; then
  echo "You have opted for this server to not be a CONTROLLER node, please specify the IP address of your openstack CONTROLLER node:"
  read IP
  echo "${IP}  controller" >> /etc/hosts
fi
if [ ${TIER_COMPUTE} == "false" ]; then
  echo "You have opted for this server to not be a COMPUTE node, please specify the IP address of your openstack COMPUTE node:"
  read IP
  echo "${IP}  compute" >> /etc/hosts
fi
if [ ${TIER_NETWORK} == "false" ]; then
  echo "You have opted for this server to not be a NETWORK node, please specify the IP address of your openstack NETWORK node:"
  read IP
  echo "${IP}  network" >> /etc/hosts
fi

}
