#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
  echo 'Usage: ./p3/scripts/IoT-configure-github.sh https://github.com/ACCOUNT/IoT-REPOSITORY.git' >&2
  echo 'Prerequisite: create a PUBLIC GitHub repository containing the p3/confs/apps files.' >&2
  exit 2
}
[[ $# -eq 1 ]] || usage
repo="$1"
[[ "$repo" =~ ^https://github\.com/[A-Za-z0-9-]+/[A-Za-z0-9_.-]+(\.git)?$ ]] || usage
[[ "${repo,,}" == *iot* ]] || {
  echo 'Repository name must include IoT (the requested login prefix).' >&2; exit 2;
}
kubectl config current-context | grep -qx 'k3d-iot'
# Fail instead of deploying an app pointing to a nonexistent public repository.
GIT_TERMINAL_PROMPT=0 git ls-remote "$repo" HEAD >/dev/null || {
  echo 'Repository not reachable: ensure it is public and contains a main branch.' >&2; exit 1;
}
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# Ensure only one Argo CD Application manages the playground.
# With no Argo CD deletion finalizer, the deployed resources are retained.
kubectl -n argocd delete application iot-gitlab \
  --ignore-not-found --wait=true

sed "s|__IOT_GITHUB_URL__|${repo}|" \
  "$root/p3/confs/IoT-github-application.template.yaml" | kubectl apply -f -

kubectl -n argocd get applications iot-github
printf 'Argo CD will now automatically sync manifests from: %s\n' "$repo"
