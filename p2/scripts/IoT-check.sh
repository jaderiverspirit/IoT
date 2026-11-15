#!/usr/bin/env bash
set -Eeuo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
echo '[1] Kubernetes resources and replica counts'
vagrant ssh IoTS -c 'sudo kubectl get deployments,pods,services,ingress -o wide; sudo kubectl get deploy iot-app2 -o jsonpath="{.status.readyReplicas}{\"/\"}{.spec.replicas}{\" ready\n\"}"'
echo '[2] Host-based routing, plus default app3'
for host in app1.com app2.com unknown.example; do
  printf '\nHost: %s\n' "$host"
  curl --fail --show-error --silent --max-time 15 -H "Host: $host" http://192.168.56.110/ | grep 'Hello from'
done
