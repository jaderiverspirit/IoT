#!/usr/bin/env bash
set -Eeuo pipefail
# Edits the deployment manifest in the checked-out repository. The user still
# commits and pushes it to their public GitHub repository as required.
[[ $# -eq 1 && ( "$1" == 'v1' || "$1" == 'v2' ) ]] || {
  echo 'Usage: ./p3/scripts/IoT-set-version.sh v1|v2' >&2; exit 2;
}
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
sed -i -E "s#(wil42/playground:)v[12]#\1${1}#" "$root/p3/confs/apps/IoT-deployment.yaml"
grep 'image: wil42/playground:' "$root/p3/confs/apps/IoT-deployment.yaml"
cat <<'EOF'
Now: git add p3/confs/apps/IoT-deployment.yaml && git commit -m 'IoT image update' && git push
The running app changes ONLY after a push to the GitHub repository watched by Argo CD.
EOF
