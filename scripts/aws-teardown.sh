#!/usr/bin/env bash
# For the organizer, after the workshop: deletes what the attendees created in AWS in Lab 11. It finds the Lambdas by their tag
# purpose=$AWS_TAG_PURPOSE (never by name alone), so it cannot touch anything that is not ours. For each one it deletes the Function URL,
# the function with its permissions, its log group, and the folder of its state in the bucket.
# Guarded: without CONFIRM=yes (or --yes) it only lists what it would delete.
#
#   scripts/aws-teardown.sh [--yes]           PARTICIPANT=<id> limits it to one attendee
#
# It needs credentials that may list tagged resources and delete these Lambdas, log groups and state files: an administrator, not the
# workshop user. They are read from .tools/aws.env (git-ignored). Run it once per cohort, or once at the end of the day.
set -euo pipefail

# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
load_env
require_docker

CONFIRM="${CONFIRM:-no}"
for arg in "$@"; do
  case "$arg" in
    --yes) CONFIRM=yes ;;
    -h | --help)
      sed -n '2,12p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) die "Unknown argument '$arg'" ;;
  esac
done
[[ -n "${AWS_TAG_PURPOSE:-}" ]] || die "AWS_TAG_PURPOSE is empty in workshop.env: it is how this script knows what is ours."
[[ -f "$TOOLS_DIR/aws.env" ]] || die "No $TOOLS_DIR/aws.env with the AWS credentials of the organizer."

# The credentials go to the AWS CLI (in Docker) through the environment, never on the command line
set -a
# shellcheck disable=SC1091
source "$TOOLS_DIR/aws.env"
set +a
export AWS_REGION="${AWS_REGION:-us-east-1}"
aws() { docker run --rm -e AWS_ACCESS_KEY_ID -e AWS_SECRET_ACCESS_KEY -e AWS_SESSION_TOKEN -e AWS_REGION -e AWS_PAGER= amazon/aws-cli "$@"; }

filters=(--tag-filters "Key=purpose,Values=$AWS_TAG_PURPOSE")
[[ -z "${PARTICIPANT:-}" ]] || filters+=("Key=participant,Values=$PARTICIPANT")
# shellcheck disable=SC2016 # the backticks are part of the JMESPath query, not shell
found="$(aws resourcegroupstaggingapi get-resources --resource-type-filters lambda:function "${filters[@]}" \
  --query 'ResourceTagMappingList[].[ResourceARN, Tags[?Key==`participant`]|[0].Value]' --output text)" ||
  die "Could not list the tagged Lambdas. These credentials need tag:GetResources (an administrator has it, the workshop user does not)."
[[ -n "$found" ]] || {
  ok "nothing to delete: no Lambda with the tag purpose=$AWS_TAG_PURPOSE${PARTICIPANT:+ and participant=$PARTICIPANT}"
  exit 0
}

printf 'Lambdas tagged purpose=%s%s:\n' "$AWS_TAG_PURPOSE" "${PARTICIPANT:+ participant=$PARTICIPANT}"
participants=""
while IFS=$'\t' read -r arn participant; do
  printf '  %s   (participant %s)\n' "${arn##*:function:}" "${participant:-?}"
  case " $participants " in *" $participant "*) ;; *) [[ -z "$participant" || "$participant" == None ]] || participants="$participants $participant" ;; esac
done <<<"$found"
printf 'It would also delete the log group of each one, and the state files under s3://%s/ in the folders:%s\n' "$AWS_STATE_BUCKET" "${participants:- (none)}"
if [[ "$CONFIRM" != yes ]]; then
  printf '\nNothing was deleted. To delete: make aws-teardown CONFIRM=yes\n'
  exit 0
fi

while IFS=$'\t' read -r arn _; do
  name="${arn##*:function:}"
  aws lambda delete-function-url-config --function-name "$name" >/dev/null 2>&1 || true
  aws lambda delete-function --function-name "$name" >/dev/null
  aws logs delete-log-group --log-group-name "/aws/lambda/$name" >/dev/null 2>&1 || true
  ok "deleted $name"
done <<<"$found"
for participant in $participants; do
  aws s3 rm "s3://$AWS_STATE_BUCKET/$participant/" --recursive >/dev/null
  ok "deleted the state files of $participant"
done
