#!/usr/bin/env bash
set -Eeuo pipefail

# Provisioned as root by Vagrant. Supported guest: Rocky Linux 10.
# Rocky Linux 10: br_netfilter/overlay may require kernel-modules-extra.
dnf -y install curl ca-certificates iproute procps-ng kmod kernel-modules-extra
modprobe overlay
modprobe br_netfilter
cat >/etc/sysctl.d/99-iot-k3s.conf <<'K8S_SYSCTL'
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
K8S_SYSCTL
sysctl --system >/dev/null

# Permit the Vagrant host-only network and K3s pod/service CIDRs, without
# opening arbitrary ports on the VM's Internet-facing NAT interface.
if systemctl is-active --quiet firewalld; then
  firewall-cmd --permanent --zone=trusted --add-source=192.168.56.0/24
  firewall-cmd --permanent --zone=trusted --add-source=10.42.0.0/16
  firewall-cmd --permanent --zone=trusted --add-source=10.43.0.0/16
  firewall-cmd --reload
fi

# Explicit node name keeps the Kubernetes DNS identifier lowercase even though
# the subject requires Vagrant machine names in the form IoTS and IoTSW.
export K3S_TOKEN
K3S_TOKEN="$(tr -d '\r\n' < /vagrant/.iot-join-token)"
export INSTALL_K3S_CHANNEL=stable
export INSTALL_K3S_EXEC='server --node-name=iots --node-ip=192.168.56.110 --advertise-address=192.168.56.110 --tls-san=192.168.56.110 --write-kubeconfig-mode=644'

curl --fail --silent --show-error --location https://get.k3s.io -o /tmp/iot-install-k3s.sh
sh /tmp/iot-install-k3s.sh

for attempt in $(seq 1 90); do
  if kubectl get nodes >/dev/null 2>&1; then
	kubectl get nodes -o wide
	exit 0
  fi
  sleep 2
done
echo 'K3s server not healthy after 180 seconds' >&2
journalctl -u k3s -n 100 --no-pager || true
exit 1
