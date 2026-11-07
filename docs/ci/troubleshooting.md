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
