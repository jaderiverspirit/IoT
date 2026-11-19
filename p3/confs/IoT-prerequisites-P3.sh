#!/usr/bin/env bash
# Read-only P3 preflight for 42 Inception-of-Things.
# Run INSIDE the Debian VM used for P3 + Bonus, from any working directory.
# Installation tools and the Kubernetes cluster may be absent before initial setup.
# This script never installs packages, changes a cluster, or creates VMs.
set -uo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
P3_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
ROOT="$(cd -- "$P3_DIR/.." && pwd)"
REPO_URL='https://github.com/jaderiverspirit/IoT-hlehmann.git'
errors=0
warnings=0

pass() { printf 'PASS  %s\n' "$*"; }
warn() { printf 'WARN  %s\n' "$*"; warnings=$((warnings + 1)); }
fail() { printf 'FAIL  %s\n' "$*"; errors=$((errors + 1)); }
info() { printf 'INFO  %s\n' "$*"; }
has() { command -v "$1" >/dev/null 2>&1; }

printf '=== P3 prerequisites: Debian VM, Docker, K3d, Argo CD, GitHub ===\n'
printf 'Project: %s\n' "$ROOT"
printf 'Hostname: %s\n\n' "$(hostname 2>/dev/null || printf 'unknown')"

printf '=== Debian VM environment ===\n'
if [[ -r /etc/os-release ]]; then
  # shellcheck disable=SC1091
  . /etc/os-release
  info "OS: ${PRETTY_NAME:-unknown}"
  if [[ "${ID:-}" == 'debian' ]]; then
    pass 'Debian operating system detected'
  else
    warn 'P3 was tested on Debian; confirm this Linux VM is suitable'
  fi
else
  warn 'Unable to read /etc/os-release'
fi

if has systemd-detect-virt; then
  hypervisor="$(systemd-detect-virt --vm 2>/dev/null || true)"
  if [[ -n "$hypervisor" ]]; then
    pass "Inside a virtual machine ($hypervisor)"
  else
    warn 'No VM detected. P3 must execute inside a Linux virtual machine.'
  fi
else
  info 'systemd-detect-virt unavailable; verify that this is the Debian VM'
fi

cores="$(getconf _NPROCESSORS_ONLN 2>/dev/null || printf '0')"
if [[ "$cores" =~ ^[0-9]+$ ]] && (( cores >= 4 )); then
  pass "CPU: $cores logical processors available"
else
  warn "CPU: ${cores} logical processors available (4 recommended)"
fi
if [[ -r /proc/meminfo ]]; then
  total_kib="$(awk '/^MemTotal:/ {print $2; exit}' /proc/meminfo)"
  if [[ "$total_kib" =~ ^[0-9]+$ ]]; then
    total_mib=$((total_kib / 1024))
    if (( total_mib >= 6144 )); then
      pass "RAM: about ${total_mib} MiB assigned"
    else
      warn "RAM: about ${total_mib} MiB (6 GiB or more recommended for P3; more for GitLab Bonus)"
    fi
  fi
fi
free_kib="$(df -Pk "$ROOT" 2>/dev/null | awk 'NR==2 {print $4}')"
if [[ "${free_kib:-}" =~ ^[0-9]+$ ]]; then
  free_gib=$((free_kib / 1024 / 1024))
  if (( free_gib >= 10 )); then
    pass "Disk: approximately ${free_gib} GiB currently available"
  else
    warn "Disk: approximately ${free_gib} GiB available; check capacity for container images"
  fi
fi

printf '\n=== Basic commands and project files ===\n'
for tool in bash git curl sudo; do
  if has "$tool"; then pass "$tool installed"; else fail "$tool missing"; fi
done
for script in IoT-install-tools.sh IoT-create-cluster.sh IoT-install-argocd.sh IoT-configure-github.sh IoT-set-version.sh IoT-check.sh; do
  path="$P3_DIR/scripts/$script"
  if [[ ! -f "$path" ]]; then
    fail "Missing p3/scripts/$script"
  elif bash -n "$path" 2>/dev/null; then
    pass "$script Bash syntax"
    if [[ ! -x "$path" ]]; then
      warn "$script is not executable; use bash scripts/$script or chmod +x"
    fi
  else
    fail "$script has a Bash syntax error"
  fi
done
for manifest in 'confs/apps/IoT-deployment.yaml' 'confs/IoT-github-application.template.yaml'; do
  if [[ -f "$P3_DIR/$manifest" ]]; then
    pass "p3/$manifest found"
  else
    fail "Missing p3/$manifest"
  fi
done

printf '\n=== GitHub connectivity ===\n'
if has git; then
  if has timeout; then
    if remote_main="$(GIT_TERMINAL_PROMPT=0 timeout 15 git ls-remote --heads "$REPO_URL" main 2>/dev/null)" && [[ -n "$remote_main" ]]; then
      pass "Public GitHub main branch reachable ($REPO_URL)"
    else
      warn 'Could not access public GitHub main branch; check Internet/DNS before GitOps demonstration'
    fi
  else
    info 'timeout not installed; skipping network probe (run git ls-remote manually)'
  fi
fi

printf '\n=== P3 installation state (informational before setup) ===\n'
if has docker; then
  if docker info --format '{{.ServerVersion}}' >/dev/null 2>&1; then
    pass "Docker daemon accessible ($(docker info --format '{{.ServerVersion}}' 2>/dev/null))"
  else
    warn 'Docker CLI found but daemon is unavailable to this user; check service and docker group'
  fi
else
  info 'Docker not installed yet; p3/scripts/IoT-install-tools.sh installs it'
fi

if has k3d; then
  pass 'k3d command installed'
  if k3d cluster list 2>/dev/null | awk 'NR>1 && $1 == "iot" {found=1} END {exit !found}'; then
    pass 'K3d cluster iot exists'
  else
    info 'K3d cluster iot not found yet; create it during P3 setup'
  fi
else
  info 'k3d not installed yet; p3/scripts/IoT-install-tools.sh installs it'
fi

if has kubectl; then
  pass 'kubectl command installed'
  current_context="$(kubectl config current-context 2>/dev/null || true)"
  if [[ "$current_context" == 'k3d-iot' ]]; then
    pass 'kubectl context: k3d-iot'
    for ns in argocd dev; do
      if kubectl get namespace "$ns" >/dev/null 2>&1; then
        pass "Namespace $ns exists"
      else
        info "Namespace $ns not created yet"
      fi
    done
    if kubectl -n argocd get application iot-github >/dev/null 2>&1; then
      info 'Argo CD application iot-github exists (verify Synced/Healthy in P3 checks)'
    elif kubectl -n argocd get application iot-gitlab >/dev/null 2>&1; then
      info 'Bonus application iot-gitlab is active; switch to GitHub before the P3 demonstration'
    else
      info 'No P3 Argo CD application found yet; configure GitHub during P3 setup'
    fi
  elif [[ -z "$current_context" ]]; then
    info 'No current kubectl context yet; this is normal before creating the cluster'
  else
    warn "kubectl context is $current_context, expected k3d-iot (do not modify another cluster)"
  fi
else
  info 'kubectl not installed yet; p3/scripts/IoT-install-tools.sh installs it'
fi

printf '\nResults: %d error(s), %d warning(s).\n' "$errors" "$warnings"
if (( errors > 0 )); then
  printf 'P3 prerequisites need attention. Resolve FAIL entries before starting.\n'
  exit 1
fi
printf 'P3 preflight complete. Review WARN entries, then follow README Part 3.\n'
