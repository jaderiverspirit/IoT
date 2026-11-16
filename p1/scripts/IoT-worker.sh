
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

# Allow required Kubernetes traffic if UFW is active.
if command -v ufw >/dev/null 2>&1 &&
   ufw status | grep -q '^Status: active'; then
  ufw allow from 192.168.56.0/24 to any port 8472 proto udp
  ufw allow from 192.168.56.0/24 to any port 10250 proto tcp
  ufw allow from 10.42.0.0/16
  ufw allow from 10.43.0.0/16
fi

# Wait until the K3s server is reachable.
for attempt in $(seq 1 90); do
  if timeout 2 bash -c \
       'echo > /dev/tcp/192.168.56.110/6443' 2>/dev/null; then
    break
  fi

  if (( attempt == 90 )); then
    echo 'Cannot reach K3s server at 192.168.56.110:6443' >&2
    exit 1
  fi

  sleep 2
done

# Join the existing K3s cluster.
export K3S_TOKEN
K3S_TOKEN="$(tr -d '\r\n' < /vagrant/.iot-join-token)"

export K3S_URL='https://192.168.56.110:6443'
export INSTALL_K3S_CHANNEL=stable
export INSTALL_K3S_EXEC='agent --node-name=iotsw --node-ip=192.168.56.111'

curl --fail --silent --show-error --location \
  https://get.k3s.io -o /tmp/iot-install-k3s.sh

sh /tmp/iot-install-k3s.sh

systemctl is-active --quiet k3s-agent
