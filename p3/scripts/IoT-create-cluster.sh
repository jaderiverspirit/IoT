#!/usr/bin/env bash
set -Eeuo pipefail

if ! docker info >/dev/null 2>&1; then
  echo 'Docker inaccessible. Run: newgrp docker (or log out and log in).' >&2
  exit 1
fi
if k3d cluster list -o json | jq -e 'any(.[]; .name == "iot")' >/dev/null 2>&1; then
  echo 'Existing iot cluster found: reusing it.'
else
  k3d cluster create iot --servers 1 --agents 0 --wait --timeout 300s --image rancher/k3s:v1.35.5-k3s1 \
    --port '127.0.0.1:8080:80@loadbalancer'
fi
kubectl config use-context k3d-iot
kubectl get nodes -o wide
kubectl create namespace dev --dry-run=client -o yaml | kubectl apply -f -
