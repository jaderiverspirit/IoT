#!/usr/bin/env bash
set -Eeuo pipefail
kubectl config current-context | grep -qx 'k3d-iot' || {
  echo 'Refusing to install into an unexpected Kubernetes context.' >&2; exit 1;
}
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
# Large CRD metadata requires server-side apply.
kubectl apply -n argocd --server-side --force-conflicts \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/v3.6.1/manifests/install.yaml
kubectl -n argocd rollout status deployment/argocd-repo-server --timeout=600s
kubectl -n argocd rollout status deployment/argocd-server --timeout=600s
kubectl -n argocd rollout status statefulset/argocd-application-controller --timeout=600s
kubectl get pods -n argocd
cat <<'EOF'
Argo CD interface: kubectl port-forward -n argocd svc/argocd-server 8082:443
Open: https://127.0.0.1:8082 (self-signed certificate)
User: admin
Get password: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo
EOF
