#!/bin/bash

USERNAME=$1
PASSWORD=$2
HOSTNAME=$3 #fqdn of masters (web console address)
NODECOUNT=$4
ROUTEREXTIP=$5 #ip address of infranodes (must to be public ip address if access from internet needed)
MASTERCOUNT=$6
INFRACOUNT=$7

#yum -y update
yum -y install wget git net-tools bind-utils iptables-services bridge-utils bash-completion httpd-tools
yum -y install https://dl.fedoraproject.org/pub/epel/7/x86_64/e/epel-release-7-9.noarch.rpm
sed -i -e "s/^enabled=1/enabled=0/" /etc/yum.repos.d/epel.repo
yum -y --enablerepo=epel install ansible pyOpenSSL
git clone https://github.com/openshift/openshift-ansible /opt/openshift-ansible
yum -y install docker
sed -i -e "s#^OPTIONS='--selinux-enabled'#OPTIONS='--selinux-enabled --insecure-registry 172.30.0.0/16'#" /etc/sysconfig/docker

cat <<EOF > /etc/sysconfig/docker-storage-setup
DEVS=/dev/sdc
VG=docker-vg
EOF

docker-storage-setup
systemctl enable docker
systemctl start docker

cat <<EOF > /etc/ansible/hosts
[OSEv3:children]
masters
nodes

[OSEv3:vars]
ansible_ssh_user=${USERNAME}
ansible_become=yes
debug_level=2
deployment_type=origin
openshift_master_identity_providers=[{'name': 'htpasswd_auth', 'login': 'true', 'challenge': 'true', 'kind': 'HTPasswdPasswordIdentityProvider', 'filename': '/etc/origin/master/htpasswd'}]

openshift_master_cluster_method=native
openshift_master_cluster_hostname=${HOSTNAME}
openshift_master_cluster_public_hostname=${HOSTNAME}

openshift_master_default_subdomain=${ROUTEREXTIP}.xip.io
openshift_use_dnsmasq=False

[masters]
master[1:${MASTERCOUNT}] openshift_public_hostname=${HOSTNAME}

[etcd]
master[1:${MASTERCOUNT}]

[nodes]
master[1:${MASTERCOUNT}]
node[01:${NODECOUNT}] openshift_node_labels="{'region': 'primary', 'zone': 'default'}"
infranode[1:${INFRACOUNT}] openshift_node_labels="{'region': 'infra', 'zone': 'default'}"
EOF

mkdir -p /etc/origin/master
htpasswd -cb /etc/origin/master/htpasswd.dist ${USERNAME} ${PASSWORD}

cat <<EOF > /home/${USERNAME}/openshift-install.sh
export ANSIBLE_HOST_KEY_CHECKING=False
ansible-playbook /opt/openshift-ansible/playbooks/byo/config.yml
oadm registry --selector=region=infra
oadm router --selector=region=infra
sudo cp -f /etc/origin/master/htpasswd.dist /etc/origin/master/htpasswd
EOF

chmod 755 /home/${USERNAME}/openshift-install.sh
