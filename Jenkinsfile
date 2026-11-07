// Role CI: the central pipeline. Role repos hold no pipeline code; Jenkins loads this file for every role repo
// (Remote Jenkinsfile Provider plugin) and runs it on the role's checked-out code.
// No repo is named here: declarative pipelines run `checkout scm` before the first stage ("Declarative: Checkout SCM"),
// and Jenkins fills `scm` from the job: the role repo, branch and commit being built. That is what makes this file reusable.
//
// Gates, cheapest first: Secrets → YAML lint → Ansible lint → Security → Molecule.
// Tool configs: a role's own .yamllint, .ansible-lint, .gitleaks.toml or .checkov.yml is picked up from its root;
// without one, each tool's built-in defaults apply. Collections come from the role's requirements.yml (Molecule).
pipeline {
  agent { label 'ansible' }

  options {
    timestamps()
    timeout(time: 30, unit: 'MINUTES')
    disableConcurrentBuilds()
    buildDiscarder(logRotator(numToKeepStr: '30'))
  }

  environment {
    // Short and unique among builds running at once on this node. Molecule's podman driver uses the container
    // name as its hostname (64-character limit), so BUILD_TAG would be too long.
    MOLECULE_RUN_ID = "e${env.EXECUTOR_NUMBER}"
    // Plain console log, no colour codes
    ANSIBLE_FORCE_COLOR = '0'
    PY_COLORS = '0'
    NO_COLOR = '1'
  }

  stages {
    // Seconds to run, and a leak must never hide behind a lint error.
    // --log-opts=HEAD: this branch's history only; gitleaks defaults to every ref in the checkout.
    stage('Secrets') {
      steps {
        sh '''
          git clean -ffdx -q          # workspace is reused: drop reports and caches from earlier builds
          mkdir -p reports
          gitleaks version
          gitleaks git -v --redact --no-banner --log-opts=HEAD --report-format sarif --report-path reports/gitleaks.sarif .
        '''
      }
    }

    stage('YAML lint') {
      steps {
        sh '''
          . /opt/ci/bin/activate
          yamllint --version
          yamllint -f parsable .
        '''
      }
    }

    // Also runs the unskippable syntax-check on every playbook, including Molecule's.
    stage('Ansible lint') {
      steps {
        sh '''
          . /opt/ci/bin/activate
          ansible-lint --version | head -1
          ansible-lint --profile production --sarif-file reports/ansible-lint.sarif
        '''
      }
    }

    // test -s: Checkov can crash while writing its report and still exit 0; no report means the gate did not run.
    stage('Security') {
      steps {
        sh '''
          /opt/checkov/bin/checkov --version
          /opt/checkov/bin/checkov -d . --framework ansible --skip-download --compact --quiet \
            -o cli -o junitxml --output-file-path console,reports/checkov.xml
          test -s reports/checkov.xml
        '''
      }
    }

    stage('Molecule') {
      steps {
        sh '''
          . /opt/ci/bin/activate
          # Jenkins runs as a system service: rootless podman needs the user's runtime dir and bus.
          export XDG_RUNTIME_DIR=/run/user/$(id -u)
          export DBUS_SESSION_BUS_ADDRESS=unix:path=$XDG_RUNTIME_DIR/bus
          molecule --version | grep -E '^molecule|ansible:'
          molecule test --all
        '''
      }
    }
  }

  post {
    always {
      // molecule test removes its containers; this covers an abort or a timeout mid-run.
      sh '''
        . /opt/ci/bin/activate
        export XDG_RUNTIME_DIR=/run/user/$(id -u)
        export DBUS_SESSION_BUS_ADDRESS=unix:path=$XDG_RUNTIME_DIR/bus
        if [ -d molecule ]; then molecule destroy --all || true; fi
      '''
      archiveArtifacts artifacts: 'reports/**', allowEmptyArchive: true
    }
  }
}
