#!/usr/bin/env bash
set -Eeuo pipefail
kubectl config current-context | grep -qx k3d-iot
kubectl get ns argocd dev
kubectl -n argocd get application iot-github
kubectl -n dev get pods,deployment,svc -o wide
kubectl -n dev rollout status deploy/iot-playground --timeout=300s
kubectl -n dev get deploy iot-playground -o jsonpath='{.spec.template.spec.containers[0].image}'; echo
cat <<'EOF'
From another terminal, expose the application:
    kubectl -n dev port-forward svc/iot-playground 8888:8888
Then run:
    curl http://127.0.0.1:8888/
To test GitOps, push an image tag change v1 -> v2 to the public repo,
wait for Argo CD auto-sync, then re-run the checks and curl.
EOF
