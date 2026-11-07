# Use the central CI for your role

How to get a role repo built and released by [ansible-pipeline](../../README.md). You write role code only; the pipeline is never copied into your repo.

> **Status:** written from the first role, `ansible-role-webserver`. A second role has not been onboarded yet (Batch 5); report anything here that does not work.

## 1. Start the repo

Name it `ansible-role-<name>`, public, on GitHub. Copy the layout of [ansible-role-webserver](https://github.com/bunnywkwk/ansible-role-webserver) (a template repo from Batch 5):

```text
ansible-role-<name>/
├── meta/main.yml            # required: the marker; no meta/main.yml, no build
├── meta/argument_specs.yml  # variable types, checked before tasks run
├── defaults/main.yml
├── tasks/main.yml
├── handlers/main.yml        # if needed
├── templates/               # if needed
├── requirements.yml         # collections the role uses
├── VERSION                  # X.Y.Z, e.g. 0.1.0
├── README.md
└── molecule/default/
    ├── molecule.yml
    ├── converge.yml
    └── verify.yml
```

Do **not** add a `Jenkinsfile`: it would be ignored (Batch 3 drill 8).

## 2. Files the pipeline depends on

**`meta/main.yml`** — `namespace` and `role_name` give the role its full name, `<namespace>.<role_name>`:

```yaml
galaxy_info:
  author: <you>
  namespace: <namespace>
  role_name: <name>
  min_ansible_version: "2.16"
  platforms:
    - name: EL
      versions: ["9"]
```

**`molecule/default/converge.yml`** — import the role by that **same** full name. Molecule and ansible-lint link your checkout under it, so the test runs this commit, and ansible-lint can syntax-check the role's tasks. A name that does not match `meta/main.yml` fails with "role not found".

```yaml
- name: Converge
  hosts: all
  gather_facts: false
  tasks:
    - name: Run the role from this checkout
      ansible.builtin.import_role:
        name: <namespace>.<name>
```

**`molecule/default/molecule.yml`** — keep from the webserver role:

- platform name ending in `-${MOLECULE_RUN_ID:-local}`: CI sets a short unique ID, so parallel builds do not clash and the hostname stays under 64 characters
- image `registry.access.redhat.com/ubi9/ubi-init:latest`, `command: /usr/sbin/init`, `systemd: always`
- the written-out `test_sequence`: `dependency, destroy, create, converge, idempotence, verify, destroy`
- `group_vars` to switch off what containers lack (the webserver role sets `webserver_manage_firewall: false`)

**`molecule/default/verify.yml`** — check what the role is for (service up, page served, file present), with the expected values written out, not read from `defaults/`. A change of behaviour must then be a deliberate change to the test too (drill 6).

**`requirements.yml`** — every collection the role uses. CI starts from an empty collection set; a missing entry fails Molecule there even if it passes on your machine.

**Optional:** a `.yamllint`, `.ansible-lint`, `.gitleaks.toml` or `.checkov.yml` in the repo root changes that tool's rules for your role only. Without one, the tool's defaults apply.

## 3. Check locally before you push

With the same tools as CI (`/opt/ci`, see the setup guide):

```bash
. /opt/ci/bin/activate
yamllint . && ansible-lint --profile production && /opt/checkov/bin/checkov -d . --framework ansible --skip-download
ANSIBLE_HOME=$(mktemp -d) molecule test     # empty Ansible home, like a fresh CI node
```

Idempotence must report `changed=0`.

## 4. Ask the Jenkins admin to connect the repo

Three one-time steps, no pipeline change ([setup guide](setup-guide.md), "Adding another role repo"):

1. Add the repo to the GitHub token's repository access.
2. Create its multibranch job in `role-ci` (Remote Jenkins File Provider mode, marker `meta/main.yml`).
3. Add the smee webhook (JSON, Pushes and Pull requests) and the rulesets for `main` and tags `v*`.

## 5. Work through pull requests

1. Push a feature branch: Jenkins builds it within seconds and the commit shows ✓ or ✗.
2. Open a pull request to `main`: the PR is built and must show `continuous-integration/jenkins/pr-head` green, with the branch up to date, before it can merge.
3. Red? Open the build's console (link on the ✗). The failed stage says what to fix; see the gate table in the [README](../../README.md#gates).

## 6. Release

Change `VERSION` (e.g. `0.1.0` → `0.2.0`) in the pull request. After the merge, the `main` build tags `v0.2.0` on the tested commit. A merge without a `VERSION` change releases nothing (`release skipped`). Released tags cannot be moved or deleted.

Users install a release by tag:

```yaml
roles:
  - name: <namespace>.<name>
    src: https://github.com/<owner>/ansible-role-<name>.git
    scm: git
    version: v0.2.0
```
