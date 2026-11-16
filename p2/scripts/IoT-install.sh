
#!/usr/bin/env bash
set -Eeuo pipefail

# Provisioned as root by Vagrant.
# Target guest OS: Debian 13 (Trixie).
export DEBIAN_FRONTEND=noninteractive

# Install dependencies required by K3s.
apt-get update
apt-get install -y \
  curl ca-certificates iproute2 procps kmod iptables

# Prepare the kernel for Kubernetes networking.
modprobe overlay
modprobe br_netfilter

cat >/etc/sysctl.d/99-iot-k3s.conf <<'K8S_SYSCTL'
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
K8S_SYSCTL

sysctl --system >/dev/null

# Debian minimal normally has no active UFW firewall.
# If UFW is active, allow the necessary lab traffic.
if command -v ufw >/dev/null 2>&1 &&
   ufw status | grep -q '^Status: active'; then
  # HTTP and HTTPS ingress from the Vagrant host-only network.
  ufw allow from 192.168.56.0/24 to any port 80 proto tcp
  ufw allow from 192.168.56.0/24 to any port 443 proto tcp

  # Kubernetes networking.
  ufw allow from 10.42.0.0/16
  ufw allow from 10.43.0.0/16
fi

# Install a single-node K3s server.
# Traefik and ServiceLB remain enabled.
export INSTALL_K3S_CHANNEL=stable
export INSTALL_K3S_EXEC='server --node-name=iots --node-ip=192.168.56.110 --advertise-address=192.168.56.110 --tls-san=192.168.56.110 --write-kubeconfig-mode=644'

curl --fail --silent --show-error --location \
  https://get.k3s.io -o /tmp/iot-install-k3s.sh

sh /tmp/iot-install-k3s.sh

# Wait until the Kubernetes node is Ready.
for attempt in $(seq 1 120); do
  if /usr/local/bin/k3s kubectl --request-timeout=10s \
       wait --for=condition=Ready node/iots --timeout=5s \
       >/dev/null 2>&1; then
    break
  fi

  if (( attempt == 120 )); then
    echo 'K3s node did not become Ready' >&2
    journalctl -u k3s -n 100 --no-pager || true
    exit 1
  fi

  sleep 5
done

# Deploy the three applications and their Ingress.
# app1: 1 replica; app2: 3 replicas; app3: 1 replica.
/usr/local/bin/k3s kubectl apply \
  -f /vagrant/confs/IoT-apps.yaml

# Verify that all three applications become available.
/usr/local/bin/k3s kubectl rollout status \
  deployment/iot-app1 --timeout=300s

/usr/local/bin/k3s kubectl rollout status \
  deployment/iot-app2 --timeout=300s

/usr/local/bin/k3s kubectl rollout status \
  deployment/iot-app3 --timeout=300s

# Traefik is installed asynchronously by K3s.
# Wait for the deployment to be created.
for attempt in $(seq 1 120); do
  if /usr/local/bin/k3s kubectl -n kube-system \
       get deployment traefik >/dev/null 2>&1; then
    break
  fi

  if (( attempt == 120 )); then
    echo 'Traefik deployment was not created' >&2
    exit 1
  fi

  sleep 5
done

# Verify that Traefik is available.
/usr/local/bin/k3s kubectl -n kube-system \
  rollout status deployment/traefik --timeout=300s

# Display deployment results.
/usr/local/bin/k3s kubectl \
  get deployments,services,ingresses,pods -o wide

echo 'P2 deployment completed successfully.'
