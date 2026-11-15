#!/usr/bin/env bash
set -Eeuo pipefail
case "${1:-}" in
  *sername*) printf 'root\n' ;;
  *assword*) cat "${HOME}/.config/iot/gitlab-bootstrap-token" ;;
  *) exit 1 ;;
esac
