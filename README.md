# Inception-of-Things — IoT-hlehmann

Implementation of the **42 Inception-of-Things (IoT), subject v4.1** project. It introduces Kubernetes through K3s, Vagrant, K3d and Argo CD, then extends the GitOps setup with a locally hosted GitLab instance.

**Team login:** `hlehmann`
**Public GitHub repository:** https://github.com/jaderiverspirit/IoT-hlehmann

## 1. Architecture

| Part | Infrastructure | Kubernetes | Purpose |
| --- | --- | --- | --- |
| **P1** | Two Debian 13 VMs created by Vagrant/VirtualBox | K3s server and agent | Cluster provisioning, networking and passwordless SSH |
| **P2** | One Debian 13 VM created by Vagrant/VirtualBox | K3s with Traefik | Three web applications, Services and host-based Ingress |
| **P3** | Debian 13 VirtualBox VM (`hlehmann-P3-Bonus`), without Vagrant | K3d cluster `iot` with Argo CD | Continuous deployment from public GitHub |
| **Bonus** | **Same VM and same K3d cluster as P3** | Existing Argo CD plus local GitLab | Continuous deployment from a local GitLab repository |

The project runs its workloads inside Linux virtual machines. Linux Mint is the workstation operating system and VirtualBox host. P3 and Bonus share **one** K3d cluster, one Argo CD installation and the same deployment in the `dev` namespace; the Bonus changes the Git source of truth rather than creating a second cluster.

```text
Linux Mint workstation (VirtualBox + Vagrant)
├── P1: hlehmannS  (192.168.56.110) ── K3s server
│       hlehmannSW (192.168.56.111) ── K3s agent
├── P2: hlehmannS  (192.168.56.110) ── K3s + Traefik + app1/app2/app3
└── P3 + Bonus: hlehmann-P3-Bonus (Debian 13 VM)
    └── Docker → K3d cluster: iot
        ├── namespace argocd ── Argo CD
        ├── namespace dev    ── wil42/playground
        └── namespace gitlab ── GitLab CE (Bonus)
```

P1 and P2 are separate Vagrant environments but deliberately reuse the VirtualBox name `hlehmannS` and private IP `192.168.56.110`. **Destroy the P1 VMs before creating P2.** Merely halting a VM does not release its registered VirtualBox name.

### Repository structure

```text
.
├── p1/
│   ├── Vagrantfile
│   ├── scripts/
│   └── confs/
├── p2/
│   ├── Vagrantfile
│   ├── scripts/
│   └── confs/
├── p3/
│   ├── scripts/
│   └── confs/
│       └── apps/
├── bonus/
│   ├── scripts/
│   └── confs/
└── README.md
```

## 2. Requirements and setup

### Linux Mint workstation (P1/P2)

- VirtualBox and Vagrant, with hardware virtualization enabled.
- Git, SSH, `curl` and `rsync`.
- A self-built **Debian 13 (Trixie)** VirtualBox Vagrant box installed under the name `IoT-Debian13-virtualbox`.
- Ruby for checking Vagrantfile syntax; Python 3 with PyYAML for the optional static checks.

Check the local box:

```bash
vagrant box list
# Expected entry: IoT-Debian13-virtualbox (virtualbox, ...)
```

Both Vagrantfiles use the locally installed `IoT-Debian13-virtualbox` box. The box archive is not included in the repository. On another computer, import or rebuild the box before starting Vagrant.

To import an existing archive, if necessary:

```bash
vagrant box add --name IoT-Debian13-virtualbox /path/to/IoT-Debian13-virtualbox.box
```

The box is built from Debian's official installation media, not from a third-party public box registry. The source files and instructions for the project are in Git; the Vagrant base-image archive is supplied separately.

### Combined P3 + Bonus VM

| Setting | Configuration |
| --- | --- |
| VirtualBox name | `hlehmann-P3-Bonus` |
| Guest operating system | Debian 13 |
| CPUs | 4 vCPU |
| Memory | 10 GiB |
| Virtual disk | 60 GiB |
| Container runtime | Docker Engine |
| Kubernetes | K3d (`iot`) |
| Namespaces | `argocd`, `dev`, `gitlab` (Bonus) |

Use a regular Debian user with `sudo` privileges. Clone the repository **inside this VM**, and run the P3/Bonus scripts there. Docker needs sufficient disk capacity for images, GitLab's persistent data and logs.

```bash
git clone https://github.com/jaderiverspirit/IoT-hlehmann.git
cd IoT-hlehmann
```

## 3. Part 1 — K3s server and worker with Vagrant

P1 provisions two Debian 13 virtual machines. VirtualBox VM names and guest hostnames follow the 42 login convention, while Kubernetes node names are lowercase to meet Kubernetes naming rules.

| Role | VM / guest hostname | K3s node name | Private IP | CPUs | RAM |
| --- | --- | --- | --- | ---: | ---: |
| Server | `hlehmannS` | `hlehmanns` | `192.168.56.110` | 2 | 2048 MiB |
| Worker | `hlehmannSW` | `hlehmannsw` | `192.168.56.111` | 1 | 1024 MiB |

From the project root on the Linux workstation:

```bash
cd p1
vagrant validate
vagrant up --provider=virtualbox
vagrant status

# Server: both Kubernetes nodes should be Ready.
vagrant ssh hlehmannS -c 'sudo /usr/local/bin/k3s kubectl get nodes -o wide'

# Verify hostnames, networking, and the worker service.
vagrant ssh hlehmannS -c 'hostname; ip -brief address'
vagrant ssh hlehmannSW -c 'hostname; ip -brief address; sudo systemctl is-active k3s-agent'

# Automated checks, including passwordless Vagrant SSH.
./scripts/IoT-check.sh
```

The first machine runs the K3s controller; the second joins as an agent. The Vagrantfile generates `p1/.iot-join-token` locally with restricted permissions and synchronizes it to the guests for cluster joining. This token is ignored by Git and must never be committed.

An optional small-resource profile is available through `IOT_P1_TINY=1`, although the default server allocation is more suitable for current K3s releases.

**Move to P2:** from inside `p1/`, remove the disposable P1 machines to free the shared VirtualBox VM name:

```bash
vagrant destroy -f
cd ..
```

This does not delete the installed Vagrant base box.

## 4. Part 2 — K3s, three applications and Traefik Ingress

P2 provisions one Debian 13 VM called `hlehmannS` (`192.168.56.110`) with K3s, Traefik and three nginx-based applications.

| HTTP request hostname | Target | Desired replicas |
| --- | --- | ---: |
| `app1.com` | `iot-app1` | 1 |
| `app2.com` | `iot-app2` | 3 |
| Any other hostname | `iot-app3` | 1 |

The Ingress configuration uses hostname rules for app1/app2 and a catch-all route for app3. Send HTTP `Host` headers explicitly; no public DNS changes are required.

```bash
cd p2
vagrant validate
vagrant up --provider=virtualbox
vagrant status

vagrant ssh hlehmannS -c 'sudo /usr/local/bin/k3s kubectl get deployments,pods,services,ingress -o wide'
./scripts/IoT-check.sh

# Run on the Linux Mint workstation:
curl --noproxy '*' -H 'Host: app1.com' http://192.168.56.110/
curl --noproxy '*' -H 'Host: app2.com' http://192.168.56.110/
curl --noproxy '*' -H 'Host: unknown.example' http://192.168.56.110/
```

Expected page messages: `Hello from app1.`, `Hello from app2.`, and `Hello from app3.`, respectively. Check that the deployment replica counts are `1`, `3`, and `1`.

To inspect routing from within the guest:

```bash
vagrant ssh hlehmannS -c 'sudo /usr/local/bin/k3s kubectl describe ingress iot-routing'
```

When finished, stop the P2 VM to free workstation resources:

```bash
vagrant halt
cd ..
```

## 5. Part 3 — K3d, Argo CD and public GitHub GitOps

P3 runs **inside the dedicated Debian 13 VM**, without Vagrant. The scripts create a K3d cluster named `iot`, deploy Argo CD in `argocd`, and manage `wil42/playground` in `dev` from the public GitHub repository.

### Install the tooling and cluster

From the repository root **inside `hlehmann-P3-Bonus`**:

```bash
./p3/scripts/IoT-install-tools.sh

# Activate Docker group membership by logging out/in, or start a new group shell:
newgrp docker

docker info
./p3/scripts/IoT-create-cluster.sh
./p3/scripts/IoT-install-argocd.sh
```

The tools installer sets up Docker, K3d and kubectl. The cluster creation script selects context `k3d-iot`, creates the `dev` namespace and reuses an existing `iot` cluster rather than creating a duplicate.

### Connect Argo CD to GitHub

```bash
./p3/scripts/IoT-configure-github.sh \
  https://github.com/jaderiverspirit/IoT-hlehmann.git

kubectl config current-context
kubectl get namespaces argocd dev
kubectl -n argocd get application iot-github
./p3/scripts/IoT-check.sh
```

Argo CD watches branch `main`, path `p3/confs/apps`, with automated synchronization, pruning and self-healing.

### Demonstrate GitHub continuous deployment

The application has two official image tags: `wil42/playground:v1` and `wil42/playground:v2`. Start with `v1` in `p3/confs/apps/IoT-deployment.yaml` on GitHub.

In one terminal **inside the VM**, expose the application:

```bash
kubectl -n dev port-forward svc/iot-playground 8888:8888
```

In another terminal:

```bash
curl http://127.0.0.1:8888/
# Expected for v1: {"status":"ok", "message":"v1"}
```

In a Git checkout with GitHub push access (for example, on the Linux Mint workstation), make and push the version change:

```bash
./p3/scripts/IoT-set-version.sh v2
git add p3/confs/apps/IoT-deployment.yaml
git commit -m 'Update playground to v2 via GitHub GitOps'
git push origin main
```

Back inside the VM, watch Argo CD reconcile the pushed GitHub change:

```bash
kubectl -n argocd get application iot-github -w
# Stop watching with Ctrl+C once synchronized.
kubectl -n dev rollout status deployment/iot-playground --timeout=300s
kubectl -n dev get deployment iot-playground \
  -o jsonpath='{.spec.template.spec.containers[0].image}'; echo
curl http://127.0.0.1:8888/
# Expected for v2: {"status":"ok", "message":"v2"}
```

To open the Argo CD interface from within the Debian VM:

```bash
kubectl -n argocd port-forward svc/argocd-server 8082:443
# Browser: https://127.0.0.1:8082 (local self-signed certificate)
```

The login is `admin`; obtain the generated initial password locally without adding it to the repository:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d; echo
```

## 6. Bonus — local GitLab in the same P3 cluster

The Bonus extends **the existing P3 K3d cluster `iot`**. It deploys GitLab CE into the dedicated `gitlab` namespace and switches the existing Argo CD workflow from a public GitHub source to a **local GitLab repository**.

There is **no second Kubernetes cluster and no second Argo CD installation**. The same application remains in `dev`.

```text
P3:    GitHub (public) ───► Argo CD (argocd) ───► playground (dev)
Bonus: GitLab (local) ───► Argo CD (argocd) ───► playground (dev)
                             same cluster: k3d-iot
```

The GitLab container uses the official GitLab CE image with a specific version tag defined in `bonus/confs/IoT-gitlab.yaml`. It has persistent storage (PVC request: 25 GiB). Upgrades of an initialized GitLab instance must follow GitLab's supported version-specific upgrade path; changing the image tag alone is not a substitute for a supported migration.

### Install GitLab and configure access

From the project root **inside the same Debian VM as P3**:

```bash
kubectl config current-context  # Expected: k3d-iot
./bonus/scripts/IoT-install-gitlab.sh
./bonus/scripts/IoT-start-gitlab-access.sh
```

The GitLab service URL is:

```text
http://gitlab.gitlab.svc.cluster.local:8081
```

Inside the cluster, this name resolves via Kubernetes DNS. From the Debian VM, the access script uses a local hosts entry and a loopback `kubectl port-forward` to reach the same URL. GitLab's initial credentials and bootstrap token are stored privately under `~/.config/iot/`, **not** in Git.

### Switch Argo CD to local GitLab

```bash
./bonus/scripts/IoT-bootstrap-local-repo.sh
./bonus/scripts/IoT-check.sh
```

Bootstrap creates a public-to-the-lab GitLab project at `root/iot-gitops`, seeds it with a `v1` copy of the P3 Kubernetes manifests, and creates a separate local working tree at `~/IoT-GitLab-worktree`. It removes the `iot-github` Argo CD Application and registers `iot-gitlab` instead, preventing two Applications from managing the same Kubernetes Deployment concurrently. It does **not** alter the original GitHub remote.

Verify the source:

```bash
kubectl -n argocd get application iot-gitlab \
  -o jsonpath='{.spec.source.repoURL}'; echo
# Expected:
# http://gitlab.gitlab.svc.cluster.local:8081/root/iot-gitops.git
```

### Demonstrate local GitLab continuous deployment

Keep the playground port-forward running in one terminal:

```bash
kubectl -n dev port-forward svc/iot-playground 8888:8888
```

In another terminal, push version changes **to local GitLab** using the project script:

```bash
./bonus/scripts/IoT-set-local-version.sh v2
curl http://127.0.0.1:8888/  # "message":"v2"

./bonus/scripts/IoT-set-local-version.sh v1
curl http://127.0.0.1:8888/  # "message":"v1"

./bonus/scripts/IoT-check.sh
```

The update must propagate **local GitLab → existing Argo CD → existing Kubernetes Deployment**. No GitHub commit or push is required for the Bonus demonstration.

## 7. Verification reference

| Part | Command | What to confirm |
| --- | --- | --- |
| P1 | `cd p1 && ./scripts/IoT-check.sh` | Two guests; server and worker; two Ready nodes; SSH and IPs |
| P2 | `cd p2 && ./scripts/IoT-check.sh` | Three deployments; replicas 1/3/1; Ingress returns the correct pages |
| P3 | `./p3/scripts/IoT-check.sh` | `k3d-iot`, Argo CD and `dev` resources; GitHub source and current image |
| Bonus | `./bonus/scripts/IoT-check.sh` | Local GitLab namespace, PVC and Argo CD GitLab source |
| Source checks | `python3 bonus/scripts/IoT-static-checks.py` | Kubernetes YAML structure, Vagrantfile and shell syntax |

For the static checker, install PyYAML if needed (for example, through your distribution's `python3-yaml` package). Static validation does not replace live VM and Kubernetes checks.

## 8. Troubleshooting

**Vagrant cannot find the Debian box.** Check `vagrant box list`. Import the self-built archive using the exact box name `IoT-Debian13-virtualbox`. A fresh Git clone alone does not contain the box archive.

**P2 VM name already exists.** P1 and P2 both use the VirtualBox name `hlehmannS`. Run `vagrant destroy -f` in `p1/` after finishing P1; merely running `vagrant halt` does not remove the registered name.

**P1 worker does not join.** Check the server at `192.168.56.110`, worker at `192.168.56.111`, the locally generated `/vagrant/.iot-join-token`, K3s services and TCP port 6443 between guests.

**Kubernetes node names differ from guest hostnames.** This is intentional: Vagrant guest names include the subject-required capitals (`hlehmannS`, `hlehmannSW`); Kubernetes node names are lowercase (`hlehmanns`, `hlehmannsw`).

**P2 HTTP requests fail.** Check `kubectl get ingress,svc,pods`, Traefik and ServiceLB in `kube-system`, the guest's port 80 and the VirtualBox private network. Use `curl --noproxy '*'` to bypass host proxy settings.

**Docker reports permission denied.** Re-enter the Docker group with `newgrp docker` or log out and in again. Membership in the Docker group gives root-equivalent access to the VM.

**Argo CD stays OutOfSync or cannot fetch Git.** Check `kubectl -n argocd describe application iot-github` (or `iot-gitlab`), repository URL, `main` branch, `p3/confs/apps` path and repo-server logs. Use `kubectl config current-context` to confirm `k3d-iot`.

**GitLab pod is Pending or not Ready.** Check VM memory/disk, PVC state, pod events and logs:

```bash
kubectl -n gitlab get pods,pvc,svc
kubectl -n gitlab describe deployment iot-gitlab
kubectl -n gitlab logs deployment/iot-gitlab --tail=150
```

**Local GitLab cannot be reached from the VM.** Rerun `./bonus/scripts/IoT-start-gitlab-access.sh`; inspect `~/.config/iot/gitlab-portforward.log` and the local `/etc/hosts` mapping. The port-forward must remain active.

**A version change does not affect the application.** Confirm whether `iot-github` (P3) or `iot-gitlab` (Bonus) is the active Argo CD Application, then inspect its Git source, synchronization state, Deployment image and Pod rollout.

## 9. Security and useful references

Do not commit K3s join tokens, GitLab root passwords, GitLab personal access tokens, `.env` files or generated Kubernetes credentials. Local Vagrant box archives are stored outside the repository; runtime state is excluded from Git. GitLab is configured for a private teaching lab, not exposed as a production service.

- [Project repository](https://github.com/jaderiverspirit/IoT-hlehmann)
- [Debian](https://www.debian.org/distrib/)
- [Vagrant machine configuration](https://developer.hashicorp.com/vagrant/docs/vagrantfile/machine_settings)
- [K3s documentation](https://docs.k3s.io/)
- [K3d documentation](https://k3d.io/stable/)
- [Argo CD documentation](https://argo-cd.readthedocs.io/en/stable/)
- [GitLab Docker installation](https://docs.gitlab.com/install/docker/installation/)
- [GitLab upgrade paths](https://docs.gitlab.com/update/upgrade_paths/)
