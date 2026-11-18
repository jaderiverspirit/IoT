#!/usr/bin/env bash
set -Eeuo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
state_dir="${HOME}/.config/iot"
mkdir -p "$state_dir"
chmod 700 "$state_dir"

kubectl config current-context | grep -qx k3d-iot
kubectl -n gitlab rollout status deploy/iot-gitlab --timeout=120s
curl --noproxy '*' --fail --silent --show-error \
  http://gitlab.gitlab.svc.cluster.local:8081/users/sign_in >/dev/null || {
	echo 'GitLab access unavailable. Run IoT-start-gitlab-access.sh.' >&2; exit 1;
  }

# Generate a personal access token with GitLab's own Rails API. Do not reuse a
# password, put a secret in the repository, or request GitHub credentials.
token_file="$state_dir/gitlab-bootstrap-token"
if [[ ! -s "$token_file" ]]; then
  (umask 077; openssl rand -hex 10 > "$token_file")
  token="$(cat "$token_file")"
  # Rails runner loads the Ruby script through standard input in a temporary
  # container file. This is a local single-node lab with cluster-admin access.
  kubectl -n gitlab exec -i deployment/iot-gitlab -- \
	env "IOT_GITLAB_PAT=$token" bash -c \
	'cat >/tmp/iot-bootstrap.rb && gitlab-rails runner /tmp/iot-bootstrap.rb; rc=$?; rm -f /tmp/iot-bootstrap.rb; exit "$rc"' \
	< "$root/bonus/scripts/IoT-bootstrap-rails.rb" || {
	  rm -f "$token_file"
	  echo 'Could not bootstrap GitLab token; inspect the gitlab pod logs.' >&2
	  exit 1
	}
fi

api='http://gitlab.gitlab.svc.cluster.local:8081/api/v4'
auth=(-H "PRIVATE-TOKEN: $(cat "$token_file")")
if ! curl --noproxy '*' --fail --silent --show-error "${auth[@]}" \
	"$api/user" > /dev/null; then
  echo 'Bootstrap token rejected or expired; remove ~/.config/iot/gitlab-bootstrap-token and rerun.' >&2
  exit 1
fi

# A publicly readable project is sufficient for Argo CD: it has no push token.
# Write credentials are required only for the VM user's git push.
if ! curl --noproxy '*' --silent --fail "${auth[@]}" \
	"$api/projects/root%2Fiot-gitops" >/dev/null; then
  curl --noproxy '*' --fail --silent --show-error "${auth[@]}" \
	--request POST --data-urlencode 'name=IoT-GitOps' \
	--data-urlencode 'path=iot-gitops' --data-urlencode 'visibility=public' \
	"$api/projects" > /dev/null
fi

repo='http://gitlab.gitlab.svc.cluster.local:8081/root/iot-gitops.git'
export GIT_ASKPASS="$root/bonus/scripts/IoT-git-askpass.sh"
export GIT_TERMINAL_PROMPT=0

# Seed the local GitLab repository with the *same GitOps manifests* as P3.
# Use a separate temp git repo: NEVER alter the 42 repository's git remote.
seed="$(mktemp -d)"
trap 'rm -rf "$seed"' EXIT
mkdir -p "$seed/p3/confs"
cp -a "$root/p3/confs/apps" "$seed/p3/confs/apps"
# Reset the *seed copy* to v1 even if P3's GitHub demonstration ended on v2.
# This ensures the bonus can independently demonstrate v1 -> v2 via GitLab.
sed -i -E 's#(wil42/playground:)v[12]#\1v1#' \
  "$seed/p3/confs/apps/IoT-deployment.yaml"
git -C "$seed" init -b main -q
git -C "$seed" add p3/confs/apps
git -C "$seed" -c user.name='IoT Lab' -c user.email='iot@localhost' \
  commit -m 'IoT initial GitOps manifests v1' -q
git -C "$seed" remote add origin "$repo"
# A repeated bootstrap does not overwrite prior GitLab changes.
if [[ -z "$(git ls-remote "$repo" refs/heads/main 2>/dev/null)" ]]; then
  git -C "$seed" push -u origin main
fi

worktree="${HOME}/IoT-GitLab-worktree"
if [[ ! -e "$worktree" ]]; then
  git clone "$repo" "$worktree"
fi

# Avoid two Argo Applications fighting over the same Deployment: the bonus
# replaces the GitHub app as the source of truth; it does not delete dev Pods.
kubectl -n argocd delete application iot-github --ignore-not-found --wait=true
kubectl apply -f "$root/bonus/confs/IoT-argocd-gitlab-application.yaml"
printf '\nGitLab repo: %s\n' "$repo"
printf 'Working tree: %s\n' "$worktree"
printf 'Argo CD Application: iot-gitlab\n'
echo 'Waiting for the initial local GitLab v1 manifests to reach the dev cluster...'
for attempt in $(seq 1 120); do
  current="$(kubectl -n dev get deployment iot-playground -o \
	jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null || true)"
  if [[ "$current" == 'wil42/playground:v1' ]]; then
	kubectl -n dev rollout status deployment/iot-playground --timeout=300s
	echo 'GitLab v1 deployed and Ready.'
	printf 'Next: ./bonus/scripts/IoT-set-local-version.sh v2\n'
	exit 0
  fi
  sleep 5
done
echo 'Local GitLab v1 deployment failed to reconcile with Argo CD.' >&2
kubectl -n argocd describe application iot-gitlab || true
exit 1
