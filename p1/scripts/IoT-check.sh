#!/usr/bin/env bash
set -Eeuo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
echo '[1] Both Vagrant VMs'
vagrant status
echo '[2] Node addresses'
vagrant ssh hlehmannS -c 'sudo /usr/local/bin/k3s kubectl wait --for=condition=Ready nodes --all --timeout=300s && ip -brief address && sudo /usr/local/bin/k3s kubectl get nodes -o wide'
echo '[3] Worker agent'
vagrant ssh hlehmannSW -c 'sudo systemctl is-active k3s-agent; ip -brief address'
echo '[4] Passwordless SSH to both VMs'
vagrant ssh hlehmannS -c 'hostname'
vagrant ssh hlehmannSW -c 'hostname'
