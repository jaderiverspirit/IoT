# IoT (subject v4.1)

A four-part, Linux-first implementation of the 42 **Inception-of-Things** subject, including the GitLab bonus. All project configuration is kept in `p1/`, `p2/`, `p3/` and `bonus/`, with executable provisioning scripts in each `scripts/` directory and Kubernetes manifests in `confs/`.

> **Important:** Verify in a Linux virtual machine before submission.

## 0. Requirements and environment

The entire exercise **must be performed in a VM**, per subject page 4. On a physical Linux workstation, start a Linux *outer VM* with nested virtualization available. Run Vagrant for Parts 1 and 2 **inside that VM**. For Part 3, use a Linux VM with Docker and K3d (without Vagrant); this can be the outer VM itself. To reduce nested virtualization complexity you may use a native Linux host with KVM/libvirt as the **provider** *inside an outer VM with nested KVM*, but running the project only on the physical host is not compliant with the subject.

**Suggested lab allocations** (subject P1 sizes are deliberate):

| Layer | Minimum for practical testing | Notes |
|---|---|---|
| Outer Linux VM | 4–6 vCPU, 16 GiB RAM, 80 GiB free, nested virtualization | Run Vagrant and K3d here. 12 GiB RAM may work with fewer parallel guests. |
| P1 IoTS | 2 vCPU, 2048 MiB RAM (default) | Rocky Linux 10 K3s server; override to 1 CPU / 1024 MiB with `IOT_P1_TINY=1` only if needed |
| P1 IoTSW | 1 vCPU, 1024 MiB RAM | Rocky Linux 10 K3s agent |
| P2 IoTS | 2 vCPU, 2048 MiB RAM | K3s server, Traefik and 5 nginx pods |
| P3 and bonus | preferably 4+ vCPU, 10–12+ GiB free RAM, 40+ GiB storage | Docker, K3d, Argo CD, full GitLab CE omnibus image |

**Linux host prerequisites for Parts 1 and 2:** `vagrant`, `curl`, `git`, and either `VirtualBox` (default) or `libvirt` plus `vagrant-libvirt` (often more reliable on Linux). For libvirt use `IOT_VAGRANT_PROVIDER=libvirt` consistently; Vagrant is explicitly directed to the image's **vendor-hosted** URL. The official Rocky Linux 10 images are published at `https://dl.rockylinux.org/pub/rocky/10/images/x86_64/` (x86_64 only). On an Ubuntu outer VM use `vagrant plugin install vagrant-libvirt` or your distribution's `vagrant-libvirt` package, and make sure your login is authorized for libvirt.

Parts 1 and 2 reuse `IoTS` as a logical Vagrant machine name in *different Vagrant environments*. **Stop/destroy one part before starting the other** to avoid IP collisions at `192.168.56.110`.

### Names, interfaces and network

- `IoTS`: `192.168.56.110` on a Vagrant private interface; K3s controller (P1) or single node (P2).
- `IoTSW`: `192.168.56.111` on its Vagrant private interface; K3s agent (P1).
- VM names/hostnames use the requested `IoT` prefix; Kubernetes resource names are lowercase, as Kubernetes requires DNS-compatible names.
- `app1.com` -> app1 (1 replica); `app2.com` -> app2 (3 replicas); *any other Host* -> app3 (1 replica).
- K3d cluster: `iot`; namespaces: `argocd`, `dev` (and bonus `gitlab`).
- Part 3 GitOps example uses the subject's official sample `wil42/playground:v1` and `wil42/playground:v2`, both exposed on TCP 8888 through a ClusterIP and `kubectl port-forward`.

## 1. Part 1 — Vagrant, K3s controller and worker

From the project root **inside the Linux outer VM**:

```bash
cd p1
vagrant up --provider=virtualbox
# On a libvirt-capable Linux VM instead:
# IOT_VAGRANT_PROVIDER=libvirt vagrant up --provider=libvirt
vagrant status
vagrant ssh IoTS
# in the IoTS guest:
#   sudo kubectl get nodes -o wide
#   ip -brief address
#   exit
vagrant ssh IoTSW
# in the IoTSW guest:
#   sudo systemctl status k3s-agent --no-pager
#   exit
./scripts/IoT-check.sh
```

The subject **advises** 1 CPU / 512–1024 MiB for the lab; the current K3s published *minimum* for a server is 2 CPU / 2 GiB, so the default server size follows the modern K3s minimum rather than the subject's non-binding resource advice. Optional `IOT_P1_TINY=1 vagrant up --provider=virtualbox` uses the smaller resource profile but may be unstable on current K3s.

**Expected state:** both Vagrant VMs `running`, with `iots` and `iotsw` in Kubernetes `Ready`; an interface with `.110` on the server and `.111` on the worker; `vagrant ssh` never prompts for the machine's password. The Rocky Linux 10 provisioning scripts also install `kernel-modules-extra` (for `br_netfilter` and overlay) and configure firewalld for the private network and K3s pod/service CIDRs. K3s installs `kubectl` on the server (the separate `kubectl` binary/symlink is provided by K3s). The `.iot-join-token` file is created by the Vagrantfile with owner-only permissions before provisioning, distributed to both VMs via the Vagrant synced folder and ignored by Git.

**Before P2:** `vagrant destroy -f` (from `p1/`) or `vagrant halt`.

## 2. Part 2 — three nginx web apps and Traefik Ingress

```bash
cd p2
vagrant up --provider=virtualbox
# OR: IOT_VAGRANT_PROVIDER=libvirt vagrant up --provider=libvirt
vagrant ssh IoTS -c 'sudo kubectl get deployment,pods,service,ingress -o wide'
./scripts/IoT-check.sh

curl -H 'Host: app1.com' http://192.168.56.110/
curl -H 'Host: app2.com' http://192.168.56.110/
curl -H 'Host: other.example' http://192.168.56.110/
```

The three responses must contain respectively `Hello from app1.`, `Hello from app2.`, `Hello from app3.`. Host headers are sent explicitly so DNS changes to public `.com` domains are **not** necessary. The `Ingress` resource in `p2/confs/IoT-apps.yaml` includes host rules plus a Kubernetes `defaultBackend`. `app2` has exactly **three replicas**, and the two other deployments have one each. K3s's default Traefik ingress controller and ServiceLB are intentionally left enabled. Show the Ingress object using `sudo kubectl describe ingress iot-routing` during evaluation.

If the guest has an active firewall, allow incoming port 80 on the guest's private interface without exposing it to public networks. Check `sudo ss -lntp | grep :80`, Traefik and ServiceLB pods (`sudo kubectl -n kube-system get pods`), and host-only networking when diagnosing a failed host curl.

**Before P3:** from `p2/`, `vagrant halt` (or `vagrant destroy -f`).

## 3. Part 3 — K3d, Argo CD and public GitHub source

**This part is deliberately not created by a Vagrantfile.** The subject requires K3d running in a Linux VM without Vagrant. Use an Ubuntu 24.04+ or Debian 12+ Linux VM with sufficient disk/RAM, with the repository present. Commands below run as a **regular, sudo-capable Linux user**.

```bash
# From project root inside the Part 3 Linux VM:
./p3/scripts/IoT-install-tools.sh
newgrp docker	 # required until a new login activates Docker group
./p3/scripts/IoT-create-cluster.sh
./p3/scripts/IoT-install-argocd.sh
```

The first script installs Docker Engine from its official signed APT repository, K3d from the official installer, and kubectl from the official Kubernetes release; install scripts are retained and may be shown during the defense. `docker` group membership is effectively root-equivalent; restrict this setup to your VM lab.

### Required user action: create and push your public GitHub repository

Create an empty public repository in your own GitHub account, then from your checked-out project directory:

```bash
# If this is a new directory that is not already under Git:
git init -b main
# Only for a NEW repository (do not overwrite your existing 42 remote):
git remote add origin https://github.com/jaderiverspirit/IoT.git
git add p1 p2 p3 bonus tests README.md .gitignore
git commit -m 'Implement IoT p1 p2 p3 and bonus'
git push -u origin main

# Then tell Argo CD where the *real* public GitHub repository is:
./p3/scripts/IoT-configure-github.sh \
  https://github.com/jaderiverspirit/IoT.git
```

If the directory already belongs to a Git repository, keep your existing origin/branch and push `p3/confs/apps/` to its `main` branch; the `IoT-configure-github.sh` script assumes `main`. The `git ls-remote` check prevents registering an inaccessible repository. The Argo Application watches `p3/confs/apps` with automatic sync, pruning and self-healing.

### P3 evaluation: change `v1` to `v2` in GitHub

```bash
./p3/scripts/IoT-check.sh
# In a separate terminal, keep the local application service port open:
kubectl -n dev port-forward svc/iot-playground 8888:8888
# In another terminal:
curl http://127.0.0.1:8888/		 # expected: {"status":"ok", "message":"v1"}
./p3/scripts/IoT-set-version.sh v2
git add p3/confs/apps/IoT-deployment.yaml
git commit -m 'IoT deploy v2 via GitHub'
git push
# Wait for Argo CD automatic reconciliation (typically within minutes):
kubectl -n argocd get application iot-github -w
kubectl -n dev rollout status deploy/iot-playground --timeout=300s
curl http://127.0.0.1:8888/		 # expected: {"status":"ok", "message":"v2"}
```

Argo CD UI: `kubectl -n argocd port-forward svc/argocd-server 8082:443`, then open `https://127.0.0.1:8082` inside the VM. Username: `admin`. Initial password: `kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo`. The certificate warning is expected for a local self-signed installation. Check for `Synced` and `Healthy`.

## 4. Bonus — local GitLab as the actual Argo CD GitOps source

GitLab is deployed **in the same K3d cluster** using the official `gitlab/gitlab-ce:latest` image and a persistent volume, and placed inside the dedicated `gitlab` namespace. The external URL is intentionally the cluster's real service DNS name:

`http://gitlab.gitlab.svc.cluster.local:8081`

Argo CD inside Kubernetes can resolve the URL natively. The Linux VM reaches that *same URL* through a locally managed `kubectl port-forward` and a scoped `/etc/hosts` entry. A separate worktree in `$HOME/IoT-GitLab-worktree` is created for commits. Secret material is written only under `$HOME/.config/iot/` and kept **out of Git**.

**Prerequisite:** successfully complete and test all of Part 3 first. Allow at least 10–12 GiB of usable RAM for the Part 3/bonus Linux VM and **25 GiB** GitLab persistent storage, plus extra space for Docker layers, logs and system. The official image is large; initial boot, database migrations and Rails startup can take a while. 

```bash
# In the P3 Linux VM, from the project root:
./bonus/scripts/IoT-install-gitlab.sh
./bonus/scripts/IoT-start-gitlab-access.sh
# Browser URL: http://gitlab.gitlab.svc.cluster.local:8081
# Username: root. First-run password printed by the preceding script.
./bonus/scripts/IoT-bootstrap-local-repo.sh
./bonus/scripts/IoT-check.sh
```

`IoT-bootstrap-local-repo.sh` uses GitLab's documented **Rails PAT API** to create a bootstrap personal access token, creates a **public local GitLab project** with the API, seeds it with the same `p3/confs/apps/` manifests (reset to `v1` in the local GitLab seed, independently of the completed GitHub demonstration), creates a distinct VM worktree, and registers `iot-gitlab` as the Argo CD Application. The public GitLab project allows Argo CD to read without a private token. The local Git push uses an `askpass` helper and token file, not credentials embedded in a Git URL. The previously configured `iot-github` Argo CD Application is deleted before enabling `iot-gitlab`, so two controllers will not fight over the **same** Kubernetes deployment.

### Bonus evaluation: update from local GitLab (NOT GitHub)

```bash
./bonus/scripts/IoT-set-local-version.sh v2
# The script commits to LOCAL GitLab, pushes, waits for Argo CD's reconciliation,
# checks the new image in dev, and checks rollout status.
# While running another terminal with:
kubectl -n dev port-forward svc/iot-playground 8888:8888
# Check actual response:
curl http://127.0.0.1:8888/		  # {"status":"ok", "message":"v2"}
./bonus/scripts/IoT-set-local-version.sh v1
curl http://127.0.0.1:8888/		  # {"status":"ok", "message":"v1"}
./bonus/scripts/IoT-check.sh
```

**Proof the bonus actually works:** `kubectl -n argocd get application iot-gitlab -o yaml` must show a `source.repoURL` under `gitlab.gitlab.svc.cluster.local:8081`; changing the tag in local GitLab must update the live deployment in `dev` and the response on port 8888. Editing the original GitHub repository should *not* be needed for this bonus flow.

**Caveats:** GitLab's `latest` tag changes over time. A newly created lab will install the current official image; an existing persistent GitLab install must follow GitLab's supported upgrade sequence. GitLab root password only configures a fresh data volume; changing the generated secret does not automatically rotate an already initialized root account. Local port forwarding must remain alive to use GitLab from the VM. Do not publicly expose this lab or check passwords/PATs into Git. Bonus tests are not substitutes for passing P1/P2/P3.

## 5. Evaluation evidence checklist

| Requirement | Command / evidence | Expected |
|---|---|---|
| P1 two VMs | `cd p1 && vagrant status` | `IoTS`, `IoTSW` running |
| P1 passwordless | `vagrant ssh IoTS`, `vagrant ssh IoTSW` | no VM password prompt |
| P1 IPs and K3s | `sudo kubectl get nodes -o wide`; `ip a` | `.110`, `.111`, two Ready nodes |
| P1 roles | `sudo systemctl is-active k3s`, `sudo systemctl is-active k3s-agent` | server / agent respectively |
| P2 three apps | `sudo kubectl get deploy,pod,svc,ingress` | app1=1, app2=3, app3=1 |
| P2 Ingress | `curl -H 'Host: app1.com|app2.com|other...' 192.168.56.110` | correct default routing |
| P3 namespaces | `kubectl get ns` | `argocd`, `dev` |
| P3 GitOps | Argo Application source URL, GitHub commit, live `curl` | v1 then v2 |
| Bonus namespace | `kubectl -n gitlab get pods,pvc,svc` | local GitLab running |
| Bonus source | `kubectl -n argocd get application iot-gitlab -o yaml` | internal GitLab service URL |
| Bonus GitOps | `IoT-set-local-version.sh v2` and `curl` | update via GitLab and Argo CD |

## 6. Common troubleshooting

- **No nested virtualization:** `grep -Ec '(vmx|svm)' /proc/cpuinfo` and `ls /dev/kvm`. Enable nested virtualization in the outer VM's hypervisor; VirtualBox can be more fragile than KVM nested on Linux.
- **Vagrant port/IP conflicts:** never run `p1` and `p2` at the same time because both define `IoTS` at `.110`. Check existing host-only networks with `ip a`.
- **Vagrant libvirt:** always select the matching box file with `IOT_VAGRANT_PROVIDER=libvirt` *and* `--provider=libvirt`.
- **P1 worker cannot join:** check that `/vagrant/.iot-join-token` exists inside both guests, `systemctl status k3s`, and TCP 6443 between `.110` and `.111`.
- **P2 default route fails:** inspect Traefik logs using `sudo kubectl -n kube-system logs deployment/traefik`, check `kubectl describe ingress iot-routing` and ensure the `Host` header goes to **the VM private IP**.
- **Docker socket permission:** after installing tools, open a new login or `newgrp docker`; run `docker info` without sudo.
- **Argo CD does not sync:** `kubectl -n argocd describe application iot-github` (or `iot-gitlab`), inspect `argocd-repo-server` logs, verify source repo/branch/path and outbound connectivity.
- **GitLab pod pending:** `kubectl -n gitlab describe pod -l app=iot-gitlab`; check RAM, disk and `local-path` storage provisioning. Do not attempt bonus on a 2 GiB VM.
- **GitLab Rails fails:** `kubectl -n gitlab logs deploy/iot-gitlab --tail=200`; first boot can be slow. Ensure root password secret exists before the deployment starts.
- **GitLab cannot be reached from VM:** rerun `IoT-start-gitlab-access.sh`; check its log under `~/.config/iot/` and `/etc/hosts` entry. The GitLab URL must stay consistent with Argo CD's source.

## 7. References

- Rocky Linux vendor-hosted Vagrant images: https://dl.rockylinux.org/pub/rocky/10/images/x86_64/
- Vagrant box URLs and box settings: https://developer.hashicorp.com/vagrant/docs/vagrantfile/machine_settings
- K3s installation: https://docs.k3s.io/quick-start
- K3s hardware requirements: https://docs.k3s.io/installation/requirements
- Traefik Kubernetes Ingress default backend: https://doc.traefik.io/traefik/reference/routing-configuration/kubernetes/ingress/
- K3d: https://k3d.io/stable/
- Argo CD installation: https://argo-cd.readthedocs.io/en/stable/getting_started/
- GitLab official Docker images and configuration: https://docs.gitlab.com/install/docker/installation/
- GitLab documented PAT bootstrap from Rails: https://docs.gitlab.com/user/profile/personal_access_tokens/

## 8. Before submitting

1. Run all runtime validations on the target Linux VM: this archive is source code, not a deployed cluster.
2. Record successful `vagrant`, `kubectl`, Argo and GitLab output for the defense. Do not commit the generated join token or user credentials.
3. Re-run `python3 tests/IoT-static-checks.py` after changes.
4. The subject explicitly states that a failed mandatory requirement prevents the **bonus** being assessed.

## 9. Quick acceptance checklist — group preflight & peer evaluation

### General rules and submission

| Check | Requirement | Evidence / acceptance criterion |
|---|---|---|
| ☐ | Project executed **inside a Linux VM** | Show the evaluation VM and its virtualization setup; do not rely on a physical-host-only demonstration. |
| ☐ | Correct root folders and placement | `ls -d p1 p2 p3 bonus`; each part has its `scripts/` and `confs/` directory, and configuration/scripts are committed. |
| ☐ | Team login and repository naming are compliant | VMs use `<login>S` / `<login>SW`; the **public GitHub** repository name contains a team member's actual login. |
| ☐ | Reproducible provisioning and no committed secrets | Show `p1/Vagrantfile`, `p2/Vagrantfile`, `p3/scripts/IoT-install-tools.sh` and bonus scripts; check `git status --short` and `git ls-files` (no join token, passwords or PATs). |

### P1 — Vagrant + K3s server/worker

| Check | Requirement | Evidence / acceptance criterion |
|---|---|---|
| ☐ | Two **Vagrant** VMs with correct names | `cd p1 && vagrant status` → `IoTS` and `IoTSW` are running (and match actual team login). |
| ☐ | Current distribution from **vendor-hosted** Vagrant image | Inspect `p1/Vagrantfile`: `config.vm.box_url` points to the distribution publisher, not just the HashiCorp registry. |
| ☐ | Correct guest hostnames and **dedicated interface/IPs** | `cd p1 && vagrant ssh IoTS -c 'hostname; ip -br a'` → `IoTS`, `192.168.56.110`; repeat with `IoTSW` → `192.168.56.111`. |
| ☐ | **Passwordless SSH** into both VMs | `cd p1 && vagrant ssh IoTS -c hostname && vagrant ssh IoTSW -c hostname` → no guest password requested. |
| ☐ | K3s roles + usable `kubectl` | `cd p1 && vagrant ssh IoTS -c 'sudo kubectl get nodes -o wide'` → **2 Ready nodes**; `k3s` active on server, `k3s-agent` active on worker. |
| ☐ | Complete P1 demonstration | `cd p1 && ./scripts/IoT-check.sh` → all checks succeed. **Stop P1 before starting P2.** |

### P2 — K3s + three web apps + Ingress

| Check | Requirement | Evidence / acceptance criterion |
|---|---|---|
| ☐ | Exactly one Vagrant VM, server role, correct IP | `cd p2 && vagrant status` → only `IoTS` running; `vagrant ssh IoTS -c 'ip -br a; sudo kubectl get nodes'` → `192.168.56.110`, Ready. |
| ☐ | **Three running web applications** and Services | `cd p2 && vagrant ssh IoTS -c 'sudo kubectl get deploy,pods,svc'` → app1, app2, app3 resources all healthy. |
| ☐ | **App2 = 3 replicas** (app1/app3 = 1 each) | `cd p2 && vagrant ssh IoTS -c 'sudo kubectl get deployments'` → ready replica counts `1/1`, `3/3`, `1/1`. |
| ☐ | Ingress rules exist and can be explained | `cd p2 && vagrant ssh IoTS -c 'sudo kubectl describe ingress iot-routing'` → `app1.com`, `app2.com`, and default backend `iot-app3`. |
| ☐ | `Host: app1.com` returns **app1** | `curl -H 'Host: app1.com' http://192.168.56.110/` → `Hello from app1.` |
| ☐ | `Host: app2.com` returns **app2** | `curl -H 'Host: app2.com' http://192.168.56.110/` → `Hello from app2.` |
| ☐ | Any other Host returns **app3** | `curl -H 'Host: unknown.example' http://192.168.56.110/` → `Hello from app3.` |
| ☐ | Complete P2 demonstration | `cd p2 && ./scripts/IoT-check.sh` → all checks succeed. **Stop P2 before P3.** |

### P3 — Docker + K3d + Argo CD + public GitHub GitOps

| Check | Requirement | Evidence / acceptance criterion |
|---|---|---|
| ☐ | **No Vagrant** for P3; required tools installable by script | Show `p3/scripts/IoT-install-tools.sh`; `docker info`, `k3d cluster list`, `kubectl version --client` work in the Linux VM. |
| ☐ | K3d cluster and **two required namespaces** | `kubectl config current-context` → `k3d-iot`; `kubectl get ns argocd dev` → both Active. |
| ☐ | Argo CD installed and functional | `kubectl -n argocd get pods,application` → Argo components healthy; `iot-github` present. Show UI `Synced` / `Healthy`. |
| ☐ | **Public, online GitHub** repository used by Argo CD | `kubectl -n argocd get application iot-github -o yaml` → real GitHub URL, correct branch/path; repository opens publicly and contains `p3/confs/apps/`. |
| ☐ | Deployed application in `dev` with **v1** | `kubectl -n dev get pods,deploy,svc`; `kubectl -n dev get deploy iot-playground -o jsonpath='{.spec.template.spec.containers[0].image}'` → `wil42/playground:v1` initially. |
| ☐ | **Actual GitOps update v1 → v2**, not a manual `kubectl apply` | Commit/push the image tag change to **GitHub**, let Argo CD automatically sync, then confirm live Deployment image `wil42/playground:v2` and app `Synced` / `Healthy`. |
| ☐ | HTTP output confirms both versions | With `kubectl -n dev port-forward svc/iot-playground 8888:8888` running, `curl http://127.0.0.1:8888/` returns `{"status":"ok", "message":"v1"}` before, and `{"status":"ok", "message":"v2"}` after GitHub sync. |
| ☐ | Complete P3 demonstration | `./p3/scripts/IoT-check.sh` succeeds after syncing; show the GitHub commit and Argo CD deployment history. |

### Bonus — **local** GitLab integrated into the same GitOps workflow (subject p. 16)

| Check | Requirement | Evidence / acceptance criterion |
|---|---|---|
| ☐ | **All P1, P2 and P3 checks passed first** | Otherwise stop: bonus is not eligible for evaluation. |
| ☐ | Current **official GitLab** deployed **locally** | Show `bonus/confs/IoT-gitlab.yaml` official `gitlab/gitlab-ce:latest` image and running instance; verify the deployed GitLab version against the current official release at evaluation time. |
| ☐ | Dedicated `gitlab` namespace and healthy service/storage | `kubectl get ns gitlab && kubectl -n gitlab get pods,svc,pvc` → GitLab Ready, service available, PVC Bound. |
| ☐ | Local GitLab web UI and local Git repository usable | Open local GitLab; show `root/iot-gitops` and its `main` branch with `p3/confs/apps/`. |
| ☐ | **Argo CD reads from local GitLab, not GitHub** | `kubectl -n argocd get application iot-gitlab -o jsonpath='{.spec.source.repoURL}'` → `http://gitlab.gitlab.svc.cluster.local:8081/root/iot-gitops.git`; app `Synced` / `Healthy`. |
| ☐ | **Actual local GitLab GitOps update v1 → v2** | Run `./bonus/scripts/IoT-set-local-version.sh v2`; show **GitLab** commit, Argo auto-sync, live image `wil42/playground:v2`, and port-8888 response containing `"message":"v2"`. Do **not** push to GitHub for this test. |
| ☐ | Rollback v2 → v1 also works | Run `./bonus/scripts/IoT-set-local-version.sh v1`; Argo syncs and `curl` confirms `"message":"v1"`. |
| ☐ | Complete bonus demonstration | `./bonus/scripts/IoT-check.sh` succeeds; explain how the GitLab application replaces the GitHub source without changing the `dev` application's functionality. |
