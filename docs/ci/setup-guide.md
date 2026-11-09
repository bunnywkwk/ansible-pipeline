# Role CI setup guide

How to build the central role CI again, batch by batch. One line per step. Proof of each step is in [evidence.md](evidence.md); errors met on the way are in [troubleshooting.md](troubleshooting.md).

**Starting point:** Fedora workstation with Jenkins (RPM, runs as user `jenkins`), Podman, git, Python 3.11, Node.js with `smee-client`. Values used in this lab: GitHub user `bunnywkwk`, `jenkins` uid 962.

## How it works

```text
git push (role repo) → GitHub webhook → smee.io → smee client → Jenkins /github-webhook/
  → branch has meta/main.yml? (marker) → yes: build
  → Jenkins reads Jenkinsfile from ansible-pipeline   (the recipe)
  → Jenkins checks out the role's commit              (the code under test)
  → stages run on the node labelled "ansible"         → ✓ or ✗ posted back to the commit on GitHub
```

## Batch 0 — CI foundation

### Part 1 — GitHub

1. **Create public repo `ansible-pipeline`, all "Initialize" boxes unchecked.** It holds the central `Jenkinsfile`, pinned tool lists and docs; empty so the first push is clean.
2. **Create public repo `ansible-role-webserver`, same settings.** It holds role code only, never pipeline code.
3. **Create a fine-grained token** (Settings → Developer settings → Fine-grained tokens): Repository access = *Only select repositories* with each role repo; permissions Contents **read and write** (write from Batch 4: Jenkins pushes release tags), Metadata read, Pull requests read, **Commit statuses read and write**. Jenkins reads code with it and posts the ✓/✗; listing only role repos keeps it from touching anything else. `ansible-pipeline` does not need to be listed: any token can read a public repo.

### Part 2 — Build node (run with sudo)

4. **Give `jenkins` a subordinate ID range** (pick a block no other user has in `/etc/subuid`):
   ```bash
   sudo usermod --add-subuids 786432-851967 --add-subgids 786432-851967 jenkins
   ```
   Rootless containers map their own users (root, nginx, …) to these host IDs; without a range, images like `ubi9-init` fail to extract.
5. **Enable linger for `jenkins`:**
   ```bash
   sudo loginctl enable-linger jenkins
   ```
   `jenkins` never logs in, so this starts its user manager and `/run/user/962` at boot; rootless Podman keeps its runtime files there and needs it for systemd containers.
6. **Create the CI tools venv:**
   ```bash
   cd ~/ansible-pipeline        # after Part 4 step 14, or with ci/requirements-tools.txt at hand
   sudo python3.11 -m venv /opt/ci
   sudo /opt/ci/bin/pip install -r ci/requirements-tools.txt
   ```
   Pinned ansible-core 2.16, ansible-lint, yamllint, Molecule; root-owned so builds cannot change their own tools.
7. **Create the Checkov venv:**
   ```bash
   sudo python3.11 -m venv /opt/checkov
   sudo /opt/checkov/bin/pip install -r ci/requirements-checkov.txt
   ```
   Checkov pins many shared libraries; its own venv stops them clashing with the tools above.
8. **Install gitleaks, checksum verified:**
   ```bash
   cd "$(mktemp -d)"            # empty folder: downloads stay out of the repo
   V=8.30.1
   curl -sSLO https://github.com/gitleaks/gitleaks/releases/download/v$V/gitleaks_${V}_linux_x64.tar.gz
   curl -sSLO https://github.com/gitleaks/gitleaks/releases/download/v$V/gitleaks_${V}_checksums.txt
   sha256sum --check --ignore-missing gitleaks_${V}_checksums.txt
   tar xzf gitleaks_${V}_linux_x64.tar.gz gitleaks
   sudo install -m 0755 gitleaks /usr/local/bin/gitleaks
   ```
   A single binary for the secrets scan; the checksum proves the download is the published release.
9. **Check every tool with the venv activated:**
   ```bash
   . /opt/ci/bin/activate
   ansible --version | head -1; ansible-lint --version | head -1; yamllint --version
   NO_COLOR=1 molecule --version | grep -E '^molecule|ansible:'
   /opt/checkov/bin/checkov --version; gitleaks version; deactivate
   ```
   Always activate, never call by full path: otherwise Molecule finds Fedora's `/usr/bin/ansible` first.

### Part 3 — Jenkins (UI at http://localhost:8080)

10. **Plugins** (Manage Jenkins → Plugins): Pipeline, Git, GitHub Branch Source, **Remote Jenkinsfile Provider**, Credentials Binding, Timestamper, Pipeline: Stage View, JUnit. Remote Jenkinsfile Provider is what lets a repo build from a Jenkinsfile kept in another repo.
11. **Label the Built-In Node `ansible`** (Manage Jenkins → Nodes → Built-In Node → Configure; executors ≥ 1, usage unchanged). The pipeline asks for "a node with the tools", not a machine name, so moving to a separate agent later means moving the label only.
12. **Credential `github-crendentials`** (Manage Jenkins → Credentials → Global): kind *Username with password*, username = GitHub user, password = the token from step 3. GitHub Branch Source needs this kind for a token.
13. **Folder `role-ci`** (New Item → Folder). Keeps CI jobs apart from CD jobs.

### Part 4 — Repo contents

14. **Push `ansible-pipeline`** with `Jenkinsfile`, `ci/requirements-tools.txt`, `ci/requirements-checkov.txt` and `docs/`:
    ```bash
    cd ~/ansible-pipeline
    git init -b main && git add Jenkinsfile ci docs && git commit -m "Central role CI"
    git remote add origin https://github.com/bunnywkwk/ansible-pipeline.git && git push -u origin main
    ```
    The `Jenkinsfile` never names a role repo: Jenkins checks out whichever repo the job is for (`checkout scm`).
15. **Push the role with at least `meta/main.yml`:**
    ```bash
    cd ~/ansible-role-webserver
    git init -b main && git add README.md meta/main.yml && git commit -m "Start webserver role"
    git remote add origin https://github.com/bunnywkwk/ansible-role-webserver.git && git push -u origin main
    ```
    `meta/main.yml` is the marker: only branches containing it are built. `git push` over HTTPS asks for a token with Contents write, not the Jenkins token.

### Part 5 — Job and trigger

16. **Multibranch job** (in `role-ci`: New Item → `ansible-role-webserver` → Multibranch Pipeline):
    | Setting | Value |
    | --- | --- |
    | Branch Sources → GitHub | credential `github-crendentials`, URL `https://github.com/bunnywkwk/ansible-role-webserver.git` |
    | Build Configuration → Mode | **by Remote Jenkins File Provider Plugin** |
    | Local Marker | `meta/main.yml` |
    | Script Path | `Jenkinsfile` |
    | Remote Jenkinsfile SCM → Git | `https://github.com/bunnywkwk/ansible-pipeline.git`, credential `github-crendentials`, branch `*/main` |
    | Scan Multibranch Pipeline Triggers | Periodically if not otherwise run: **1 day** |

    The job watches the role repo but takes the recipe from `ansible-pipeline`; the daily scan only catches events smee missed. Saving starts the first scan and builds `main`.
17. **Create a smee channel** at https://smee.io/new and copy its URL. GitHub cannot reach `localhost:8080`; smee relays webhooks to it.
18. **Run the smee client as a user service:**
    ```bash
    mkdir -p ~/.config/systemd/user
    cat > ~/.config/systemd/user/smee-jenkins.service <<'EOF'
    [Unit]
    Description=smee relay: GitHub webhooks to local Jenkins
    After=network-online.target

    [Service]
    # smee is a Node script; systemd's PATH does not include ~/.local/node/bin
    Environment=PATH=/home/bunny/.local/node/bin:/usr/bin
    # ?smee=1 keeps the trailing slash (smee-client strips it, Jenkins then answers 405)
    ExecStart=/home/bunny/.local/node/bin/smee -u https://smee.io/<channel> -t http://localhost:8080/github-webhook/?smee=1
    Restart=always
    RestartSec=10

    [Install]
    WantedBy=default.target
    EOF
    systemctl --user daemon-reload
    systemctl --user enable --now smee-jenkins.service
    ```
    Runs at login and restarts on failure, so pushes trigger builds without an open terminal.
19. **Webhook on the role repo** (Settings → Webhooks → Add webhook): Payload URL = smee channel URL, content type **`application/json`**, events **Pushes** and **Pull requests**. JSON is required: with the default form type, smee mangles the payload and Jenkins ignores it.

### Part 6 — Check it works

20. **Webhook relay:** `journalctl --user -u smee-jenkins -n 5 --no-pager` shows `POST http://localhost:8080/github-webhook/?smee=1 - 200` after GitHub's ping.
21. **Push to the role** (any small change): a `main` build starts within seconds. Its console shows the Jenkinsfile read from `ansible-pipeline`, the role cloned in `Declarative: Checkout SCM`, `No Jenkinsfile in this repo`, the tool versions, `systemd in container: running`, and `Finished: SUCCESS`.
22. **Status on GitHub:** the commit shows `continuous-integration/jenkins/branch` ✓ ("This commit looks good").
23. **Marker:** push a branch without `meta/main.yml`; no branch job appears for it. Delete the branch afterwards.

## Batch 1 — Template role

24. **Write the role** in `ansible-role-webserver`: `defaults/` (variables), `meta/argument_specs.yml` (type checks), `tasks/` and `handlers/`, `templates/` (server block and page), `requirements.yml` (collections the role needs), `VERSION` (`0.1.0`).
25. **(Replaced in Batch 4b: tests now live in `ansible-pipeline/ci/molecule/`.)** Write the Molecule test in `molecule/default/`: `molecule.yml` (one `ubi9-init` container and the test steps), `converge.yml` (runs the role from the checkout with `import_role: name: <namespace>.<role_name>` from `meta/main.yml`; static, so ansible-lint also syntax-checks the role's tasks), `verify.yml` (nginx up, page shows the message).
26. **Lint by hand:**
    ```bash
    . /opt/ci/bin/activate
    yamllint . && ansible-lint --profile production && /opt/checkov/bin/checkov -d . --framework ansible --skip-download
    ```
27. **Test by hand on an empty Ansible home**, like a fresh CI node: `ANSIBLE_HOME=$(mktemp -d) molecule test`. Idempotence must show `changed=0`.
28. **Push on a feature branch**, never straight to `main`: `git switch -c feature/webserver-role`, commit, `git push -u origin feature/webserver-role`.

## Batch 2 — Central pipeline

29. **Replace the spike stage in `ansible-pipeline/Jenkinsfile` with the gates** (Secrets, YAML lint, Ansible lint, Security, Molecule) and push. Role repos do not change.
30. **Build the feature branch** (Jenkins → the branch → Build Now): all five stages green, reports under *Build Artifacts*.
31. **Open a pull request** from the feature branch to `main`: Jenkins builds `PR-1` by itself and the PR shows the check. Do not merge yet; the merge gate comes in Batch 4.

## Batch 3 — Gate drills

32. **Break each gate once** on its own branch `drill/NN-name` from the feature branch, push, and record predicted vs real in [evidence.md](evidence.md). A gate that stays green is a gap: fix it on the feature branch, rebase the drill branch, push again.
33. **Keep the drill branches** on GitHub as evidence; they stay red in Jenkins, which is the point.

## Batch 4 — Release and merge gate

34. **Push the `Version` and `Release` stages** in `Jenkinsfile`: Version checks `VERSION` is `X.Y.Z` on every build; Release, on `main` only, tags the tested commit `v<VERSION>` unless the tag exists.
35. **Give the token Contents read and write** (step 3): Jenkins pushes the tag with it; without write, the push fails with 403.
36. **Ruleset on the role's `main`** (Settings → Rules → Rulesets → New branch ruleset, Active, no bypass, default branch): restrict deletions, require a pull request, require status check `continuous-integration/jenkins/pr-head` with branches up to date, block force pushes.
37. **Ruleset on the role's tags** (New tag ruleset, Active, pattern `v*`): restrict updates and deletions only; creation must stay allowed for Jenkins.
38. **Ruleset on `ansible-pipeline` `main`:** restrict deletions and block force pushes; direct pushes stay allowed.
39. **Merge the first pull request:** the `main` build ends with `Released v0.1.0 at <commit>`.
40. **To release later:** change `VERSION` in a pull request; a merge without it prints `release skipped`.

## Batch 4b — PR test on a VM

41. **Install on the host:** Terraform, Packer, KVM with libvirt, `genisoimage`; `jenkins` in group `libvirt`.
42. **Build the golden image and put it in pool `ci`:** `~/ansible-cis/docs/local-laptop/updated-doc-setup/golden-image-rhel9.md`, steps 1–4. Plain RHEL 9.8; every test VM is a throwaway copy of it.
43. **Jenkins credentials `rhsm-org`, `rhsm-activation-key`** (Secret text): each VM registers with Red Hat through cloud-init, to install packages.
44. **Push `Jenkinsfile` and `ci/molecule/`:** the pipeline follows the event table in the README and copies the tests into each build.
45. **Job → Branch Sources → delete "Discover pull requests from forks":** a fork's role code would otherwise run on this host.
46. **Role ruleset on `main` → Allowed merge methods: Merge only:** Release tags only PR merge commits; squash has one parent and would never release.
47. **Open a PR:** the console shows Terraform apply, `SELinux is enforcing`, converge, idempotence `changed=0`, destroy; `virsh list --all` then shows no `role-vm-*`.

## Adding another role repo (until Batch 5 automates it)

Add the repo to the token's repository access (step 3), create its multibranch job (step 16), add the webhook (step 19) and the rulesets (steps 36–37). The pipeline itself needs no change. What the role repo itself needs: [onboarding-a-role.md](onboarding-a-role.md).
