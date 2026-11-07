# Role CI evidence

Verified results per batch: what was run and what it printed. Steps are in [setup-guide.md](setup-guide.md).

## Batch 0 — CI foundation (2026-11-07)

**Build node:** Jenkins 2.580.2, Fedora 44, built-in node labelled `ansible`, user `jenkins` (uid 962).

```text
$ grep jenkins /etc/subuid /etc/subgid; loginctl show-user jenkins -p Linger; ls -ld /run/user/962
/etc/subuid:jenkins:786432:65536
/etc/subgid:jenkins:786432:65536
Linger=yes
drwx------. 4 jenkins jenkins 140 Nov  7 18:18 /run/user/962
```

**smee service**

```text
$ systemctl --user is-active smee-jenkins; systemctl --user is-enabled smee-jenkins
active
enabled
$ journalctl --user -u smee-jenkins -n 4 --no-pager -o cat
Started smee-jenkins.service - smee relay: GitHub webhooks to local Jenkins.
Connected to https://smee.io/<channel>
Forwarding https://smee.io/<channel> to http://localhost:8080/github-webhook/?smee=1
POST http://localhost:8080/github-webhook/?smee=1 - 200
```

**Build `role-ci/ansible-role-webserver` `main` #2** (started by the webhook), console excerpts:

```text
Push event to branch main
Checking out git https://github.com/bunnywkwk/ansible-pipeline.git into /var/lib/jenkins/workspace/e-ci_ansible-role-webserver_main@script/… to read Jenkinsfile
Checking out Revision d98ce214ce74ef75d8a7a613403f4cf9879e8a44 (origin/main)
[Pipeline] { (Declarative: Checkout SCM)
Cloning repository https://github.com/bunnywkwk/ansible-role-webserver.git
Checking out Revision 62d9dd21dd25f624e8b15de7413e1492bd0bce53 (main)
19:43:19  https://github.com/bunnywkwk/ansible-role-webserver.git
19:43:19  62d9dd2 Test webhook trigger
19:43:19  No Jenkinsfile in this repo: the pipeline came from ansible-pipeline
19:43:19  ansible [core 2.16.20]
19:43:20  ansible-lint 26.11.0 using ansible-core:2.16.20 ansible-compat:26.11.0 ruamel-yaml:0.19.1
19:43:20  yamllint 1.38.0
19:43:20  molecule 26.9.0 using python 3.11
19:43:20      ansible:2.16.20
19:43:22  3.4.3
19:43:22  8.30.1
19:43:22  podman version 5.8.9
19:43:22  Red Hat Enterprise Linux release 9.8 (Plow)
19:43:23  systemd in container: running
19:43:23  + podman rm -f jenkins-role-ci-ansible-role-webserver-main-2
Finished: SUCCESS
```

| Done-when check | Result |
| --- | --- |
| Role repo without a Jenkinsfile builds by itself from the central one | Passed: #1 on job creation, #2 within seconds of a push (webhook) |
| Tool versions match `ci/requirements-*.txt` | Passed (above); checkov 3.4.3, gitleaks 8.30.1 |
| `ubi9-init` systemd `running` as `jenkins`, rootless | Passed (above); container removed in `post` |
| Branch without `meta/main.yml` not built | Passed: branch `no-marker` pushed, no branch job created (observed by the user in Jenkins; scan log not captured); branch deleted |
| Jenkins status on GitHub | Passed after the token fix (see troubleshooting): `62d9dd2` has status `continuous-integration/jenkins/branch` = success, "This commit looks good" |

**Known:** `jenkins` is also in the `docker` group (Docker CE active), used by older jobs. Role CI does not use Docker. Membership in that group is equivalent to root on the workstation.

## Batch 1 — Template role (2026-11-07)

Role `ansible-role-webserver`, run by hand on the workstation with `/opt/ci` activated and an **empty Ansible home** (`ANSIBLE_HOME=$(mktemp -d) molecule test`), so nothing came from earlier installs.

```text
INFO     default ➜ discovery: scenario test matrix: dependency, destroy, create, converge, idempotence, verify, destroy
WARNING  default ➜ dependency: Missing roles requirements file: requirements.yml
WARNING  default ➜ dependency: Missing collections requirements file: collections.yml
converge     webserver-ubi9-local : ok=6    changed=5    unreachable=0    failed=0    skipped=1
idempotence  webserver-ubi9-local : ok=5    changed=0    unreachable=0    failed=0
verify       webserver-ubi9-local : ok=4    changed=0    unreachable=0    failed=0
default ➜ destroy: Executed: Successful
```

The empty home afterwards held `ansible.posix-2.2.2` (prerun, from the role's `requirements.yml`) and `containers.podman-1.21.2` (`dependency` step, declared by the podman driver). The two "Missing" warnings are expected: the scenario has no test-only requirements.

Static checks on the final files:

```text
yamllint: OK
ansible-lint --profile production: Passed: 0 failure(s), 0 warning(s) in 11 files processed of 14 encountered.
checkov -d . --framework ansible: Passed checks: 4, Failed checks: 0, Skipped checks: 1   (CKV2_ANSIBLE_1, verify.yml http://localhost request, reason inline)
gitleaks dir: no leaks found
```

| Done-when check | Result |
| --- | --- |
| `molecule test` passes with `/opt/ci`, idempotence 0 changed | Passed (above), on an empty Ansible home |
| yamllint, ansible-lint `production`, Checkov clean | Passed; one Checkov skip with a written reason |

**Decisions**

- Own server block and page: the package owns `index.html`, and nginx must listen on `webserver_port`.
- `verify.yml` uses `uri` with one Checkov skip, written inside the task.
- No `syntax` step (ansible-lint covers it); no scenario `collections.yml` (the podman driver declares its own); `dependency` stays (it installs that collection on a clean node).

## Batch 2 — Central pipeline (2026-11-07)

Build `feature/webserver-role` (Build Now), first run with the gates:

```text
Secrets       3 commits scanned. no leaks found
YAML lint     (clean; the stage now prints "yamllint: no problems found")
Ansible lint  Passed: 0 failure(s), 0 warning(s) in 11 files processed of 15 encountered. Profile 'production' was required, and it passed.
Security      Passed checks: 4, Failed checks: 0, Skipped checks: 1   + test -s reports/checkov.xml
Molecule      converge changed=5, idempotence changed=0, verify failed=0 (container webserver-ubi9-e0)
              dependency 38 s: first download of containers.podman as jenkins
post          molecule destroy --all; reports archived
GitHub has been notified of this commit's build result
Finished: SUCCESS
```

Pull request #1 `feature/webserver-role → main` (open, not merged), commit `bf13ae8` on GitHub:

```text
continuous-integration/jenkins/branch   | success
continuous-integration/jenkins/pr-head  | success
```

| Done-when check | Result |
| --- | --- |
| Branch build runs all five stages, green | Passed |
| PR build runs all five stages, green; PR shows the check | Passed: `PR-1` built by itself; check `pr-head` |
| Reports archived | Passed: `reports/gitleaks.sarif`, `ansible-lint.sarif`, `checkov.xml` |

**Note:** the job builds the PR's own commit (`pr-head`), not the PR merged with `main` (`pr-merge`). Batch 4 decides which check the merge gate requires.

## Batch 3 — Gate drills (2026-11-07)

Each drill: one bad commit on branch `drill/NN-name` (from `feature/webserver-role`), built by Jenkins by itself. Predicted stage, then what really happened.

| # | Break | Predicted | Result | Error seen |
| --- | --- | --- | --- | --- |
| 01 | Indent `webserver_message` in `defaults/main.yml` | YAML lint red | As predicted: Secrets passed, YAML lint failed, the other 3 stages skipped; `Finished: FAILURE`, GitHub status `error` | `defaults/main.yml:8:3: [error] syntax error: expected <block end>, but found '<block mapping start>' (syntax)` |
| 02 | `ansible.builtin.template` → `templat` in `tasks/main.yml` | Ansible lint red | **Gap:** Ansible lint passed (only `WARNING Invalid value (None)for resolved_fqcn attribute of ansible.builtin.templat module`), Security passed; Molecule converge failed, `Finished: FAILURE`. Cause: syntax-check only reads playbooks, and `converge.yml` loaded the role at run time (`include_role` with a lookup). Fix (`a72181f`): `import_role: name: bunnywkwk.webserver`. Re-run #2 on top of it: Ansible lint red at `tasks/main.yml:9:3` `syntax-check[unknown-module]`, Security and Molecule skipped | `ERROR! couldn't resolve module/action 'ansible.builtin.templat'. This often indicates a misspelling, missing collection, or incorrect module path.` |
| 03 | `dnf` task replaced by `shell: yum install -y nginx` | Ansible lint red | As predicted: Ansible lint failed with 3 rules (all profile `basic`), Security and Molecule skipped, `Finished: FAILURE` | `command-instead-of-module: yum used in place of yum module`, `command-instead-of-shell: Use shell only when shell functionality is required.`, `no-changed-when: Commands should not change things if nothing needs doing.` (all `tasks/main.yml:2`) |
| 04 | 4a: throwaway ed25519 private key added to `defaults/main.yml` (`807e901`) | Secrets red, value redacted | 4a as predicted: GitHub accepted the push (no push protection block); Secrets failed, the other 4 stages skipped, `Finished: FAILURE`. 4b as predicted: revert `34a6dc0` (files equal to `feature/webserver-role` again) still red, same finding from `807e901`, `6 commits scanned`. 4c as predicted: `reset --hard` to `a72181f` + force-push, build #3 green in all 5 stages (`4 commits scanned`, `no leaks found`) | `RuleID: private-key`, `Secret: REDACTED`, `File: defaults/main.yml`, `Line: 15`, `5 commits scanned`, `leaks found: 1` |
| 05 | `get_url` task with `validate_certs: false` added to `tasks/main.yml` | Security red | As predicted: Secrets, YAML lint and Ansible lint passed (ansible-lint does not check this), Security failed, Molecule skipped, `Finished: FAILURE` | `Check: CKV_ANSIBLE_2: "Ensure that certificate validation isn't disabled with get_url"`, `FAILED for resource: tasks.ansible.builtin.get_url.Download the site logo`, `File: /tasks/main.yml:41-48` |
| 06 | `webserver_message` changed to "Hello from the web", `verify.yml` not updated | Molecule verify red | As predicted: the first 4 gates passed; Molecule converge `changed=5`, idempotence `changed=0`, verify `failed=1`; Molecule destroyed the container itself ("Cleaning up"), then `post` ran `molecule destroy --all`; `Finished: FAILURE` | `"assertion": "expected_message in page.content"`, `"msg": "Page does not contain 'Hello from the lab'"`, `[default > verify] Executed: Failed` |
| 07 | `changed_when: true` added to the `Install nginx` task | Molecule idempotence red | As predicted: the first 4 gates passed (no linter flags it); converge `changed=5`, idempotence `changed=1`, verify not run; Molecule cleaned up, `Finished: FAILURE` | `CRITICAL Idempotence test failed because of the following tasks:`, `*  => bunnywkwk.webserver : Install nginx` |
| 08 | Role branch adds its own `Jenkinsfile` (one stage `Skip CI`, `echo 'all checks skipped'`) | Ignored, central pipeline runs | As predicted: the pipeline was read from `ansible-pipeline` (`638fac2`), the role commit `e5bb6c6` was checked out as code only; all 5 gates ran and passed, no `Skip CI` stage, `Finished: SUCCESS` | `Checking out git https://github.com/bunnywkwk/ansible-pipeline.git into …@script/… to read Jenkinsfile`; ansible-lint `16 encountered` (was 15: the role's Jenkinsfile is just a file) |

**Notes**

- Fix `a72181f` built green as `PR-1` #2 (converge `changed=5`, idempotence `changed=0`, verify `failed=0`), so Molecule resolves `bunnywkwk.webserver` too.
- A push to a branch with an open PR builds `PR-1` only: branch discovery is "Exclude branches that are also filed as PRs", so the `feature/webserver-role` job is no longer buildable. Such commits get only the `pr-head` status, never `branch`; Batch 4 must require `pr-head` (or `pr-merge`), not `branch`.
- Known limit: `command-instead-of-module` lists `yum` but not `dnf`; `command: dnf install -y nginx` with `changed_when: false` passed a local ansible-lint run. Not drilled on Jenkins.

| Done-when check | Result |
| --- | --- |
| Drills 1–8 have real results | Passed (table above); drill 9 dropped at your request |
| Every gap fixed and proven by re-pushing the same commit | Passed: one gap (drill 02), fixed in `a72181f`, re-run red at Ansible lint |
| Drill branches | Kept on GitHub as evidence: `drill/01-yaml-indent` … `drill/08-own-jenkinsfile` |
