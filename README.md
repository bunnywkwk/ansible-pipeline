# ansible-pipeline

Central CI for Ansible roles. A role repo holds only role code. Jenkins brings the pipeline and the tests from this repo, tests every branch and pull request, runs pull requests on a real RHEL 9 VM, and tags releases from `main`.

- **For role authors:** [docs/ci/onboarding-a-role.md](docs/ci/onboarding-a-role.md) — what your repo needs and how to get it built.
- **For the Jenkins admin:** [docs/ci/setup-guide.md](docs/ci/setup-guide.md) — build this CI from scratch, one line per step.
- **Proof:** [docs/ci/evidence.md](docs/ci/evidence.md) (real output of every check) · [docs/ci/troubleshooting.md](docs/ci/troubleshooting.md) (errors met, cause, fix) · [docs/PLAN.md](docs/PLAN.md) (batches and decisions).

## How it works

![What the pipeline does: any role gets quick checks and a container test on a branch, quick checks and a test on a fresh real RHEL 9 VM when asking to merge, and a permanent version tag after the merge. Any failed check stops there.](docs/ci/pipeline.svg)

| Event | Runs |
| --- | --- |
| Push to a branch with no PR | Gates + container test |
| PR opened or updated | Gates + **VM test** |
| Merge to `main` | **Release only** |

A branch with an open PR builds as the PR only. `main` needs no tests: the PR must be green and up to date, so it merges exactly what was tested.

### Where things come from

![Your role repo gives the code and, if you want, its own play and settings; ansible-pipeline gives the recipe and the tests; Jenkins joins them and tests a branch in a container, a pull request on a fresh real RHEL 9 VM.](docs/ci/where-things-come-from.svg)

The pipeline never names a role: Jenkins fills `scm` with the role, branch and commit being built, so the same file serves every role.

### Inside a test

![Five steps: make the machine, set it up (the container gets the RHEL 9 minimal install, the VM registers with Red Hat), run the role, run it again (nothing may change), delete. Only steps 1 and 2 differ between the container and the VM.](docs/ci/inside-a-test.svg)

| | Container test (branch) | VM test (pull request) |
| --- | --- | --- |
| Driven by | Molecule (`ci/molecule/container/`) | `ansible-playbook`, like ansible-lockdown (`ci/molecule/vm/vm-test.sh`) |
| Machine | Podman, Rocky Linux 9 (RHEL 9 rebuild), privileged, RHEL 9 minimal install added | Terraform, a fresh copy of the RHEL 9 golden image, registered with Red Hat |
| Same file | `shared/site.yml` | The same |

### Your role's settings: the `ci/` folder

Optional, in the role repo. The pipeline looks for these exact names:

| File | Used in |
| --- | --- |
| `ci/site.yml` | Both tests: your play instead of the pipeline's (every play `hosts: all`) |
| `ci/group_vars/all.yml` | Both tests |
| `ci/group_vars/container.yml` | Container test only |
| `ci/group_vars/vm.yml` | VM test only |

No `ci/` folder: the role runs with its own defaults. Details and an example: [onboarding](docs/ci/onboarding-a-role.md#2-files-the-pipeline-depends-on).

## Gates

Gates 1–5 run on branches and PRs, cheapest first; the first red stage stops the build. Proof is in [evidence.md](docs/ci/evidence.md); the drills ran on the earlier layout, when Molecule still lived in the role.

| Stage | Tool | Catches | Proven by | If it is red |
| --- | --- | --- | --- | --- |
| Secrets | gitleaks 8.30.1 | Keys and tokens anywhere in the branch's history, value redacted in the log | Drill 4: key found, still found after a revert commit | Revoke the secret first, then remove the commit from the branch and force-push |
| Version | `grep` | `VERSION` that is not `X.Y.Z` | PR #2 (merged before this stage existed, broke `main`) | Fix `VERSION` in the pull request |
| YAML lint | yamllint 1.38.0 | Broken YAML: indentation, syntax | Drill 1 | Fix the file and line printed (`file:line:col`) |
| Ansible lint | ansible-lint 26.11.0, profile `production` | Unknown modules, bad Ansible practice (`shell` for a package, no `changed_when`) | Drills 2 and 3 | Read the rule name; its docs link explains the fix |
| Security | Checkov 3.4.3 | Insecure settings such as `validate_certs: false` | Drill 5 | Fix the setting; skip only with a reason inside the task (`# checkov:skip=ID: reason`) |
| Container test | Molecule 26.9.0, Podman, Rocky Linux 9 with the RHEL 9 minimal install, like the VM (firewalld, logind) | The role does not run or is not idempotent (branch builds) | Drill 7; jenkins `staging` #5, registry `staging` #2 | Read the failing step and task in the console |
| VM test | Terraform, KVM, `ansible-playbook` (run twice) | The same, on real RHEL 9: SELinux enforcing, firewalld on, packages from Red Hat (PR builds) | `PR-4` #2, green run only | Read the failing task in the console |
| Release | git | — (`main` only): tags the PR's commit `v<VERSION>`; skips if the tag exists, or if the commit is not a PR merge | `v0.1.1` from `main` #9; skip on #8 | 403 on push: the token needs Contents write |

The tests only prove the role runs and is idempotent: there is no verify step for now. Checking what the role does belongs to a separate audit.

After every branch and PR build, `post` removes any container or VM left by an abort and archives `reports/` (gitleaks and ansible-lint SARIF, Checkov JUnit XML).

## Branches, pull requests and releases

- **Every branch** with `meta/main.yml` is built; GitHub shows `continuous-integration/jenkins/branch`.
- **A pull request** is built instead of its branch and shows `continuous-integration/jenkins/pr-head`.
- **`main`** accepts changes only through a pull request whose `pr-head` check is green and whose branch is up to date with `main`, merged with a merge commit. No force push, no deletion, no bypass (GitHub ruleset). The release relies on this ruleset.
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

## Repo layout

| Path | Holds |
| --- | --- |
| `Jenkinsfile` | The pipeline, for every role |
| `ci/molecule/shared/` | `site.yml` (runs the role), used by both tests |
| `ci/molecule/container/` | Container test scenario, copied into every branch build |
| `ci/molecule/vm/` | VM test: `vm-test.sh` (Terraform, then `ansible-playbook`), Red Hat register and unregister, its Terraform; copied into PR builds |
| `ci/requirements-tools.txt` | Pinned ansible-core 2.16, ansible-lint, yamllint, Molecule (`/opt/ci`) |
| `ci/requirements-checkov.txt` | Pinned Checkov (`/opt/checkov`, own venv: its pins clash with the tools above) |
| `docs/` | Plan, setup guide, onboarding, evidence, troubleshooting |
