# Ansible Role Pipeline — Plan

Nov 7, 2026 · @Aeron

## Summary

A lab of a full Ansible role delivery pipeline on Jenkins, built **CI first**. CD continues from CI's output: a tested version tag.

- **CI (Batches 0–5):** one central pipeline in repo `ansible-pipeline` tests any role repo. Role repos hold only role code, with no Jenkinsfile. Jenkins watches each role repo, checks out its code, loads the Jenkinsfile from `ansible-pipeline` (Remote Jenkinsfile Provider plugin) and runs gitleaks, yamllint, ansible-lint, Checkov and Molecule. A green `main` gets a release tag. Every gate is proven by pushing a bad commit on purpose.
- **CD (Batches 6–11):** Terraform creates RHEL 9 lab VMs from the golden image on the local KVM. A deployment repo pins role tags and holds variables per environment. A separate Jenkins job deploys to staging, smoke-tests it, waits for approval and rolls out to production. Every run writes a deploy record. A small read-only dashboard shows those records in plain language.

**Changed 2026-11-07** from the first version of this plan:

- **CI moved first.** Lab VMs moved from Batch 0 to Batch 6, because only CD needs them.
- **Central pipeline replaces the shared library.** A role repo has nothing to edit, so the gates cannot be weakened from a role branch.
- **GitHub and the Jenkins on this workstation replace Proxmox.**
- **Gate method taken from the earlier `chrome_cis` CI work** (Obsidian vault `ci-pipeline/ansible-ci-plan.md`): break it on purpose, and record what happens. The vault notes stay as they are; this plan continues the work.

## Lab setup and decisions

| Topic | Lab choice | What it means |
| --- | --- | --- |
| Git hosting | GitHub, public repos | Branch and tag rulesets are free on public repos; no secrets are committed |
| Jenkins | Jenkins 2.580.2 already on this workstation (RPM, user `jenkins`) | Controller and builds on one machine |
| Build node | Built-in node, label `ansible` | shortcut: builds can read the controller's files; move to a separate agent before real use |
| CI pipeline | Central `Jenkinsfile` in `ansible-pipeline`; Remote Jenkinsfile Provider plugin | Role repos contain no pipeline code; a marker file (`meta/main.yml`) marks a branch as buildable |
| CI jobs | Jenkins folder `role-ci/` | One multibranch job per role, or an organization folder for `ansible-role-*` (Batch 5) |
| Triggers | GitHub webhook relayed by smee.io to `http://localhost:8080/github-webhook/`; daily repository scan as a backup | GitHub cannot reach `localhost:8080` directly; the smee client on the workstation forwards each event (changed 2026-11-07 from 5-minute scans, at your request) |
| Tools | `/opt/ci` (Python 3.11, ansible-core 2.16) from `ci/requirements-tools.txt`, `/opt/checkov` (Python 3.11) from `ci/requirements-checkov.txt`, gitleaks 8.30.1 binary (checksum verified) | Pinned versions in the repo; Checkov is kept apart because of its dependency pins |
| Security scanner | Checkov (`--framework ansible`) | Flags insecure task settings, such as `validate_certs: false` |
| Secrets | Not handled in the lab | Only Jenkins' credentials store holds the GitHub token (`github-crendentials`) and, from Batch 6, the VM SSH key |
| Test containers | `ubi9-init`, rootless Podman as `jenkins` | Closest container match to RHEL 9 for Molecule |
| RHEL versions | 9 only | One Molecule scenario: `default` |
| Example role | `ansible-role-webserver`: nginx, custom index page, firewall port; also the template for new roles | Gives a clear smoke test later: HTTP 200 with the expected text |
| Release tags | `VERSION` file in the role repo; Jenkins tags `v<VERSION>` on a green `main` | To release, bump `VERSION` in the pull request |
| Lab VMs (CD) | Terraform with the libvirt provider on this workstation's KVM | User `jenkins` is already in the `libvirt` group |
| Approval (CD) | Jenkins `input` step; the approver is you | Production waits until you click Proceed |

**Open:** your GitHub username (needed in Batch 0), and the golden image's qcow2 path on the local KVM (needed in Batch 6).

**Lab machines**

| Name | Purpose | Built from |
| --- | --- | --- |
| This workstation | Jenkins controller; builds run on the built-in node | Fedora, already installed |
| `lab-stg-01` | Short-lived staging target (CD): created at the start of each deploy, destroyed after its smoke test | Golden image on local KVM |
| `lab-prd-01` | Production target (CD); stays up (`VM_COUNT=2` adds `lab-prd-02`) | Golden image on local KVM |

## Pipeline flow

```text
ROLE CI · Jenkins role-ci/ · central Jenkinsfile from ansible-pipeline
  Push or PR to ansible-role-<name> ──► Secrets ──► Lint ──► Security ──► Molecule ──► Release tag
  (role code only, no Jenkinsfile)      gitleaks    yamllint  Checkov     ubi9-init    v<VERSION>, green main only
                                                    ansible-lint                            │ tag
                                                                                             ▼
DEPLOYMENT REPO · platform engineer
  Deployable release ◄── Review and merge ◄── Pre-deploy checks ◄── Version bump PR
  (config at a git tag)                       (pins, vars, dry run)  (manual pin edit in lab)
        │ ready
        ▼
CD · Jenkins cd/ · results on the dashboard
  Deploy request ──► Staging ──────────► Approval ──────► Production
  (Jenkins cd/        (deploy + smoke     (named           (rolling + verify)
   job form)           tests)              approver)
```

Role code is tested once, in CI. CD only deploys tested tags and never re-runs role tests.

## Progress tracker

Update the Status column as each batch finishes. A batch is Done only when every one of its "Done when" checks passed. Never start a batch before the one above it is Done.

| Batch | Phase | Goal | You have at the end | Status |
| --- | --- | --- | --- | --- |
| 0 — CI foundation | CI | Jenkins builds on label `ansible` with pinned tools; a role repo with no Jenkinsfile builds from the central one | Working build node, GitHub connection, proven remote Jenkinsfile | Done (2026-11-07) |
| 1 — Template role | CI | `webserver` role passes Molecule by hand | `ansible-role-webserver` with Molecule | Done (2026-11-07) |
| 2 — Central pipeline | CI | Every push and PR to the role runs the gates | Central `Jenkinsfile`, `role-ci/ansible-role-webserver` | Done (2026-11-07) |
| 3 — Gate drills | CI | Every gate catches a real bad commit | Drill table with real output in `docs/ci/evidence.md` | Done (2026-11-07) |
| 4 — Release and merge gate | CI | Green `main` produces a tag; red code cannot merge | Tag `v0.1.0`, GitHub rulesets | In progress |
| 5 — Any role, zero setup | CI | A second role gets CI without pipeline edits; CI docs done | Second role green, CI README and guides | Not started |
| 6 — Lab VMs | CD | Terraform creates VMs on demand from the golden image | `infra-lab` repo, `infra/lab-vm` job | Not started |
| 7 — Deployment repo | CD | Config that says what goes where, checked on change | `deploy-webserver` repo | Not started |
| 8 — CD job | CD | Staging → approval → production in one Jenkins job | `cd/deploy-webserver` job + deploy records | Not started |
| 9 — Rollback drill | CD | Prove you can go back a release | Release 2 deployed, then rolled back | Not started |
| 10 — Dashboard | CD | Non-technical view of deploys and results | `cd-dashboard` web page | Not started |
| 11 — Wrap-up | Both | Guides, lessons, next steps | READMEs + next-phase list | Not started |

## How to work with Claude Code

Point Claude Code at this file with the prompt below. Start a new prompt at each batch, changing the last line.

**Rules for Claude Code**

- One batch at a time, in order; never build ahead.
- Propose the steps and the file list before writing anything, and wait for an OK.
- Ask for missing facts (usernames, URLs, paths) instead of guessing.
- No secrets in any repo. Only the Jenkins credentials store holds tokens and keys.
- Role repos never contain pipeline code; pipeline changes go to `ansible-pipeline`.
- CI and CD stay in separate repos and separate Jenkins folders; CD never re-runs role tests.
- The user runs workstation admin commands, Jenkins UI steps and lab tests; Claude Code gives exact commands and reviews the output.
- End every batch by running its "Done when" checks and showing the output. Terraform changes always go plan → approval → apply through Jenkins.

**Prompt to paste**

```text
You are helping me build a lab of the Ansible role delivery pipeline in docs/PLAN.md:
CI first (central Jenkinsfile, role repos without pipeline code), then CD. Jenkins on this workstation, GitHub,
one example role "webserver", RHEL 9 golden-image VMs on local KVM for CD, Checkov, no secrets yet.
We work batch by batch, Batch 0 to Batch 11, never skipping ahead.
For the current batch:
1. Restate its goal and list anything you need from me.
2. Give me the step-by-step plan and the files you will create or change.
3. Wait for my OK, then build it one step at a time.
4. Walk me through every "Done when" check and show the results.
5. Update the batch's Status in the tracker in docs/PLAN.md, then name the next batch.
Current batch: Batch 0.
```

## Batch 0 — CI foundation

**Goal:** Jenkins on this workstation builds on label `ansible` with pinned tools, the `jenkins` user runs systemd containers with rootless Podman, and a role repo **without a Jenkinsfile** is built automatically from the central `Jenkinsfile`.

**Steps**

- [x] Create public GitHub repos `ansible-pipeline` (this folder) and `ansible-role-webserver` (local folder `/home/bunny/ansible-role-webserver`, next to this one, not inside it). The role repo starts with only `README.md` and `meta/main.yml`, enough to test the marker file.
- [x] Write `ci/requirements-tools.txt` with pinned `ansible-core`, `ansible-lint`, `yamllint`, `molecule`, `molecule-plugins[podman]` and `checkov`, for a Python version all of them support.
- [x] Workstation admin: subuid/subgid ranges and `loginctl enable-linger` for `jenkins`; the `/opt/ci` and `/opt/checkov` virtualenvs; the gitleaks binary, pinned and checksum verified.
- [x] Jenkins plugins: Pipeline, Git, GitHub Branch Source, Remote Jenkinsfile Provider, Credentials Binding, Timestamper, Pipeline Stage View, JUnit.
- [x] Built-in node: label `ansible`.
- [x] Reuse credential `github-crendentials` (Username with password, fine-grained token `jenkins-laptop`, expires 2027-01-10): add each role repo to the token's repository access (`ansible-pipeline` is not needed: any token can read a public repo, and statuses go only to role repos). Permissions already set: Contents, Metadata and Pull requests read; Commit statuses read/write.
- [x] Folder `role-ci/`.
- [x] Spike `Jenkinsfile` in `ansible-pipeline`: one stage that prints the repo, branch and commit it was given, the tool versions, and boots a `ubi9-init` container with systemd.
- [x] Multibranch job `role-ci/ansible-role-webserver`: GitHub source with `github-crendentials`, build mode "by Remote Jenkins File Plugin", marker file `meta/main.yml`, Jenkinsfile from `ansible-pipeline` branch `main`, build triggered by the webhook, with a daily scan as a backup.
- [x] smee: a channel at smee.io, the smee client forwarding it to Jenkins as a user service, and a webhook on each role repo pointing at the channel.

**Done when** (all checks run inside a Jenkins build, so they prove the real build context)

- A push to `ansible-role-webserver`, which has no Jenkinsfile, starts a build by itself within seconds, through the webhook, and its console shows the central `Jenkinsfile` running on the role's code.
- That build prints the versions of `ansible-core`, `ansible-lint`, `yamllint`, `molecule`, `checkov`, `gitleaks` and `podman`, matching `ci/requirements-tools.txt`.
- In that build, a `ubi9-init` container reports `systemctl is-system-running` as `running` or `degraded`, as user `jenkins`.
- A branch without `meta/main.yml` is not built.
- The role commit shows a Jenkins status on GitHub.

**Watch out:** rootless Podman for a system service user needs subuid/subgid entries (none exist for `jenkins` on 2026-11-07) and a runtime directory (`XDG_RUNTIME_DIR=/run/user/<uid>`, created by linger). Prove systemd containers here, not in Batch 2. If the plugin cannot do the marker file or remote Jenkinsfile on this Jenkins version, fall back to a two-line Jenkinsfile in each role that loads the pipeline from `ansible-pipeline`, and record why.

## Batch 1 — Template role `webserver`

**Goal:** a small, real role that passes Molecule by hand, before Jenkins is involved. It is also the template that new roles are copied from.

**What the role does:** installs nginx, writes an index page showing `webserver_message`, opens `webserver_port` in firewalld, and enables and starts nginx.

**Steps**

- [x] Scaffold `ansible-role-webserver` (`ansible-galaxy role init`), keeping only the folders the role uses.
- [x] `defaults/main.yml`: `webserver_port: 80`, `webserver_message: "Hello from the lab"`, `webserver_manage_firewall: true`.
- [x] Tasks: install nginx, own server block `/etc/nginx/conf.d/webserver.conf` listening on `webserver_port`, page `/usr/share/nginx/html/webserver.html`, firewalld port (only when `webserver_manage_firewall`), service enabled and started, handler to reload nginx. **Changed 2026-11-07:** the package owns `index.html` (a symlink to its test page), so the role writes its own page and server block instead; this also makes nginx listen on `webserver_port`, not only the firewall.
- [x] `meta/argument_specs.yml`: `webserver_port` int, `webserver_message` str, `webserver_manage_firewall` bool.
- [x] Molecule `default` scenario: 1 × `ubi9-init` with systemd; `webserver_manage_firewall: false` there, since containers have no firewalld.
- [x] Verify play: nginx running, port listening, page contains the message.
- [x] `VERSION` file containing `0.1.0`.

```yaml
# molecule/default/molecule.yml (shape)
driver:
  name: podman
platforms:
  - name: webserver-ubi9
    image: registry.access.redhat.com/ubi9/ubi-init
    command: /usr/sbin/init
    systemd: always
provisioner:
  name: ansible
  inventory:
    group_vars:
      all:
        webserver_manage_firewall: false
verifier:
  name: ansible
```

**Done when**

- `molecule test` passes on the workstation with the `/opt/ci` tools, including the idempotence step (second run: 0 changed).
- `yamllint .`, `ansible-lint --profile production` and `checkov -d . --framework ansible` are clean on the role.

**Moved (2026-11-07):** "run the role against the hardened `lab-stg-01`" moved to Batch 7, the first batch with a VM.

**Watch out:** on the hardened image, a non-standard port needs an SELinux port label (`community.general.seport`). Keep port 80 for the lab.

## Batch 2 — Central pipeline, happy path

**Goal:** every push and pull request to a role repo runs the same gates, defined once in `ansible-pipeline/Jenkinsfile`.

**Stages, cheapest first**

| # | Stage | Command | Fails on |
| --- | --- | --- | --- |
| 1 | Secrets | `gitleaks git -v --redact --log-opts=HEAD` | Any finding |
| 2 | YAML lint | `yamllint -f parsable .` | Errors |
| 3 | Ansible lint | `ansible-lint --profile production` | Any violation |
| 4 | Security | `checkov -d . --framework ansible --skip-download` | Failed checks |
| 5 | Molecule | `molecule test --all` | Converge, idempotence or verify fails |
| 6 | Release | Batch 4; `main` only | — |

`--log-opts=HEAD` scans only the branch being built; by default gitleaks scans every ref in the checkout (found in the `chrome_cis` spike).

**Steps**

- [x] Replace the spike `Jenkinsfile` with the stages above: `agent { label 'ansible' }`, `/opt/ci` activated, timeout, `disableConcurrentBuilds()`, unique Molecule names per build (`MOLECULE_RUN_ID`), `post { always }` cleanup.
- [x] ~~Default `.yamllint`, `.ansible-lint` and `.gitleaks.toml` in `ansible-pipeline/ci/`~~ **Changed 2026-11-07:** no central configs. Each tool already picks up a role's own config file from its root, and without one its built-in defaults apply, the same for every role. Central copies would need a second checkout in every build. Add one only when the Batch 3 drills show a shared rule is needed.
- [x] Archive the gitleaks and ansible-lint SARIF reports and the Molecule output as build artifacts.

**Done when**

- A push to a branch runs all stages and is green.
- A pull request runs all stages and is green, and GitHub shows the status on the PR.
- The reports are archived on the build.

## Batch 3 — Gate drills: break it on purpose

**Goal:** every gate has caught a real bad commit. A gate that stays green when it should go red is a gap; fix it with the smallest change and re-push the same bad commit.

**Each round:** predict the stage that fails → push the bad commit on branch `drill/NN-name` → read the real result → fix any gap → re-push the same commit → record it in the drill table in `docs/ci/evidence.md`.

One drill per gate or behaviour, no repeats (changed 2026-11-07: trimmed from 19 to 8 at your request).

| # | Break | Proves | Predicted | Status |
| --- | --- | --- | --- | --- |
| 1 | Wrong YAML indentation | YAML lint | YAML lint red | Done: as predicted |
| 2 | Typo in a module name | Ansible lint syntax-check | Ansible lint red | Done: gap found (Molecule caught it, not lint); fixed with a static `import_role` in `converge.yml` |
| 3 | `shell: yum install -y nginx` | Ansible lint rules | Ansible lint red | Done: as predicted (3 rules) |
| 4 | Fake private key, then deleted in a second commit | Secrets scans history, not only the last commit | Secrets red on both pushes, value redacted. Fix: drop the commit, force-push | Done: as predicted; GitHub push protection did not block the key |
| 5 | `get_url` with `validate_certs: false` | Security (Checkov) | Security red | Done: as predicted (`CKV_ANSIBLE_2`) |
| 6 | Change the page text without updating verify | Molecule verify | Molecule verify red | Done: as predicted |
| 7 | Task with `changed_when: true` | Molecule idempotence | Molecule idempotence red | Done: as predicted |
| 8 | Role branch adds its own `Jenkinsfile` that skips every stage | Role repos cannot change the pipeline | Ignored: the central pipeline still runs | Done: as predicted |

**Dropped, with reason:**

- Undefined variable: Molecule converge red is already shown by drill 2 before its fix.
- `file` without `mode`, `dnf` with `disable_gpg_check`, fake token in `README.md`: same gate and same tool as drills 3, 5 and 4.
- Branch without `meta/main.yml`: proven in Batch 0.
- `yum_repository` with `gpgcheck: false`: Checkov missed it in the earlier laptop spike (not re-run here); recorded as a known limit, not a drill.
- Abort during Molecule: skipped at your request; Molecule's own cleanup after a failure is shown in drills 6 and 7, and `post { always }` runs `molecule destroy --all` in every build.
- Known limit, found 2026-11-07 (local ansible-lint run): `command-instead-of-module` lists `yum` but not `dnf` or `apt`, so `command: dnf install -y nginx` with `changed_when: false` passes lint. PR review catches it for now; revisit a custom rule in Batch 5.
- `.gitleaksignore` false positive, docs-only builds, missing tool or unreachable image: setup procedures or optimisations, not something a gate catches.

**Done when:** drills 1–8 have real results in `docs/ci/evidence.md`, every gap has a fix proven by re-pushing the same commit. Drill branches stay on GitHub as evidence (changed 2026-11-07: kept, not deleted, at your request).

## Batch 4 — Release tags and merge gate

**Goal:** a green `main` produces a version tag that is never moved, red code cannot reach `main`, and the tag is the only thing CD may deploy.

**How it works:** on `main`, the gates run again, then the Release stage. Running the gates on `main` too avoids a lesson from `chrome_cis`, where the job's first scan tagged untested code on `main`. Release reads `VERSION`, fails unless it is `X.Y.Z`, and creates and pushes `v<VERSION>` if that tag does not exist. If the tag exists, it skips with a message and the build stays green.

**Steps**

- [x] Add the Release stage to the central `Jenkinsfile` with `when { branch 'main' }`.
- [x] `Version` stage on every build, right after Secrets (added 2026-11-07: with the check only in Release, a PR with a bad `VERSION` built green, could merge, and then turned `main` red).
- [ ] Jenkins pushes tags over HTTPS with `github-crendentials`; give the token Contents read/write on the role repos.
- [ ] GitHub branch ruleset on `main`: pull request required, check `continuous-integration/jenkins/pr-head` required with "branches up to date before merging", no force push, no deletion, no bypass. **Decided 2026-11-07:** `pr-head` + up to date, not `pr-merge`: no job change, and an up-to-date PR head is exactly what gets merged. Not `branch`: branches with an open PR are not built as branches (Batch 3 drill 2 note).
- [ ] `ansible-pipeline` `main`: block force push and deletion (added 2026-11-07: Batch 3 drill 8 showed whoever pushes there controls CI). Direct pushes stay allowed.
- [ ] GitHub tag ruleset on `v*`: block update and deletion. Creation stays allowed: the token acts as you, so GitHub cannot tell a Jenkins tag from a hand-made one (changed 2026-11-07: HTTPS token instead of a deploy key, at your request).
- [ ] Merge the Batch 1 role to `main` with `VERSION` = `0.1.0`.

**Done when**

- The `main` build is green and tag `v0.1.0` appears on GitHub.
- Re-running the same `main` build skips the release without failing; the tag is not moved.
- A pull request with `VERSION` set to `v1` goes red at the Version stage and cannot be merged.
- A `main` build that fails any gate creates no tag.
- A red pull request cannot be merged, even by you; a direct push to `main` is refused.
- Moving or deleting `v0.1.0` is refused.
- A small playbook installs the role from `v0.1.0` through `requirements.yml`: the release is usable.

## Batch 5 — Any role, zero pipeline setup

**Goal:** a new role gets the full CI without touching the pipeline, and the CI is documented well enough to use without help.

**Steps**

- [ ] Mark `ansible-role-webserver` as a GitHub template repository.
- [ ] Replace the per-role job with a GitHub organization folder in `role-ci/` that discovers repos named `ansible-role-*` with the same remote-Jenkinsfile settings. If the plugin does not support organization folders, keep one multibranch job per role and document the one-minute setup.
- [ ] Create a second role from the template (a small one, such as `ansible-role-motd`); change only role code.
- [ ] Docs in `ansible-pipeline`: `README.md` (what it is, how it works), `docs/ci/gates.md` (each gate: what it catches, how to fix a failure), `docs/ci/onboarding-a-role.md`, `docs/ci/troubleshooting.md`. Role README in the template.

**Done when**

- The second role's repo is built and green without any change in Jenkins or `ansible-pipeline` (or with only the documented job setup).
- A change to the central `Jenkinsfile` reaches both roles on their next build.
- Following only `docs/ci/onboarding-a-role.md`, a new role reaches a green build.

**CI is done here.** Its output for CD: role tags `v<VERSION>` that passed every gate.

## Batch 6 — Lab VMs with Terraform (CD starts here)

**Goal:** Terraform, run only through Jenkins, creates lab VMs from the golden image on the local KVM on demand: one production VM, and a staging VM only during a deploy.

| Environment | VMs | Lifetime |
| --- | --- | --- |
| staging | 1 (`lab-stg-01`) | Created by the CD job at the start of a deploy, destroyed after its smoke test |
| production | 1 by default (`lab-prd-01`); `VM_COUNT=2` adds `lab-prd-02` | Stays up between deploys |

**Steps**

- [ ] Add pinned `terraform` and `tflint` to the workstation; add Jenkins folder `infra/` and credential `lab-ssh-key` (SSH private key for the `ansible` user on the VMs).
- [ ] Create repo `infra-lab`. Write module `modules/rhel9_vm` (libvirt provider): a volume cloned from the golden image qcow2, CPU, memory, network and hostname; the `ansible` user and public key at first boot with cloud-init.
- [ ] In `envs/lab/`, take two inputs, `environment` and `vm_count` (default 1), and name VMs `lab-stg-NN` or `lab-prd-NN`.
- [ ] One Terraform workspace per environment, so destroying staging never touches production.
- [ ] Write the inventory to `/var/lib/lab-inventory/<environment>/hosts.ini`; Ansible jobs read hosts from there.
- [ ] State in a local directory owned by `jenkins`.
- [ ] Job `infra/lab-vm` from `infra-lab/Jenkinsfile`, parameters `ACTION` (plan, apply, destroy), `ENVIRONMENT` (staging, production), `VM_COUNT` (default 1). Stages: `terraform fmt -check` → `validate` → `tflint` → Checkov (`--framework terraform`) → select workspace → plan (archived) → approval for production only → apply or destroy → `ansible all -m ping`.

```hcl
# envs/lab/main.tf (shape)
variable "environment" { type = string }   # "staging" or "production"
variable "vm_count" {
  type    = number
  default = 1
}

locals {
  prefix = var.environment == "staging" ? "lab-stg" : "lab-prd"
}

module "vm" {
  source         = "../../modules/rhel9_vm"
  count          = var.vm_count
  name           = format("%s-%02d", local.prefix, count.index + 1)
  cpu            = 2
  memory_mb      = 4096
  golden_image   = var.golden_image
  ssh_public_key = var.ansible_ssh_public_key
}

resource "local_file" "inventory" {
  filename = "/var/lib/lab-inventory/${var.environment}/hosts.ini"
  content  = templatefile("${path.module}/hosts.ini.tftpl", {
    hosts = { for vm in module.vm : vm.name => vm.ip }
  })
}
```

**Done when**

- `ACTION=apply ENVIRONMENT=production` creates only `lab-prd-01`, and its inventory pings SUCCESS.
- `VM_COUNT=2` adds `lab-prd-02`; setting it back to 1 removes it.
- `ACTION=apply ENVIRONMENT=staging` then `ACTION=destroy ENVIRONMENT=staging` creates and removes `lab-stg-01` without touching production.
- A `plan` right after an apply shows no changes, and Checkov passes on the Terraform code.

**Watch out:** the CIS Level 1 image restricts SSH (no root login, limited ciphers, sometimes an allow-list of users). Confirm the `ansible` user and the key type are allowed by the image's SSH settings.

## Batch 7 — Deployment repo

**Goal:** one repo, `deploy-webserver`, that says which role versions go to which hosts with which variables, checked on every change.

**Files**

| File | Holds |
| --- | --- |
| `requirements.yml` | `webserver` pinned to `v0.1.0` (tags only) |
| `vars/common.yml` | `service_name: webserver`, `target_group: web`, `deploy_roles: [webserver]` |
| `vars/staging.yml`, `vars/production.yml` | `webserver_message` per environment |
| `/var/lib/lab-inventory/<environment>/hosts.ini` (on the workstation) | Written by Terraform; not committed |
| `playbooks/site.yml` | The generic playbook below |
| `playbooks/smoke.yml` | `uri` check per host: HTTP 200 and the page contains `webserver_message` |
| `scripts/check_pins.py` | Fails if any role `version` is not a `v*` tag |
| `Jenkinsfile.checks` | gitleaks, yamllint, ansible-lint, pin check, syntax check, staging `--check --diff` |

```yaml
# playbooks/site.yml — the role list is a variable, so no playbook is written per service
- name: Deploy {{ service_name }}
  hosts: "{{ target_group }}"
  become: true
  serial: "{{ deploy_serial | default([1, '50%']) }}"
  max_fail_percentage: 0
  vars_files:
    - ../vars/common.yml
    - "../vars/{{ deploy_env }}.yml"
  tasks:
    - name: Apply roles in order
      ansible.builtin.include_role:
        name: "{{ role_item }}"
      loop: "{{ deploy_roles }}"
      loop_control:
        loop_var: role_item
```

**Steps**

- [ ] Create the files above; install roles with `ansible-galaxy install -r requirements.yml -p roles/`.
- [ ] Create multibranch job `cd/deploy-webserver-checks` running `Jenkinsfile.checks` on pull requests.
- [ ] After merging, tag the deploy repo `release-1`. Every deploy uses a deploy-repo tag.

**Done when**

- Running the role once against `lab-stg-01` works with firewalld on and SELinux enforcing (moved from Batch 1: the hardened image is the real test).
- With a staging VM from `infra/lab-vm`: `ansible-playbook -i /var/lib/lab-inventory/staging/hosts.ini playbooks/site.yml -e deploy_env=staging` succeeds; a second run reports 0 changed.
- `smoke.yml` passes against staging.
- A pull request changing the pin to `version: main` fails the pin check.
- A pull request setting `webserver_port: "abc"` fails the staging dry run (role argument validation).

## Batch 8 — CD job

**Goal:** one parameterized Jenkins job, `cd/deploy-webserver`, deploys a release to staging, waits for your approval, then rolls it out to production, and records the result.

**Parameters:** `ENVIRONMENT` (staging or production), `RELEASE` (a deploy-repo tag such as `release-1`), `LIMIT` (optional host list).

**Stages**

1. Checkout the deploy repo at `RELEASE`.
2. Install roles from `requirements.yml`.
3. Preflight: syntax check and `ansible -m ping` on the target hosts.
4. Create the staging VM (runs `infra/lab-vm` with `ENVIRONMENT=staging`), deploy and smoke-test it, then destroy it, even if the deploy failed.
5. Production only: `--check --diff` preview saved as `prod-diff.txt`.
6. Production only: approval with the Jenkins `input` step, reading the preview first.
7. Production only: rolling deploy (1 host, then the rest), then smoke-test production.
8. Always, even on failure: write `deploy-record.json` and archive it with `prod-diff.txt`.

```groovy
// Jenkinsfile.deploy (outline)
pipeline {
  agent { label 'ansible' }
  options { disableConcurrentBuilds() }
  parameters {
    choice(name: 'ENVIRONMENT', choices: ['staging', 'production'])
    string(name: 'RELEASE', defaultValue: 'release-1')
    string(name: 'LIMIT', defaultValue: '')
  }
  stages {
    stage('Checkout release')   { /* deploy repo at params.RELEASE */ }
    stage('Install roles')      { /* ansible-galaxy install -r requirements.yml -p roles/ --force */ }
    stage('Preflight')          { /* --syntax-check, ping */ }
    stage('Create staging VM')  { /* build job: 'infra/lab-vm', ACTION=apply, ENVIRONMENT=staging */ }
    stage('Deploy staging')     { /* site.yml -i /var/lib/lab-inventory/staging/hosts.ini -e deploy_env=staging */ }
    stage('Smoke staging')      { /* smoke.yml */ }
    stage('Production preview') { when { expression { params.ENVIRONMENT == 'production' } } /* --check --diff */ }
    stage('Approval')           { when { expression { params.ENVIRONMENT == 'production' } }
                                  steps { input message: 'Deploy to production?', submitter: '<your Jenkins user>' } }
    stage('Deploy production')  { /* site.yml -i /var/lib/lab-inventory/production/hosts.ini -e deploy_env=production */ }
    stage('Smoke production')   { /* smoke.yml */ }
  }
  post { always { /* destroy staging VM via infra/lab-vm, scripts/record_deploy.py, archiveArtifacts */ } }
}
```

SSH to the VMs uses the `lab-ssh-key` credential through `sshagent`.

**Deploy record** (one per run; the dashboard reads only this)

```json
{
  "service": "webserver",
  "environment": "production",
  "release": "release-1",
  "role_versions": {"webserver": "v0.1.0"},
  "started_by": "aeron",
  "approved_by": "aeron",
  "started_at": "2026-11-07T10:02:00+08:00",
  "finished_at": "2026-11-07T10:09:00+08:00",
  "result": "SUCCESS",
  "failed_stage": null,
  "hosts": {"ok": 3, "changed": 2, "failed": 0},
  "build_url": "http://localhost:8080/job/cd/job/deploy-webserver/12/"
}
```

**Done when**

- `ENVIRONMENT=staging` deploys and smoke-tests a fresh `lab-stg-01`, which no longer exists when the run ends.
- `ENVIRONMENT=production` deploys staging, pauses at Approval with the preview available, then after Proceed updates `lab-prd-01` (with `VM_COUNT=2`, `lab-prd-01` before `lab-prd-02`).
- Each run archives a `deploy-record.json` with the right result.
- Failure drill: a release with `webserver_port: "abc"` fails at Deploy staging, production is untouched, and the record says `FAILURE` with `failed_stage: "Deploy staging"`.

## Batch 9 — Rollback drill

**Goal:** run the whole loop once more with a new role version, then prove you can return production to the previous release.

**Steps**

- [ ] In the role repo, change the index page wording and bump `VERSION` to `0.2.0` through a pull request; CI tags `v0.2.0`.
- [ ] In the deploy repo, change the pin to `v0.2.0` through a pull request, merge, tag `release-2`.
- [ ] Run `cd/deploy-webserver` with `ENVIRONMENT=production`, `RELEASE=release-2`.
- [ ] Roll back: run the same job with `RELEASE=release-1`.

**Done when**

- After `release-2`, production smoke tests see the new wording.
- After the rollback, production smoke tests see the `v0.1.0` wording again, and the second deploy in a row of `release-1` reports 0 changed.
- Jenkins history shows three runs with three deploy records: release-1, release-2 and the rollback to release-1.

Rollback is just a normal deploy of an older tag. It works cleanly because Molecule enforced idempotence in CI.

## Batch 10 — Operator dashboard

**Goal:** a non-technical person can see what is deployed where and how each deploy went, without opening Jenkins.

**How it gets data:** a small backend calls the Jenkins API for `cd/deploy-webserver` builds and reads each build's `deploy-record.json`. It uses a read-only Jenkins API token held on the server, never in the browser.

**Pages**

| Page | Shows | Answers |
| --- | --- | --- |
| Overview | One card per environment: current release, role version, result colour, last deploy time | What is running where, and is it healthy? |
| History | Newest first: when, environment, release, started by, approved by, result | What changed, and who did it? |
| Detail | Stage timeline, host counts, plain summary, link to the Jenkins build | Why did it fail, and what was affected? |
| Waiting for approval | Builds paused at the Approval stage | What is waiting on me? |

**Plain-language statuses:** SUCCESS shows as Succeeded, FAILURE as Failed (with the stage, for example "Failed at Deploy staging; production was not touched"), ABORTED as Cancelled, a paused build as Waiting for approval, a run that deploys an older release as Rolled back.

**Steps**

- [ ] Build `cd-dashboard`: a small Python web app (for example Flask) with server-side Jenkins calls and four HTML pages.
- [ ] Map Jenkins results to the plain statuses above.
- [ ] Add a "Request a deploy" link to the Jenkins job's Build with Parameters page (lab only).
- [ ] Run it on the workstation; no sign-in in the lab.

**Done when**

- Overview shows `release-1` on staging and production after the Batch 9 rollback.
- History lists the Batch 8 and 9 runs, including the failure drill, explained in plain words.
- A non-technical colleague answers "what is in production, and did the last deploy work?" in under a minute without help.

## Batch 11 — Wrap-up and what comes after the lab

**Goal:** the lab is documented well enough that someone else can repeat it, and the next phase is decided.

**Steps**

- [ ] A README in each repo: what it is, how to run it, how to test it.
- [ ] A one-page operator guide with dashboard screenshots: reading status, requesting a deploy, what to do on a failure.
- [ ] A rollback runbook (Batch 9, written as steps).
- [ ] Lessons learned: what broke, what was slow, what surprised you.

**Done when:** a teammate who has not seen the lab deploys `release-2` and rolls it back using only the READMEs.

**Next phase, in suggested order**

1. Builds on a separate agent instead of the built-in node; webhooks straight to a reachable Jenkins URL instead of the smee relay.
2. Secrets from a vault (HashiCorp Vault or Ansible Vault) instead of Jenkins credentials.
3. Jenkins permissions (Role-based Authorization Strategy plugin) so operators see only `cd/` jobs, or nothing but the dashboard.
4. Dashboard sign-in and Deploy / Approve buttons that call Jenkins directly.
5. Automatic version-bump pull requests in deploy repos (Renovate).
6. More Molecule scenarios if roles must support RHEL 8 or 10, or multi-node layouts; a real-VM test scenario on pull requests.

## Repo layout (reference)

Local folders sit side by side in `/home/bunny/`; each is its own GitHub repo, created in the batch shown.

```text
ansible-pipeline/                    # Batch 0 — the CI itself (this folder)
├── Jenkinsfile                      # central role CI: gates + release
├── ci/requirements-*.txt            # pinned tool versions for /opt/ci and /opt/checkov
├── ci/.yamllint  ci/.ansible-lint  ci/.gitleaks.toml   # defaults; a role's own copy wins (Batch 2)
├── docs/PLAN.md                     # this plan
└── docs/ci/                         # setup-guide, evidence, troubleshooting; later gates, onboarding, gate drills

ansible-role-webserver/              # Batches 0–1 — example role and template; no pipeline code
├── defaults/  tasks/  handlers/  templates/
├── meta/main.yml                    # also the marker file that makes a branch buildable
├── meta/argument_specs.yml
├── molecule/default/                # 1 × ubi9-init
└── VERSION

infra-lab/                           # Batch 6 — Terraform for the lab VMs
├── modules/rhel9_vm/  envs/lab/
└── Jenkinsfile                      # infra/lab-vm: plan → approval → apply

deploy-webserver/                    # Batches 7–8 — what goes where
├── requirements.yml  vars/  playbooks/  scripts/
├── Jenkinsfile.checks               # pull request checks
└── Jenkinsfile.deploy               # the CD job

cd-dashboard/                        # Batch 10 — operator view
├── app.py
└── templates/
```
