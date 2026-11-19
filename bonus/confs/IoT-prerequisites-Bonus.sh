#!/usr/bin/env bash
# Read-only preflight for the Inception-of-Things GitLab bonus.
# Run inside the P3 + Bonus Debian VM, from any working directory.
set -u

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
errors=0
warnings=0
pass() { printf 'PASS  %s\n' "$*"; }
warn() { printf 'WARN  %s\n' "$*"; warnings=$((warnings + 1)); }
fail() { printf 'FAIL  %s\n' "$*"; errors=$((errors + 1)); }
section() { printf '\n=== %s ===\n' "$*"; }
has() { command -v "$1" >/dev/null 2>&1; }

printf '=== Bonus prerequisites: local GitLab + Argo CD (shared K3d cluster) ===\n'
printf 'Project: %s\n' "$ROOT"

section 'Local commands and project files'
for tool in bash git kubectl k3d docker curl; do
  if has "$tool"; then pass "$tool installed"; else fail "$tool missing"; fi
done

for file in \
  bonus/confs/IoT-gitlab.yaml \
  bonus/confs/IoT-argocd-gitlab-application.yaml \
  bonus/scripts/IoT-install-gitlab.sh \
  bonus/scripts/IoT-start-gitlab-access.sh \
  bonus/scripts/IoT-bootstrap-local-repo.sh \
  bonus/scripts/IoT-set-local-version.sh \
  bonus/scripts/IoT-check.sh; do
  if [[ -f "$ROOT/$file" ]]; then
    pass "$file exists"
    if [[ $file == *.sh ]]; then
      if bash -n "$ROOT/$file"; then pass "$file Bash syntax"; else fail "$file Bash syntax"; fi
    fi
  else
    fail "$file missing"
  fi
done

section 'K3d and Kubernetes'
if has docker; then
  if docker info >/dev/null 2>&1; then pass 'Docker daemon accessible'; else fail 'Docker daemon not accessible'; fi
fi
if has k3d; then
  if k3d cluster list 2>/dev/null | awk 'NR > 1 {print $1}' | grep -qx 'iot'; then
    pass 'K3d cluster iot exists'
  else
    fail 'K3d cluster iot not found'
  fi
fi

kube_ok=false
if has kubectl; then
  context="$(kubectl config current-context 2>/dev/null || true)"
  if [[ "$context" == 'k3d-iot' ]]; then
    pass 'Kubernetes context is k3d-iot'
    if kubectl cluster-info >/dev/null 2>&1; then
      pass 'Kubernetes API reachable'
      kube_ok=true
    else
      fail 'Kubernetes API unreachable'
    fi
  else
    fail "Kubernetes context is '${context:-unset}', expected k3d-iot (no automatic switching)"
  fi
fi

if [[ "$kube_ok" == true ]]; then
  section 'Required namespaces and Argo CD'
  for ns in argocd dev gitlab; do
    if kubectl get ns "$ns" >/dev/null 2>&1; then
      pass "Namespace $ns exists"
    else
      warn "Namespace $ns missing (may be created during setup)"
    fi
  done

  if kubectl -n argocd get deployment argocd-server >/dev/null 2>&1; then
    pass 'Argo CD server deployment exists'
  else
    fail 'Argo CD server deployment missing'
  fi

  if kubectl -n argocd get application iot-github >/dev/null 2>&1; then
    pass 'P3 GitHub Application is active (expected before Bonus switch)'
  elif kubectl -n argocd get application iot-gitlab >/dev/null 2>&1; then
    pass 'Local GitLab Application exists (Bonus may already be active)'
  else
    warn 'Neither iot-github nor iot-gitlab Application exists'
  fi

  section 'Local GitLab instance'
  if kubectl -n gitlab get deployment iot-gitlab >/dev/null 2>&1; then
    ready="$(kubectl -n gitlab get deployment iot-gitlab -o jsonpath='{.status.readyReplicas}' 2>/dev/null || true)"
    desired="$(kubectl -n gitlab get deployment iot-gitlab -o jsonpath='{.spec.replicas}' 2>/dev/null || true)"
    if [[ "$ready" == '1' && "$desired" == '1' ]]; then
      pass 'GitLab deployment 1/1 Ready'
    else
      warn "GitLab deployment not fully ready (${ready:-0}/${desired:-unknown}); check startup"
    fi
    manifest_image="$(grep -E '^[[:space:]]*image:[[:space:]]*gitlab/gitlab-ce:' "$ROOT/bonus/confs/IoT-gitlab.yaml" | head -n1 | awk '{print $2}')"
    live_image="$(kubectl -n gitlab get deployment iot-gitlab -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null || true)"
    if [[ -n "$manifest_image" && "$manifest_image" == "$live_image" ]]; then
      pass "GitLab image matches manifest ($live_image)"
    elif [[ -n "$live_image" ]]; then
      warn "GitLab image differs: deployed '$live_image', manifest '${manifest_image:-unknown}'"
    fi
  else
    warn 'GitLab deployment not installed (run Bonus install script first)'
  fi

  if kubectl -n gitlab get service gitlab >/dev/null 2>&1; then
    pass 'GitLab Kubernetes Service exists'
  else
    warn 'GitLab Service missing'
  fi

  if kubectl -n gitlab get pvc iot-gitlab-storage >/dev/null 2>&1; then
    pvc_state="$(kubectl -n gitlab get pvc iot-gitlab-storage -o jsonpath='{.status.phase}' 2>/dev/null || true)"
    if [[ "$pvc_state" == 'Bound' ]]; then pass 'GitLab PVC is Bound'; else warn "GitLab PVC status: ${pvc_state:-unknown}"; fi
  else
    warn 'GitLab persistent-volume claim missing'
  fi

  section 'GitLab access from Debian VM'
  url='http://gitlab.gitlab.svc.cluster.local:8081/users/sign_in'
  if has curl; then
    status="$(curl --noproxy '*' --silent --output /dev/null --write-out '%{http_code}' --max-time 6 "$url" 2>/dev/null || true)"
    case "$status" in
      200|301|302|303) pass "GitLab login page reachable via local URL (HTTP $status)" ;;
      *) warn "GitLab local URL not reachable (HTTP ${status:-none}); if installed, run bonus/scripts/IoT-start-gitlab-access.sh" ;;
    esac
  fi
  if [[ -d "$HOME/IoT-GitLab-worktree/.git" ]] || [[ -f "$HOME/IoT-GitLab-worktree/.git" ]]; then
    pass 'Local GitLab Git worktree exists'
  else
    warn 'Local GitLab Git worktree not found (bootstrap creates it)'
  fi
fi

section 'Result'
printf '%d error(s), %d warning(s).\n' "$errors" "$warnings"
if (( errors > 0 )); then
  printf 'Prerequisites have blocking problems. Resolve FAIL items before continuing.\n'
  exit 1
fi
printf 'Core prerequisites passed. WARN items may reflect components not yet installed or started.\n'
exit 0
