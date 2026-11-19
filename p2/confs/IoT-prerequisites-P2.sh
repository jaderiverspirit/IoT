#!/usr/bin/env bash
# Read-only prerequisite checks for Inception-of-Things Part 2.
set -uo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
P2="$ROOT/p2"
P1="$ROOT/p1"
errors=0
warnings=0
pass() { printf 'PASS  %s\n' "$*"; }
warn() { printf 'WARN  %s\n' "$*"; warnings=$((warnings + 1)); }
fail() { printf 'FAIL  %s\n' "$*"; errors=$((errors + 1)); }

echo '=== P2 prerequisites: Vagrant + VirtualBox + Debian 13 ==='
printf 'P2 directory: %s\n\n' "$P2"

for program in bash git vagrant VBoxManage ssh curl rsync ruby; do
  if command -v "$program" >/dev/null 2>&1; then
    pass "$program installed"
  else
    fail "$program missing"
  fi
done

if command -v VBoxManage >/dev/null 2>&1; then
  if version=$(VBoxManage --version 2>/dev/null); then
    pass "VirtualBox responds ($version)"
  else
    fail 'VirtualBox is installed but not responding'
  fi
fi
if command -v vagrant >/dev/null 2>&1; then
  if version=$(vagrant --version 2>/dev/null); then
    pass "$version"
  else
    fail 'Vagrant did not respond'
  fi
  if boxes=$(vagrant box list 2>/dev/null); then
    if grep -qE '^IoT-Debian13-virtualbox[[:space:]]+\(virtualbox,' <<<"$boxes"; then
      pass 'Debian 13 box IoT-Debian13-virtualbox is installed'
    else
      fail 'Missing Vagrant box: IoT-Debian13-virtualbox (virtualbox)'
    fi
  else
    fail 'Could not list Vagrant boxes'
  fi
fi

if [[ -f "$P2/Vagrantfile" ]]; then
  pass 'P2 Vagrantfile found'
  if command -v ruby >/dev/null 2>&1 && ruby -c "$P2/Vagrantfile" >/dev/null 2>&1; then
    pass 'P2 Vagrantfile Ruby syntax'
  else
    fail 'P2 Vagrantfile Ruby syntax'
  fi
  if grep -q "hlehmannS" "$P2/Vagrantfile"; then
    pass 'P2 machine name hlehmannS present'
  else
    fail 'P2 machine name hlehmannS missing'
  fi
else
  fail 'P2 Vagrantfile missing'
fi

for script in IoT-install.sh IoT-check.sh; do
  file="$P2/scripts/$script"
  if [[ ! -f "$file" ]]; then
    fail "Missing P2 script: $script"
  elif bash -n "$file"; then
    pass "$script Bash syntax"
  else
    fail "$script Bash syntax"
  fi
done
if [[ -f "$P2/confs/IoT-apps.yaml" ]]; then
  pass 'P2 Kubernetes manifests found'
else
  fail 'P2 Kubernetes manifests missing'
fi

if command -v vagrant >/dev/null 2>&1; then
  echo
  echo '=== Vagrant machine status (P2) ==='
  (cd "$P2" && vagrant status) || fail 'Cannot read P2 Vagrant status'
  if [[ -f "$P1/Vagrantfile" ]]; then
    echo
    echo '=== Vagrant machine status (P1; name conflict check) ==='
    (cd "$P1" && vagrant status) || warn 'Cannot read P1 Vagrant status'
  fi
fi

# Compare registered VirtualBox VM with the VM that P2 actually owns.
if command -v VBoxManage >/dev/null 2>&1; then
  vms=$(VBoxManage list vms 2>/dev/null || true)
  if grep -q '^"hlehmannS" ' <<<"$vms"; then
    registered_id=$(sed -n 's/^"hlehmannS" {\([^}]*\)}$/\1/p' <<<"$vms")
    p2_idfile="$P2/.vagrant/machines/hlehmannS/virtualbox/id"
    p2_id=""
    [[ -f "$p2_idfile" ]] && p2_id=$(tr -d '\r\n' < "$p2_idfile")
    if [[ -n "$p2_id" && "$registered_id" == "$p2_id" ]]; then
      pass 'Registered hlehmannS belongs to P2'
    else
      warn 'VirtualBox name hlehmannS is registered but not owned by this P2 environment; resolve before vagrant up'
    fi
  else
    pass 'VirtualBox VM name hlehmannS is available'
  fi
fi

printf '\nResults: %d error(s), %d warning(s).\n' "$errors" "$warnings"
if (( errors > 0 )); then
  echo 'P2 prerequisites failed; correct FAIL results before starting.'
  exit 1
fi
echo 'P2 local prerequisites passed. Next: cd p2 && vagrant up --provider=virtualbox'
