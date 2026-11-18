#!/usr/bin/env bash
set -Eeuo pipefail
# Execute from the same Linux VM running K3d Part 3.
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
kubectl config current-context | grep -qx 'k3d-iot' || {
  echo 'Expected Kubernetes context k3d-iot, run Part 3 first.' >&2; exit 1;
}
kubectl get namespace argocd >/dev/null || {
  echo 'Argo CD must be installed first (Part 3).' >&2; exit 1;
}

# Never commit passwords or access tokens. This also makes reruns idempotent.
secret_dir="${HOME}/.config/iot"
mkdir -p "$secret_dir"
chmod 700 "$secret_dir"
secret_file="$secret_dir/gitlab-root-password"
if [[ ! -s "$secret_file" ]]; then
  (umask 077; openssl rand -hex 32 > "$secret_file")
fi

kubectl create namespace gitlab --dry-run=client -o yaml | kubectl apply -f -
kubectl -n gitlab create secret generic iot-gitlab-bootstrap \
  --from-file="root-password=${secret_file}" --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f "$root/bonus/confs/IoT-gitlab.yaml"

echo 'Waiting for local GitLab to become ready (initial migration can take time).'
kubectl -n gitlab rollout status deployment/iot-gitlab --timeout=1800s
kubectl -n gitlab get pod,service,pvc

echo 'Next: ./bonus/scripts/IoT-start-gitlab-access.sh'
echo 'Then: ./bonus/scripts/IoT-bootstrap-local-repo.sh'
