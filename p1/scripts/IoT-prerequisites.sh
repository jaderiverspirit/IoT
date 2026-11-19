#!/usr/bin/env bash
# P1 host preflight: run on the Linux machine that will execute Vagrant.
set -uo pipefail

P1_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
errors=0
warnings=0

ok()   { printf 'PASS  %s\n' "$1"; }
fail() { printf 'FAIL  %s\n' "$1"; errors=$((errors + 1)); }
warn() { printf 'WARN  %s\n' "$1"; warnings=$((warnings + 1)); }

printf '%s\n' '=== P1 prerequisites: Vagrant + VirtualBox + Debian 13 ==='
printf 'P1 directory: %s\n\n' "$P1_DIR"

for command_name in bash git vagrant VBoxManage ssh curl rsync ruby; do
  if command -v "$command_name" >/dev/null 2>&1; then
    ok "$command_name installed"
  else
    fail "$command_name missing"
  fi
done

if command -v VBoxManage >/dev/null 2>&1; then
  if VBoxManage --version >/dev/null 2>&1; then
    ok "VirtualBox responds ($(VBoxManage --version))"
  else
    fail 'VirtualBox is installed but cannot be contacted'
  fi
fi

if command -v vagrant >/dev/null 2>&1; then
  ok "$(vagrant --version)"
  if vagrant box list 2>/dev/null | grep -Fq 'IoT-Debian13-virtualbox (virtualbox,'; then
    ok 'Debian 13 box IoT-Debian13-virtualbox is installed'
  else
    fail 'Debian 13 box missing: vagrant box add --name IoT-Debian13-virtualbox /path/to/IoT-Debian13-virtualbox.box'
  fi
fi

if [[ -f "$P1_DIR/Vagrantfile" ]]; then
  ok 'P1 Vagrantfile found'
  if command -v ruby >/dev/null 2>&1; then
    if ruby -c "$P1_DIR/Vagrantfile" >/dev/null 2>&1; then
      ok 'P1 Vagrantfile Ruby syntax'
    else
      fail 'P1 Vagrantfile has invalid Ruby syntax'
    fi
  fi
else
  fail 'P1 Vagrantfile missing'
fi

for script in IoT-server.sh IoT-worker.sh IoT-check.sh; do
  path="$P1_DIR/scripts/$script"
  if [[ ! -f "$path" ]]; then
    fail "$script missing"
  elif bash -n "$path"; then
    ok "$script Bash syntax"
  else
    fail "$script Bash syntax error"
  fi
done

if command -v VBoxManage >/dev/null 2>&1; then
  if registered="$(VBoxManage list vms 2>/dev/null)"; then
    for vm in hlehmannS hlehmannSW; do
      if grep -Fq '"'"$vm"'"' <<< "$registered"; then
        warn "VirtualBox VM $vm is already registered. Ensure it belongs to P1 (P2 also uses hlehmannS)."
      fi
    done
  else
    warn 'Could not list registered VirtualBox VMs'
  fi
fi

printf '\nResults: %d error(s), %d warning(s).\n' "$errors" "$warnings"
if (( errors > 0 )); then
  printf '%s\n' 'P1 is NOT ready. Fix the errors above before running vagrant up.'
  exit 1
fi
printf '%s\n' 'P1 local prerequisites passed. Next: cd p1 && vagrant up --provider=virtualbox'
