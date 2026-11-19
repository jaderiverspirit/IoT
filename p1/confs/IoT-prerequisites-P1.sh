#!/usr/bin/env bash
# Read-only P1 host preflight. Does not start, stop, or destroy VMs.
set -uo pipefail

P1_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT="$(cd "$P1_DIR/.." && pwd)"
errors=0
warnings=0

pass() { printf 'PASS  %s\n' "$1"; }
fail() { printf 'FAIL  %s\n' "$1"; errors=$((errors + 1)); }
warn() { printf 'WARN  %s\n' "$1"; warnings=$((warnings + 1)); }

printf '=== P1 prerequisites: Vagrant, VirtualBox, Debian 13 ===\n'
printf 'Project: %s\n\n' "$ROOT"

for tool in bash git vagrant VBoxManage ssh curl rsync ruby; do
  if command -v "$tool" >/dev/null 2>&1; then
    pass "$tool installed"
  else
    fail "$tool missing"
  fi
done

if command -v VBoxManage >/dev/null 2>&1; then
  if vb_version="$(VBoxManage --version 2>/dev/null)"; then
    pass "VirtualBox available ($vb_version)"
  else
    fail 'VirtualBox could not be queried'
  fi
fi

if command -v vagrant >/dev/null 2>&1; then
  printf '\n=== Installed Debian 13 box ===\n'
  if vagrant box list 2>/dev/null | grep -Fq 'IoT-Debian13-virtualbox (virtualbox,'; then
    pass 'IoT-Debian13-virtualbox is installed'
  else
    fail 'Missing Vagrant box IoT-Debian13-virtualbox'
  fi
fi

printf '\n=== P1 configuration syntax ===\n'
if [[ -f "$P1_DIR/Vagrantfile" ]]; then
  if command -v ruby >/dev/null 2>&1 && ruby -c "$P1_DIR/Vagrantfile" >/dev/null 2>&1; then
    pass 'P1 Vagrantfile Ruby syntax'
  else
    fail 'P1 Vagrantfile syntax check failed'
  fi
else
  fail 'P1 Vagrantfile missing'
fi

for script in IoT-server.sh IoT-worker.sh IoT-check.sh; do
  if [[ -f "$P1_DIR/scripts/$script" ]] && bash -n "$P1_DIR/scripts/$script"; then
    pass "$script Bash syntax"
  else
    fail "$script missing or invalid"
  fi
done

if command -v vagrant >/dev/null 2>&1; then
  if ( cd "$P1_DIR" && vagrant validate >/dev/null 2>&1 ); then
    pass 'P1 Vagrant configuration validates'
  else
    fail 'P1 Vagrant configuration did not validate'
  fi

  printf '\n=== Vagrant machine status (P1) ===\n'
  if p1_status="$(cd "$P1_DIR" && vagrant status 2>&1)"; then
    printf '%s\n' "$p1_status"
  else
    printf '%s\n' "$p1_status"
    fail 'Unable to read P1 Vagrant status'
  fi

  printf '\n=== Potential name conflict (P2) ===\n'
  if [[ -f "$ROOT/p2/Vagrantfile" ]]; then
    if p2_status="$(cd "$ROOT/p2" && vagrant status 2>&1)"; then
      printf '%s\n' "$p2_status"
      p2_state="$(printf '%s\n' "$p2_status" | awk '$1 == "hlehmannS" { if ($2 == "not" && $3 == "created") print "not created"; else print $2; exit }')"
      if [[ -n "$p2_state" && "$p2_state" != 'not created' ]]; then
        warn "P2 owns hlehmannS ($p2_state); destroy the disposable P2 VM before starting P1"
      fi
    else
      printf '%s\n' "$p2_status"
      warn 'Unable to check P2 Vagrant status'
    fi
  else
    warn 'P2 Vagrantfile not found; cannot check shared VM-name conflict'
  fi

  if command -v VBoxManage >/dev/null 2>&1; then
    vms="$(VBoxManage list vms 2>/dev/null || true)"
    p1_server_state="$(printf '%s\n' "${p1_status:-}" | awk '$1 == "hlehmannS" { if ($2 == "not" && $3 == "created") print "not created"; else print $2; exit }')"
    p1_worker_state="$(printf '%s\n' "${p1_status:-}" | awk '$1 == "hlehmannSW" { if ($2 == "not" && $3 == "created") print "not created"; else print $2; exit }')"
    if [[ "$p1_server_state" == 'not created' && "${p2_state:-}" == 'not created' ]] && grep -Fq '"hlehmannS"' <<< "$vms"; then
      warn 'hlehmannS is registered in VirtualBox but neither P1 nor P2 currently owns it'
    fi
    if [[ "$p1_worker_state" == 'not created' ]] && grep -Fq '"hlehmannSW"' <<< "$vms"; then
      warn 'hlehmannSW is registered in VirtualBox but not recognized by this P1 environment'
    fi
  fi
fi

printf '\nResults: %d error(s), %d warning(s).\n' "$errors" "$warnings"
if (( errors > 0 )); then
  printf 'P1 prerequisites NOT met. Resolve FAIL entries before running vagrant up.\n'
  exit 1
fi
printf 'P1 prerequisites met. Review warnings, then: cd p1 && vagrant up --provider=virtualbox\n'
