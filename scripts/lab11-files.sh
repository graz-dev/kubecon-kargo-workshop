#!/usr/bin/env bash
# Adds to the GitOps repository in Gitea what Lab 11 needs: the Lambda (lambda/) and the Terraform of dev, staging and prod
# (env/<stage>/terraform/). Idempotent: when lambda/app.py is already there it does nothing. It only talks to the local Gitea;
# nothing is created in AWS. Called by `make seed`.
#
#   scripts/lab11-files.sh
set -euo pipefail

# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
load_env
require_tools

if [[ -z "${AWS_TAG_OWNER:-}" || -z "${AWS_TAG_PURPOSE:-}" ]]; then
  warn "AWS_TAG_OWNER or AWS_TAG_PURPOSE is empty in workshop.env: the files of Lab 11 are not added"
  exit 0
fi
cluster_exists || die "Cluster '$CLUSTER_NAME' does not exist. Run: make up"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
GITEA_HOST="$(service_host gitea)"
REMOTE="http://$GITEA_ADMIN_USER:$GITEA_ADMIN_PASSWORD@127.0.0.1:$HTTP_PORT/$GITEA_ORG/$GITEA_REPO.git"
HDR="http.extraHeader=Host: $GITEA_HOST$(port_suffix)"

git -c "$HDR" clone -q "$REMOTE" "$WORK/repo"
changed=0

# The Lambda and the Terraform of dev, staging and prod
if [[ ! -f "$WORK/repo/lambda/app.py" ]]; then
  export AWS_PARTICIPANT AWS_STATE_BUCKET AWS_REGION AWS_EXECUTION_ROLE_ARN AWS_FUNCTION_PREFIX AWS_TAG_OWNER AWS_TAG_PURPOSE INITIAL_VERSION TF_STAGE
  AWS_PARTICIPANT="$(aws_participant)"
  mkdir -p "$WORK/repo/lambda"
  cp "$ROOT_DIR"/seed/lab11/lambda/* "$WORK/repo/lambda/"
  for TF_STAGE in dev staging prod; do
    mkdir -p "$WORK/repo/env/$TF_STAGE/terraform"
    for f in main.tf outputs.tf provider.tf variables.tf env.auto.tfvars; do
      render_template "$ROOT_DIR/seed/lab11/terraform/$f" >"$WORK/repo/env/$TF_STAGE/terraform/$f"
    done
  done
  changed=1
  ok "the Lambda and the Terraform of dev, staging and prod (participant id: $AWS_PARTICIPANT)"
fi

# The key env.LAMBDA_URL must exist in the values file of every stage: yaml-update does not create keys
for stage in $STAGES; do
  values="$WORK/repo/env/$stage/k8s/values.yaml"
  if [[ -f "$values" ]] && ! grep -q 'LAMBDA_URL' "$values"; then
    printf '# Lab 11 writes the URL of the Lambda here\nenv:\n  LAMBDA_URL: ""\n' >>"$values"
    changed=1
    ok "env.LAMBDA_URL added to the values file of $stage"
  fi
done

if [[ "$changed" == 0 ]]; then
  ok "the repository already has the files of Lab 11"
  exit 0
fi
git -C "$WORK/repo" add -A
git -C "$WORK/repo" -c user.name="Kargo workshop" -c user.email="workshop@workshop.local" commit -q -m "Prepare the repository for Lab 11"
git -C "$WORK/repo" -c "$HDR" push -q origin "$GITEA_BRANCH"
ok "pushed"
