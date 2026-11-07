// Role CI: the central pipeline. Role repos hold no pipeline code; Jenkins loads this file for every role repo
// (Remote Jenkinsfile Provider plugin) and runs it on the role's checked-out code.
// No repo is named here: declarative pipelines run `checkout scm` before the first stage ("Declarative: Checkout SCM"),
// and Jenkins fills `scm` from the job: the role repo, branch and commit being built. That is what makes this file reusable.
// Batch 0 spike: proves the remote Jenkinsfile, the pinned tools and rootless systemd containers.
// Batch 2 replaces the stage with the gates.
pipeline {
  agent { label 'ansible' }

  options {
    timestamps()
    timeout(time: 15, unit: 'MINUTES')
  }

  environment {
    // Container names allow only [a-z0-9-]; branch names can hold '/' or '%'.
    CTR = "${env.BUILD_TAG.toLowerCase().replaceAll('[^a-z0-9-]', '-')}"
  }

  stages {
    stage('Build node check') {
      steps {
        sh '''
          echo "== Code under test"
          git remote get-url origin
          git log -1 --oneline
          if [ -e Jenkinsfile ]; then echo "Jenkinsfile found in this repo"; else echo "No Jenkinsfile in this repo: the pipeline came from ansible-pipeline"; fi

          echo "== Tools"
          # Activate, not a full path: otherwise Molecule picks up Fedora's /usr/bin/ansible (2.20) first.
          . /opt/ci/bin/activate
          ansible --version | head -1
          ansible-lint --version | head -1
          yamllint --version
          # grep, not head: ansible-compat prints a cache warning on stdout first (/opt/ci is read-only on purpose).
          # NO_COLOR: colour codes split "ansible:" and the grep misses it.
          NO_COLOR=1 molecule --version | grep -E '^molecule|ansible:'
          /opt/checkov/bin/checkov --version
          gitleaks version
          podman --version

          echo "== Rootless systemd container as $(id -un)"
          # Jenkins runs as a system service, so systemd does not set these; podman needs them for the user's cgroups.
          export XDG_RUNTIME_DIR=/run/user/$(id -u)
          export DBUS_SESSION_BUS_ADDRESS=unix:path=$XDG_RUNTIME_DIR/bus
          podman run -d --name "$CTR" registry.access.redhat.com/ubi9/ubi-init
          podman exec "$CTR" cat /etc/redhat-release
          state=$(podman exec "$CTR" systemctl is-system-running --wait || true)
          echo "systemd in container: $state"
          case "$state" in running|degraded) ;; *) exit 1 ;; esac
        '''
      }
    }
  }

  post {
    always {
      sh '''
        export XDG_RUNTIME_DIR=/run/user/$(id -u)
        podman rm -f "$CTR" || true
      '''
    }
  }
}
