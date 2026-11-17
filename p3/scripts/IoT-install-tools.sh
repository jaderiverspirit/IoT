#!/usr/bin/env bash
set -Eeuo pipefail

# Run *inside* the Linux VM used for P3, not on your physical computer.
if [[ ! -f /etc/os-release ]]; then echo 'Cannot identify Linux distribution' >&2; exit 1; fi
source /etc/os-release
if [[ "${ID}" != 'ubuntu' && "${ID}" != 'debian' ]]; then
  echo 'This setup script supports Ubuntu 24.04+/Debian 12+ VMs.' >&2
  exit 1
fi
if [[ "$(id -u)" -eq 0 ]]; then
  echo 'Run this script as your regular VM user (sudo is used internally).' >&2
  exit 1
fi
sudo apt-get update
sudo apt-get install -y ca-certificates curl gnupg git jq openssl apt-transport-https

# Docker Inc official signed APT repository; no apt-key and no insecure source.
sudo install -m 0755 -d /etc/apt/keyrings
if [[ ! -e /etc/apt/keyrings/docker.asc ]]; then
  sudo curl --fail --silent --show-error --location \
    "https://download.docker.com/linux/${ID}/gpg" -o /etc/apt/keyrings/docker.asc
fi
sudo chmod a+r /etc/apt/keyrings/docker.asc
arch="$(dpkg --print-architecture)"
codename="${UBUNTU_CODENAME:-${VERSION_CODENAME}}"
sudo rm -f /etc/apt/sources.list.d/docker.list

sudo tee /etc/apt/sources.list.d/docker.sources >/dev/null <<EOF
Types: deb
URIs: https://download.docker.com/linux/${ID}
Suites: ${codename}
Components: stable
Architectures: ${arch}
Signed-By: /etc/apt/keyrings/docker.asc
EOF
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo systemctl enable --now docker
sudo usermod -aG docker "$(id -un)"

# K3d official installer fetches the current stable release by default.
curl --fail --silent --show-error --location \
  https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh -o /tmp/iot-k3d-install.sh
sudo bash /tmp/iot-k3d-install.sh

# Install the latest kubectl patch release for Kubernetes 1.35.
arch="$(dpkg --print-architecture)"
case "$arch" in amd64|arm64) ;; *) echo "Unsupported arch: $arch" >&2; exit 1 ;; esac
version="$(curl --fail --silent --show-error -L https://dl.k8s.io/release/stable-1.35.txt)"
curl --fail --silent --show-error -L \
  "https://dl.k8s.io/release/${version}/bin/linux/${arch}/kubectl" -o /tmp/iot-kubectl
sudo install -m 0755 /tmp/iot-kubectl /usr/local/bin/kubectl

k3d version
kubectl version --client
printf '\nDocker user group may not be active yet. Run: newgrp docker\n'
printf 'Then: ./p3/scripts/IoT-create-cluster.sh\n'
printf 'WARNING: membership in docker group grants root-equivalent access; VM lab only.\n'
