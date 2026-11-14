#!/usr/bin/env bash
# PR test on a real RHEL 9 VM, like ansible-lockdown's pipeline: Terraform makes the VM,
# ansible-playbook runs the role's play on it. No Molecule.
# Run from the build workspace (the role checkout); Test setup put this folder at molecule/vm.
#   vm-test.sh test      remove leftovers, create, register, run the play twice, the second must change nothing
#   vm-test.sh destroy   unregister and remove the VM; safe when there is none (Jenkins post)
set -euo pipefail

DIR=molecule/vm
SHARED=molecule/shared
TF=(terraform "-chdir=$DIR/terraform")
NAME="role-vm-${MOLECULE_RUN_ID:-local}"
KEY="$PWD/$DIR/id_ed25519"
INV="$DIR/hosts.ini"

destroy() {
  # Best effort: a VM that never registered, or no longer answers, must not stop its removal.
  [ ! -f "$INV" ] || ansible-playbook -i "$INV" "$DIR/unregister.yml" || true
  "${TF[@]}" init -input=false -no-color >/dev/null
  "${TF[@]}" destroy -input=false -auto-approve -no-color "-var=run_id=$NAME"
  rm -f "$INV"
}

test_vm() {
  destroy

  # The role under its full name, and only the collections it lists: like a clean control node.
  work=$(mktemp -d)
  trap 'rm -rf "$work"' EXIT
  role=$(python -c "import yaml; g = yaml.safe_load(open('meta/main.yml'))['galaxy_info']; print(g['namespace'] + '.' + g['role_name'])")
  mkdir "$work/roles" && ln -s "$PWD" "$work/roles/$role"
  export ANSIBLE_ROLES_PATH="$work/roles" ANSIBLE_COLLECTIONS_PATH="$work/collections"
  [ ! -f requirements.yml ] || ansible-galaxy collection install -r requirements.yml -p "$work/collections"

  [ -f "$KEY" ] || ssh-keygen -q -t ed25519 -N '' -C ci -f "$KEY"
  "${TF[@]}" init -input=false -no-color
  "${TF[@]}" apply -input=false -auto-approve -no-color "-var=run_id=$NAME" "-var=ssh_public_key=$(cat "$KEY.pub")"
  ip=$("${TF[@]}" output -raw ip)

  # Group vm: the role's ci/group_vars/vm.yml applies (next to site.yml, loaded by Ansible).
  printf '[vm]\n%s ansible_host=%s ansible_user=root ansible_ssh_private_key_file=%s ansible_ssh_common_args="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"\n' \
    "$NAME" "$ip" "$KEY" > "$INV"

  # terraform apply returns once the VM has an IP: wait for SSH, and for cloud-init (it adds the root key).
  ansible all -i "$INV" -m ansible.builtin.wait_for_connection -a timeout=600
  ansible all -i "$INV" -m ansible.builtin.command -a 'cloud-init status --wait'
  ansible-playbook -i "$INV" "$DIR/register.yml"

  echo "== Run 1: the role's play"
  ansible-playbook -i "$INV" "$SHARED/site.yml"

  echo "== Run 2: idempotence, nothing may change"
  ansible-playbook -i "$INV" "$SHARED/site.yml" | tee "$DIR/run2.log"
  if grep -E '^\S+ +: ok=' "$DIR/run2.log" | grep -qv 'changed=0 '; then
    echo "Idempotence failed: the second run changed something (tasks marked changed above)"
    exit 1
  fi
  echo "Idempotence: changed=0"
}

case "${1:-}" in
  test) test_vm ;;
  destroy) destroy ;;
  *) echo "usage: $0 test|destroy" >&2; exit 2 ;;
esac
