// Role CI: the central pipeline. Role repos hold no pipeline code; Jenkins loads this file for every role repo
// (Remote Jenkinsfile Provider plugin) and runs it on the role's checked-out code.
// No repo is named here: declarative pipelines run `checkout scm` before the first stage ("Declarative: Checkout SCM"),
// and Jenkins fills `scm` from the job: the role repo, branch and commit being built. That is what makes this file reusable.
//
// What runs when:
//   Push to a branch with no PR   Gates + container test
//   PR opened or updated          Gates + VM test
//   Merge to main                 Release only: the PR already tested this exact code
// Gates, cheapest first: Secrets → Version → YAML lint → Ansible lint → Security.
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
    stage('Gates') {
      when { not { branch 'main' } }
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

        // Every build checks VERSION, so a bad one fails its pull request, not main after the merge.
        stage('Version') {
          steps {
            sh '''
              V=$(cat VERSION)
              echo "$V" | grep -qxE '[0-9]+[.][0-9]+[.][0-9]+' || { echo "VERSION must be X.Y.Z, got '$V'"; exit 1; }
              echo "VERSION $V"
            '''
          }
        }

        stage('YAML lint') {
          steps {
            sh '''
              . /opt/ci/bin/activate
              yamllint --version
              # yamllint prints nothing when clean; say so, so the log shows the check ran.
              # Two lines, not "&&": sh -e does not stop on a failure inside an && list.
              yamllint -f parsable .
              echo "yamllint: no problems found"
            '''
          }
        }

        // The test scenarios come from this repo, so a role needs only its code, and a role branch cannot weaken them.
        // After YAML lint (they are ours to lint), before Ansible lint (which must see converge.yml to read the role's tasks).
        stage('Test setup') {
          steps {
            dir('.pipeline') {
              git url: 'https://github.com/bunnywkwk/ansible-pipeline.git', branch: 'main', changelog: false, poll: false
            }
            sh '''
              . /opt/ci/bin/activate
              rm -rf molecule
              cp -r .pipeline/ci/molecule molecule
              rm -rf .pipeline
              [ -n "$CHANGE_ID" ] || rm -rf molecule/vm     # the VM scenario is for PR builds only
              ROLE=$(python -c "import yaml; g = yaml.safe_load(open('meta/main.yml'))['galaxy_info']; print(g['namespace'] + '.' + g['role_name'])")
              sed -i "s/ROLE_FQCN/$ROLE/" molecule/default/converge.yml
              mkdir molecule/default/vars       # a vars/ folder, so ansible-lint does not read it as a playbook
              if [ -f ci-container-vars.yml ]; then cp ci-container-vars.yml molecule/default/vars/container.yml
              else printf -- '---\n{}\n' > molecule/default/vars/container.yml; fi
              echo "Testing role $ROLE"
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
      }
    }

    stage('Molecule') {
      when { allOf { not { branch 'main' }; not { changeRequest() } } }
      steps {
        sh '''
          . /opt/ci/bin/activate
          # Jenkins runs as a system service: rootless podman needs the user's runtime dir and bus.
          export XDG_RUNTIME_DIR=/run/user/$(id -u)
          export DBUS_SESSION_BUS_ADDRESS=unix:path=$XDG_RUNTIME_DIR/bus
          molecule --version | grep -E '^molecule|ansible:'
          molecule test -s default
        '''
      }
    }

    // PR only: the role on a real RHEL 9 VM, from the scenario in ci/molecule/vm.
    stage('VM test') {
      when { changeRequest() }
      steps {
        // The VM registers with Red Hat through cloud-init, so the role's dnf tasks have packages.
        withCredentials([string(credentialsId: 'rhsm-org', variable: 'TF_VAR_rhsm_org'),
                         string(credentialsId: 'rhsm-activation-key', variable: 'TF_VAR_rhsm_activation_key')]) {
          sh '''
            . /opt/ci/bin/activate
            terraform version | head -1
            molecule test -s vm
          '''
        }
      }
    }

    // main only: tag the commit a PR tested, v<VERSION>. An existing tag is never moved: skip instead.
    stage('Release') {
      when { branch 'main' }
      steps {
        withCredentials([usernamePassword(credentialsId: 'github-crendentials',
                                          usernameVariable: 'GIT_USER', passwordVariable: 'GIT_TOKEN')]) {
          sh '''
            # Only a PR merge commit (two parents) was tested; a new repo's first commit is not.
            if ! git rev-parse -q --verify 'HEAD^2' >/dev/null; then echo "Not a pull request merge: no release."; exit 0; fi
            V=$(cat VERSION)        # format checked by the PR's Version stage
            # Token read from the environment by git, never put in a URL or the log
            H='!f() { echo "username=$GIT_USER"; echo "password=$GIT_TOKEN"; }; f'
            if git -c credential.helper= -c credential.helper="$H" ls-remote --exit-code --tags origin "refs/tags/v$V" >/dev/null; then
              echo "Tag v$V already exists: release skipped. Bump VERSION in a pull request to release."
            else
              # -f: local tag only, left over if an earlier push failed; the push itself never forces
              git -c user.name=jenkins -c user.email=jenkins@localhost tag -fa "v$V" -m "Release v$V"
              git -c credential.helper= -c credential.helper="$H" push origin "refs/tags/v$V"
              echo "Released v$V at $(git rev-parse --short HEAD)"
            fi
          '''
        }
      }
    }
  }

  post {
    always {
      // molecule test removes its container or VM; this covers an abort or a timeout mid-run.
      sh '''
        . /opt/ci/bin/activate
        export XDG_RUNTIME_DIR=/run/user/$(id -u)
        export DBUS_SESSION_BUS_ADDRESS=unix:path=$XDG_RUNTIME_DIR/bus
        if [ "$BRANCH_NAME" != main ] && [ -d molecule ]; then molecule destroy --all || true; fi
      '''
      archiveArtifacts artifacts: 'reports/**', allowEmptyArchive: true
    }
  }
}
