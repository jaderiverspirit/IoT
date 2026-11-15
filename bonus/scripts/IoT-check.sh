#!/usr/bin/env bash
set -Eeuo pipefail
kubectl config current-context | grep -qx k3d-iot
kubectl get namespaces argocd dev gitlab
kubectl -n gitlab get pods,svc,pvc
kubectl -n argocd get applications iot-gitlab -o wide
source_url="$(kubectl -n argocd get applications iot-gitlab -o jsonpath='{.spec.source.repoURL}')"
[[ "$source_url" == 'http://gitlab.gitlab.svc.cluster.local:8081/root/iot-gitops.git' ]] || {
  echo "Argo CD is not sourcing the local GitLab repository: ${source_url}" >&2; exit 1;
}
kubectl -n dev rollout status deploy/iot-playground --timeout=300s
kubectl -n dev get deployment,svc,pods -o wide
kubectl -n dev get deploy/iot-playground \
  -o jsonpath='{.spec.template.spec.containers[0].image}'; echo
printf 'Check the application body with port-forward + curl; update via IoT-set-local-version.sh.\n'
