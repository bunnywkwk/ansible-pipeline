# Build node setup

How the Jenkins build node for role CI is prepared: Jenkins 2.580.2 on a Fedora 44 workstation, builds on the built-in node with label `ansible`, user `jenkins` (uid 962).

## 1. Rootless Podman for `jenkins`

Molecule starts its test containers with Podman as `jenkins`, without root.

```bash
sudo usermod --add-subuids 786432-851967 --add-subgids 786432-851967 jenkins
sudo loginctl enable-linger jenkins
```

| Setting | Why |
| --- | --- |
| subuid/subgid range | A rootless container maps its own users to host IDs: container root becomes `jenkins`, container uids 1–65536 become `786432`–`851967`. Without a range, images with files owned by several users (such as `ubi9-init`) fail to extract. The range is the next free block after the existing users, so no IDs are shared. |
| Linger | `jenkins` never logs in, so systemd would never start its user manager or create `/run/user/962`. Rootless Podman keeps its runtime files there and needs the user manager for the cgroups that systemd-in-container uses. Linger starts both at boot. |

**Verified 2026-11-07**

```text
$ grep jenkins /etc/subuid /etc/subgid; loginctl show-user jenkins -p Linger; ls -ld /run/user/962
/etc/subuid:jenkins:786432:65536
/etc/subgid:jenkins:786432:65536
Linger=yes
drwx------. 4 jenkins jenkins 140 Nov  7 18:18 /run/user/962
```

**Known:** `jenkins` is also in the `docker` group (Docker CE active), used by older jobs. Role CI does not use Docker. Membership in that group is equivalent to root on the workstation.

## 2. Tool virtualenvs and gitleaks

```bash
cd /home/bunny/ansible-pipeline
sudo python3.11 -m venv /opt/ci
sudo /opt/ci/bin/pip install -r ci/requirements-tools.txt
sudo python3.11 -m venv /opt/checkov
sudo /opt/checkov/bin/pip install -r ci/requirements-checkov.txt
cd "$(mktemp -d)"            # empty folder: keeps downloads out of the repo and the checksum check clean
V=8.30.1
curl -sSLO https://github.com/gitleaks/gitleaks/releases/download/v$V/gitleaks_${V}_linux_x64.tar.gz
curl -sSLO https://github.com/gitleaks/gitleaks/releases/download/v$V/gitleaks_${V}_checksums.txt
sha256sum --check --ignore-missing gitleaks_${V}_checksums.txt
tar xzf gitleaks_${V}_linux_x64.tar.gz gitleaks
sudo install -m 0755 gitleaks /usr/local/bin/gitleaks
```

| Choice | Why |
| --- | --- |
| Python 3.11, ansible-core 2.16 | Matches the stack already used in other projects; every tool accepts ansible-core ≥ 2.16.19 |
| Checkov in its own venv | Checkov pins many shared libraries that would clash with ansible-lint and Molecule |
| Root-owned venvs | Builds run as `jenkins` and cannot change their own tools |

**Always activate the venv** (`. /opt/ci/bin/activate`). Called by full path, `/opt/ci/bin/molecule` reported `ansible:2.20.7`: it found Fedora's `/usr/bin/ansible` first on `PATH`. Activated, it reports `ansible:2.16.20`.

**Verified 2026-11-07** (with `/opt/ci` activated)

```text
ansible [core 2.16.20]
ansible-lint 26.11.0 using ansible-core:2.16.20 ansible-compat:26.11.0 ruamel-yaml:0.19.1
yamllint 1.38.0
molecule 26.9.0 using python 3.11
    ansible:2.16.20
gitleaks 8.30.1
```

Checkov: pending (`/opt/checkov` not created yet).
