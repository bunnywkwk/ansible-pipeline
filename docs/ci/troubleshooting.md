# Role CI troubleshooting

Each entry: the exact error, its cause, the fix, and how to avoid it.

## smee forwards the webhook, Jenkins answers 405

**Error** (smee client, 2026-11-07)

```text
$ smee -u https://smee.io/<channel> -t http://localhost:8080/github-webhook/
POST http://localhost:8080/github-webhook/ - 405
```

**Cause:** smee-client 5.0.0 removes the trailing `/` from the target (`trimTrailingSlash` in its `index.js`); the log still prints the URL as typed. The POST goes to `/github-webhook`, Jenkins redirects (302) to `/github-webhook/`, the client follows the redirect as a GET, and the webhook only accepts POST. Reproduced with curl: POST without the slash gives 302, GET with the slash gives 405.

**Fix:** end the target with a query string, so it no longer ends in `/`; Jenkins ignores the parameter.

```bash
smee -u https://smee.io/<channel> -t 'http://localhost:8080/github-webhook/?smee=1'
```

**Check:** curl POST to `http://localhost:8080/github-webhook/?smee=1` with header `X-GitHub-Event: ping` returns 200. Redeliver the ping from the repo's webhook page; smee prints `- 200`.

**Prevent:** after starting smee, the first forwarded line must end in ` - 200`. Same issue and fix as T-G5 in `~/ansible-cis/docs/troubleshooting.md` (2026-10-12).

## Webhook delivered (200) but no build: "Could not parse PUSH event"

Not hit in this project; found earlier (T-G6 in `~/ansible-cis/docs/troubleshooting.md`). With content type `application/x-www-form-urlencoded`, smee wraps the payload as a string and Jenkins finds no `repository` field (`journalctl -u jenkins` shows the NullPointerException). **Prevent:** with smee, the GitHub webhook always uses content type `application/json`.

## Build green, but GitHub gets no status: 403 "Resource not accessible by personal access token"

**Error** (`role-ci/ansible-role-webserver`, `main` #1, 2026-11-07)

```text
Could not update commit status. Message: {"message":"Resource not accessible by personal access token","documentation_url":"https://docs.github.com/rest/commits/statuses#create-a-commit-status","status":"403"}
```

**Cause:** the fine-grained token in `github-crendentials` (`jenkins-laptop`) listed only `chrome_cis` under Repository access. It could read the public role repo but not write statuses to it.

**Fix:** GitHub → Settings → Developer settings → Fine-grained tokens → `jenkins-laptop` → Edit → Repository access → add the role repos → Save. The token value does not change.

**Prevent:** adding a role repo means adding it to the token too (onboarding checklist). Same as T-G7 in `~/ansible-cis/docs/troubleshooting.md`.

## `molecule --version | head -2` prints a warning instead of the version

**Cause:** with `/opt/ci` activated, ansible-compat prints `UserWarning: Found VIRTUAL_ENV=/opt/ci but we cannot use it for caching as it is not writable.` on stdout before Molecule's output. The venv is root-owned on purpose; ansible-compat caches elsewhere.

**Fix:** filter instead of cutting lines, with colours off (colour codes split `ansible:`): `NO_COLOR=1 molecule --version | grep -E '^molecule|ansible:'` prints `molecule 26.9.0 using python 3.11` and `ansible:2.16.20`.

## Converge warns "Using a mapping for `action` is deprecated"

**Seen** (`molecule test`, converge and idempotence, 2026-11-07)

```text
TASK [Run the role from this checkout]
[DEPRECATION WARNING]: Using a mapping for `action` is deprecated. Use a string value for `action`. This feature will be removed in version 2.23.
```

**Cause:** not the role's code. ansible-core 2.16.20 builds the argument-validation task for `meta/argument_specs.yml` itself, as an `action:` mapping (`ansible/playbook/role/__init__.py`), and the same release deprecates that form (`ansible/parsing/mod_args.py`).

**Fix:** none needed; the validation task runs and passes. It goes away with a newer ansible-core.

## Molecule passes locally because collections are already in `~/.ansible`

**Seen:** the `dependency` step printed `Nothing to do. All requested collections are already installed`: `ansible.posix` 2.2.2 and `containers.podman` 1.21.2 were in `~/.ansible/collections` from earlier projects. The run did not prove that the role's requirements are complete.

**Fix:** test with an empty Ansible home, as a clean CI node would: `ANSIBLE_HOME=$(mktemp -d) molecule test`. Run that way (2026-11-07), both were downloaded into the empty home: `ansible.posix` by the prerun from the role's `requirements.yml`, and `containers.podman` by the `dependency` step itself, because the podman driver declares it (`molecule/dependency/base.py` installs `driver.required_collections`). A scenario `collections.yml` listing `containers.podman` was therefore redundant and was removed; the `dependency` step must stay, or a clean node cannot create the container.

## Checkov crashes while writing its report and still exits 0

**Seen** (local test of the Security stage, 2026-11-07)

```text
$ checkov -d . --framework ansible -o cli -o junitxml --output-file-path console,<a directory>
IsADirectoryError: [Errno 21] Is a directory: '<a directory>'
exit=0
```

**Cause:** with several outputs, `--output-file-path` takes one path per output, and for `junitxml` it must be a file, not a directory. Checkov finished scanning, crashed while writing the report, and still exited 0: in a pipeline, the security gate would pass without anyone noticing.

**Fix:** a file path (`console,reports/checkov.xml`), and the stage also runs `test -s reports/checkov.xml`, so a missing report fails the stage.

## Molecule container name too long for a hostname

**Found before it happened** (Batch 2, 2026-11-07): the podman driver sets the container's hostname to its name (`hostname: item.hostname | default(item.name)` in its `create.yml`), and Linux hostnames are limited to 64 characters. A run id built from `BUILD_TAG` (`jenkins-role-ci-ansible-role-webserver-feature-2fwebserver-role-12`) makes the name about 81 characters.

**Fix:** the pipeline sets `MOLECULE_RUN_ID = "e${EXECUTOR_NUMBER}"`, short and unique among builds running at once on the node.

## Release stage: tag push 403 "Permission … denied to bunnywkwk"

**Error** (`role-ci/ansible-role-webserver`, `main` #4, 2026-11-07, first build with the Release stage)

```text
+ git … push origin refs/tags/v0.1.0
remote: Permission to bunnywkwk/ansible-role-webserver.git denied to bunnywkwk.
fatal: unable to access 'https://github.com/bunnywkwk/ansible-role-webserver.git/': The requested URL returned error: 403
```

**Cause:** GitHub accepted the login (the helper sent `bunnywkwk` and the token) but the token in `github-crendentials` had no write access to the repo's contents. A read-only token can still `ls-remote` a public repo, so the check before the push passed.

**Fix:** token `jenkins-laptop` → Repository permissions → Contents = Read and write → Update; re-run the `main` build. No tag was created on GitHub by the failed build.

**Prevention:** setup step 3 lists Contents read and write from Batch 4 on.

## VM test: Terraform "Cannot find start time for pid"

**Error** (`PR-4` #1, 2026-11-09, first VM test; no VM was created)

```text
Error: failed to connect: internal error: Cannot find start time for pid 143418
  on main.tf line 13, in provider "libvirt"
```

`journalctl -u virtproxyd` showed the same line at the same second.

**Cause:** `qemu:///system` reached libvirt through `virtproxyd`, which could not read the Terraform process started by the Jenkins service. The same URI worked from a login shell. Probably an SELinux denial (`virtproxyd_t` against `unconfined_service_t`); the audit log was not checked.

**Fix:** connect straight to the QEMU daemon: `qemu:///system?socket=/var/run/libvirt/virtqemud-sock` (`ci/molecule/vm/terraform/variables.tf`). `PR-4` #2 passed.

**Prevention:** test libvirt access from a Jenkins build, not from a login shell or `sudo -u jenkins`: those run in a different SELinux context.

## VM test: `terraform init` 504 from github.com

**Error** (`PR-5` #1, 2026-11-09; no VM was created)

```text
Error while installing dmacvicar/libvirt v0.8.3: could not query provider registry for registry.terraform.io/dmacvicar/libvirt:
failed to retrieve authentication checksums for provider: the request failed after 2 attempts, please try again later: 504 Gateway Timeout returned from github.com
```

**Cause:** every new PR build downloaded the plugin again, and GitHub was timing out. The cleanup `terraform init` failed the same way: with a VM running, it could not have been removed.

**Fix:** the plugin lives on the build node (`/opt/ci/terraform-plugins`) and the `Jenkinsfile` sets `TF_CLI_ARGS_init=-plugin-dir=…`. Local test with the network blocked: `TF_PLUGIN_CACHE_DIR` still failed, `-plugin-dir` worked.

**Prevention:** when the plugin version in `main.tf` changes, update the copy on the node (setup step 41b).

## New role job lists another role's branches, all red

**Error** (`role-ci/ansible-role-motd`, 2026-11-10; job made with "Copy from" `ansible-role-webserver`)

```text
+ git clean -ffdx -q
fatal: not a git repository (or any of the parent directories): .git
```

**Cause:** "Copy from" also copies the old job's branches. Each one built once with no code, failed at its first command, and was then disabled. No commit, tag or VM of the old role was touched.

**Fix:** delete the new job and create it fresh.

**Prevention:** never use "Copy from" for a role job (setup guide, "Adding another role repo").

## Container test: `loginctl enable-linger` "Could not activate remote peer"

**Error** (`role-ci/ansible-role-jenkins`, `staging` #4, 2026-11-13)

```text
TASK [bunnywkwk.jenkins : PODMAN | Enable linger for jenkins]
"stderr": "Could not enable linger: Could not activate remote peer."
```

**Cause:** the `ubi9/ubi-init` image masks `systemd-logind.service` in its own build (`systemctl mask ... systemd-logind.service ...`, seen in the image history). `loginctl` asks logind over D-Bus and gets no answer. `privileged: true` alone did not help: the unit is switched off, not blocked.

**Fix:** `ci/molecule/container/prepare.yml` unmasks and starts `systemd-logind`. `staging` #5 passed.

**Prevention:** a task that works on a VM but not in the container: check the image history for masked units (`skopeo inspect --config docker://<image>`).

## Container test: firewalld is not in the UBI repos

**Seen** (2026-11-13, checking the public UBI 9 repo metadata before writing `prepare.yml`): `firewalld`, `audit` and `chrony` are not in UBI 9 baseos or appstream. An unregistered `ubi9-init` cannot install them.

**Fix:** the container registered with Red Hat first. Changed 2026-11-14: the image is Rocky Linux 9 (`quay.io/rockylinux/rockylinux:9-ubi-init`, as in ansible-lockdown); its public repos have every RHEL 9 package, so no registration. `prepare.yml` installs group `@core`, the golden image's minimal install.

**Prevention:** before picking a test image, check its public repos have the packages a real host has.

