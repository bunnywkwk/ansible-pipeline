# ansible-pipeline

Central CI for Ansible roles. Role repos hold only role code; Jenkins tests every branch and pull request of every role with the one [`Jenkinsfile`](Jenkinsfile) in this repo, and turns a green `main` into a release tag.

- **For role authors:** [docs/ci/onboarding-a-role.md](docs/ci/onboarding-a-role.md) — what your repo needs and how to get it built.
- **For the Jenkins admin:** [docs/ci/setup-guide.md](docs/ci/setup-guide.md) — build this CI from scratch, one line per step.
- **Proof:** [docs/ci/evidence.md](docs/ci/evidence.md) (real output of every check) · [docs/ci/troubleshooting.md](docs/ci/troubleshooting.md) (errors met, cause, fix) · [docs/PLAN.md](docs/PLAN.md) (batches and decisions).

## How it works

![Role CI: a push or PR reaches Jenkins through smee; Jenkins loads the Jenkinsfile from ansible-pipeline, checks out the role commit and runs six stages cheapest first; any red stage posts a red status, all green posts a green one, and on main Release adds a version tag.](docs/ci/pipeline.svg)

1. **Recipe:** Jenkins loads the `Jenkinsfile` from this repo. A `Jenkinsfile` in a role repo is ignored.
2. **Code:** it checks out the role commit being built (branch, PR or `main`).
3. **Stages:** cheapest first; the first red stage stops the build, so most mistakes fail in seconds, before Molecule starts a container.

The pipeline never names a repo: Jenkins fills `scm` with the role, branch and commit being built, so the same file serves every role.

## Gates

Each gate was proven by pushing a bad commit on purpose (Batch 3 drills; real output in [evidence.md](docs/ci/evidence.md)).

| Stage | Tool | Catches | Proven by | If it is red |
| --- | --- | --- | --- | --- |
| Secrets | gitleaks 8.30.1 | Keys and tokens anywhere in the branch's history, value redacted in the log | Drill 4: key found, still found after a revert commit | Revoke the secret first, then remove the commit from the branch and force-push |
| Version | `grep` | `VERSION` that is not `X.Y.Z` | PR #2 (merged before this stage existed, broke `main`) | Fix `VERSION` in the pull request |
| YAML lint | yamllint 1.38.0 | Broken YAML: indentation, syntax | Drill 1 | Fix the file and line printed (`file:line:col`) |
| Ansible lint | ansible-lint 26.11.0, profile `production` | Unknown modules, bad Ansible practice (`shell` for a package, no `changed_when`) | Drills 2 and 3 | Read the rule name; its docs link explains the fix |
| Security | Checkov 3.4.3 | Insecure settings such as `validate_certs: false` | Drill 5 | Fix the setting; skip only with a reason inside the task (`# checkov:skip=ID: reason`) |
| Molecule | Molecule 26.9.0, Podman | The role does not run, is not idempotent, or does not do what `verify.yml` says | Drills 6 (verify) and 7 (idempotence) | Run `molecule test` locally; the failing step and task are named |
| Release | git | — (`main` only): tags the tested commit `v<VERSION>`; skips if the tag exists | `v0.1.0` from `main` #5; skip on #7 | 403 on push: the token needs Contents write |

After every build, `post` removes any Molecule container left by an abort and archives `reports/` (gitleaks and ansible-lint SARIF, Checkov JUnit XML).

## Branches, pull requests and releases

- **Every branch** with `meta/main.yml` is built; GitHub shows `continuous-integration/jenkins/branch`.
- **A pull request** is built instead of its branch and shows `continuous-integration/jenkins/pr-head`.
- **`main`** accepts changes only through a pull request whose `pr-head` check is green and whose branch is up to date with `main`. No force push, no deletion, no bypass (GitHub ruleset).
- **To release:** change `VERSION` in the pull request. After the merge, `main` tags `v<VERSION>`. Tags `v*` cannot be moved or deleted (GitHub ruleset).
- **Use a release:**

  ```yaml
  # requirements.yml
  roles:
    - name: bunnywkwk.webserver
      src: https://github.com/bunnywkwk/ansible-role-webserver.git
      scm: git
      version: v0.1.0
  ```

## Build it yourself

Full commands in the [setup guide](docs/ci/setup-guide.md); in short:

1. Two public GitHub repos: `ansible-pipeline` (this) and a role repo.
2. A fine-grained token for the role repos: Contents read and write, Metadata and Pull requests read, Commit statuses read and write.
3. Build node: subordinate IDs and linger for `jenkins` (rootless Podman), `/opt/ci` and `/opt/checkov` venvs from `ci/requirements-*.txt`, gitleaks binary (checksum verified).
4. Jenkins: plugins (GitHub Branch Source, Remote Jenkinsfile Provider, …), label `ansible` on the build node, credential `github-crendentials` with the token, folder `role-ci`.
5. Per role repo: a multibranch job in "Remote Jenkins File Provider" mode, marker `meta/main.yml`, Jenkinsfile from this repo's `main`.
6. Webhook through a smee channel, smee client as a user service.
7. GitHub rulesets: role `main` (PR + `pr-head` + up to date), role tags `v*` (no update or delete), this repo's `main` (no force push or delete).

## Repo layout

| Path | Holds |
| --- | --- |
| `Jenkinsfile` | The pipeline, for every role |
| `ci/requirements-tools.txt` | Pinned ansible-core 2.16, ansible-lint, yamllint, Molecule (`/opt/ci`) |
| `ci/requirements-checkov.txt` | Pinned Checkov (`/opt/checkov`, own venv: its pins clash with the tools above) |
| `docs/` | Plan, setup guide, onboarding, evidence, troubleshooting |

## Known limits

- **Lab shortcuts:** builds run on the Jenkins controller itself (built-in node), and user `jenkins` is also in the `docker` group (root-equivalent). Move builds to a separate agent before real use.
- **Containers, not VMs (yet):** Molecule tests in a `ubi9-init` container, without firewalld (`webserver_manage_firewall: false` in the test) and without the host's SELinux. Next step: every pull request also runs the role on a short-lived RHEL 9 VM ([PLAN, Batch 4b](docs/PLAN.md#batch-4b--pr-test-on-a-lab-vm)).
- **Lint gaps found:** `command: dnf install …` with `changed_when: false` passes ansible-lint (its rule knows `yum`, not `dnf`); Checkov missed `yum_repository` with `gpgcheck: false` in an earlier spike. PR review covers both for now.
- **ansible-core 2.16** is end of life upstream; kept because it is the version in use.
- **One token** acts as the GitHub user, so GitHub cannot tell a Jenkins tag from a hand-made one; the tag ruleset blocks changes, not creation.
- **Not tested yet:** a second role (Batch 5); a red pull request's blocked merge button and a refused tag move (rulesets read back from the API, not exercised).
