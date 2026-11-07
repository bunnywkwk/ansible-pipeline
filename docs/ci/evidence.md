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
