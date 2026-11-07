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
