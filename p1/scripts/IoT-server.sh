
#!/usr/bin/env bash
set -Eeuo pipefail

# Provisioned as root by Vagrant.
# Target guest OS: Debian 13 (Trixie).
export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y curl ca-certificates iproute2 procps kmod iptables

# Prepare the kernel for K3s networking.
modprobe overlay
modprobe br_netfilter

cat >/etc/sysctl.d/99-iot-k3s.conf <<'K8S_SYSCTL'
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
K8S_SYSCTL

sysctl --system >/dev/null

# Debian minimal normally has no active UFW firewall.
# If UFW is active, permit K3s traffic within the lab networks.
if command -v ufw >/dev/null 2>&1 &&
   ufw status | grep -q '^Status: active'; then
  ufw allow from 192.168.56.0/24 to any port 6443 proto tcp
  ufw allow from 192.168.56.0/24 to any port 8472 proto udp
  ufw allow from 192.168.56.0/24 to any port 10250 proto tcp
  ufw allow from 10.42.0.0/16
  ufw allow from 10.43.0.0/16
fi

# Use the same join token for server and worker.
export K3S_TOKEN
K3S_TOKEN="$(tr -d '\r\n' < /vagrant/.iot-join-token)"

export INSTALL_K3S_CHANNEL=stable
export INSTALL_K3S_EXEC='server --node-name=iots --node-ip=192.168.56.110 --advertise-address=192.168.56.110 --tls-san=192.168.56.110 --write-kubeconfig-mode=644'

curl --fail --silent --show-error --location \
  https://get.k3s.io -o /tmp/iot-install-k3s.sh

sh /tmp/iot-install-k3s.sh

# Wait until the server node is actually Ready.
for attempt in $(seq 1 120); do
  if /usr/local/bin/k3s kubectl --request-timeout=10s \
       wait --for=condition=Ready node/iots --timeout=5s \
       >/dev/null 2>&1; then
    /usr/local/bin/k3s kubectl get nodes -o wide
    exit 0
  fi
  sleep 5
done

echo 'K3s server did not become Ready' >&2
journalctl -u k3s -n 100 --no-pager || true
exit 1
