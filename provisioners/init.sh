#!/usr/bin/env bash
cd /tmp/provisioners
mkdir -p /root/.ssh
chmod 700 /root/.ssh
cp roles/k8s/files/id_rsa /root/.ssh/
chmod 600 /root/.ssh/id_rsa
yum install -y ansible
echo -e "[all]\n$1\n$2\n$3\n" >hosts
export ANSIBLE_HOST_KEY_CHECKING=False && ansible-playbook -i hosts deploy.yaml
