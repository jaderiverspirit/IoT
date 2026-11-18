#!/usr/bin/env bash
set -Eeuo pipefail
kubectl config current-context | grep -qx k3d-iot
kubectl -n gitlab get service gitlab >/dev/null

# Access the same GitLab URL from inside the Kubernetes cluster and the VM:
# inside: native Kubernetes DNS; outside: loopback + kubectl port-forward.
line='127.0.0.1 gitlab.gitlab.svc.cluster.local # IoT GitLab lab'
if ! grep -Fq "$line" /etc/hosts; then
  printf '%s\n' "$line" | sudo tee -a /etc/hosts >/dev/null
fi
state_dir="${HOME}/.config/iot"
mkdir -p "$state_dir"
chmod 700 "$state_dir"
pid_file="$state_dir/gitlab-portforward.pid"
if [[ -f "$pid_file" ]] && kill -0 "$(cat "$pid_file")" 2>/dev/null; then
  echo "Existing kubectl port-forward: PID $(cat "$pid_file")"
else
  nohup kubectl -n gitlab port-forward --address 127.0.0.1 \
	svc/gitlab 8081:8081 > "$state_dir/gitlab-portforward.log" 2>&1 </dev/null &
  echo "$!" > "$pid_file"
fi
for n in $(seq 1 40); do
  if curl --noproxy '*' --silent --fail --max-time 5 \
	'http://gitlab.gitlab.svc.cluster.local:8081/users/sign_in' >/dev/null; then
	echo 'Local GitLab ready at http://gitlab.gitlab.svc.cluster.local:8081'
	echo 'GitLab username: root'
	echo "Initial password: $(cat "$state_dir/gitlab-root-password")"
	exit 0
  fi
  sleep 3
done
echo 'GitLab not responding. See ~/.config/iot/gitlab-portforward.log' >&2
exit 1
