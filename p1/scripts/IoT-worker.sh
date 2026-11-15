#!/usr/bin/env bash
set -Eeuo pipefail

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

# Vagrant starts/provisions IoTS before IoTSW, but retry to avoid boot races.
for attempt in $(seq 1 90); do
  if timeout 2 bash -c 'echo > /dev/tcp/192.168.56.110/6443' 2>/dev/null; then
	break
  fi
  if (( attempt == 90 )); then
	echo 'Cannot reach K3s server at 192.168.56.110:6443' >&2
	exit 1
  fi
  sleep 2
done

export K3S_TOKEN
K3S_TOKEN="$(tr -d '\r\n' < /vagrant/.iot-join-token)"
export K3S_URL='https://192.168.56.110:6443'
export INSTALL_K3S_CHANNEL=stable
export INSTALL_K3S_EXEC='agent --node-name=iotsw --node-ip=192.168.56.111'

curl --fail --silent --show-error --location https://get.k3s.io -o /tmp/iot-install-k3s.sh
sh /tmp/iot-install-k3s.sh
systemctl is-active --quiet k3s-agent
