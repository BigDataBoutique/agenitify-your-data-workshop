#!/usr/bin/env bash
#
# provision.sh — pure-AWS-CLI equivalent of the Terraform in ./terraform.
#
# For anyone who would rather not use Terraform: this script creates exactly the
# same assets the Rekognition agent needs in *your own* AWS account, and is
# idempotent so it is safe to re-run:
#   * an S3 bucket for images (AES256 encryption + full public-access block)
#   * a bucket policy granting the Rekognition access role read access
#   * an IAM role that the workshop runtime account is trusted to assume
#   * an inline policy on that role for rekognition:DetectText + S3 read
#
# Configure it by editing the CONFIGURATION block below (or by passing the
# values via the environment), and honour an AWS profile — so `./provision.sh`
# mirrors `terraform apply` without needing Terraform or a tfvars file.
#
# Usage:
#   ./provision.sh [--profile <aws_profile>] [--destroy]
#
#   --profile   AWS CLI profile to use (else uses AWS_PROFILE / default creds)
#   --destroy   tear down everything this script created
#
# Any variable can also be overridden via the environment, e.g.:
#   bucket_name=my-bucket aws_region=us-east-1 ./provision.sh
#
set -euo pipefail

# ═════════════════════════════════════════════════════════════════════════════
# CONFIGURATION — edit these to match your environment
# (the same variables as terraform/variables.tf; env vars override them)
# ═════════════════════════════════════════════════════════════════════════════

# REQUIRED — S3 bucket to create under *your own* AWS account.
bucket_name="${bucket_name:-}"

# REQUIRED — AWS account ID of the workshop runtime (trusted to assume the role).
runtime_account_id="${runtime_account_id:-}"

# Region for the S3 bucket and Rekognition (same region as the agent).
aws_region="${aws_region:-us-east-1}"

# Name of the role in the runtime account that will assume the Rekognition role.
runtime_role_name="${runtime_role_name:-AgentCoreRuntimeRole}"

# Name of the IAM role created in your account for Rekognition + S3 access.
rekognition_role_name="${rekognition_role_name:-RekognitionAccessRole}"

# ═════════════════════════════════════════════════════════════════════════════

PROFILE=""
DESTROY=0

# ─── Args ────────────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile)   PROFILE="$2"; shift 2 ;;
    --destroy)   DESTROY=1; shift ;;
    -h|--help)   grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

# ─── Logging helpers ─────────────────────────────────────────────────────────
if [[ -t 1 ]]; then C_G=$'\033[32m'; C_Y=$'\033[33m'; C_R=$'\033[31m'; C_B=$'\033[1m'; C_0=$'\033[0m'
else C_G=""; C_Y=""; C_R=""; C_B=""; C_0=""; fi
info()  { echo "${C_B}▸${C_0} $*"; }
ok()    { echo "  ${C_G}✓${C_0} $*"; }
warn()  { echo "  ${C_Y}!${C_0} $*"; }
die()   { echo "${C_R}✗ $*${C_0}" >&2; exit 1; }

# ─── AWS CLI wrapper (injects --profile when set) ────────────────────────────
aws_() {
  if [[ -n "$PROFILE" ]]; then aws --profile "$PROFILE" "$@"; else aws "$@"; fi
}

# ─── Validate ────────────────────────────────────────────────────────────────
[[ -n "$bucket_name" ]]        || die "bucket_name is required (edit the CONFIGURATION block at the top of this script, or set it in the environment)"
[[ -n "$runtime_account_id" ]] || die "runtime_account_id is required (edit the CONFIGURATION block at the top of this script, or set it in the environment)"

CALLER_ACCOUNT="$(aws_ sts get-caller-identity --query Account --output text)" \
  || die "Unable to authenticate with AWS (check --profile / credentials)"
REKOGNITION_ROLE_ARN="arn:aws:iam::${CALLER_ACCOUNT}:role/${rekognition_role_name}"
BUCKET_ARN="arn:aws:s3:::${bucket_name}"

echo
info "Configuration"
echo "    profile              : ${PROFILE:-<default credentials>}"
echo "    target account       : ${CALLER_ACCOUNT}"
echo "    aws_region           : ${aws_region}"
echo "    bucket_name          : ${bucket_name}"
echo "    runtime_account_id   : ${runtime_account_id}"
echo "    runtime_role_name    : ${runtime_role_name}"
echo "    rekognition_role_name: ${rekognition_role_name}"
echo

# ─── Policy documents (mirror main.tf) ───────────────────────────────────────
trust_policy() {
  cat <<JSON
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "sts:AssumeRole",
      "Principal": {
        "AWS": "arn:aws:iam::${runtime_account_id}:role/${runtime_role_name}"
      }
    }
  ]
}
JSON
}

role_inline_policy() {
  cat <<JSON
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowDetectText",
      "Effect": "Allow",
      "Action": ["rekognition:DetectText"],
      "Resource": "*"
    },
    {
      "Sid": "AllowS3Access",
      "Effect": "Allow",
      "Action": ["s3:ListBucket", "s3:GetObject"],
      "Resource": ["${BUCKET_ARN}", "${BUCKET_ARN}/*"]
    }
  ]
}
JSON
}

bucket_policy() {
  cat <<JSON
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowRekognitionRoleListBucket",
      "Effect": "Allow",
      "Principal": { "AWS": "${REKOGNITION_ROLE_ARN}" },
      "Action": "s3:ListBucket",
      "Resource": "${BUCKET_ARN}"
    },
    {
      "Sid": "AllowRekognitionRoleGetObject",
      "Effect": "Allow",
      "Principal": { "AWS": "${REKOGNITION_ROLE_ARN}" },
      "Action": "s3:GetObject",
      "Resource": "${BUCKET_ARN}/*"
    }
  ]
}
JSON
}

# ═════════════════════════════════════════════════════════════════════════════
# DESTROY
# ═════════════════════════════════════════════════════════════════════════════
if [[ "$DESTROY" -eq 1 ]]; then
  info "Destroying resources"

  if aws_ iam get-role --role-name "$rekognition_role_name" >/dev/null 2>&1; then
    aws_ iam delete-role-policy --role-name "$rekognition_role_name" \
      --policy-name "rekognition-and-s3-access" >/dev/null 2>&1 && ok "deleted inline role policy" || true
    aws_ iam delete-role --role-name "$rekognition_role_name" >/dev/null 2>&1 \
      && ok "deleted role ${rekognition_role_name}" || warn "role not deleted (may have other attachments)"
  else
    warn "role ${rekognition_role_name} does not exist"
  fi

  if aws_ s3api head-bucket --bucket "$bucket_name" >/dev/null 2>&1; then
    aws_ s3api delete-bucket-policy --bucket "$bucket_name" >/dev/null 2>&1 && ok "deleted bucket policy" || true
    # Empty the bucket before deletion.
    aws_ s3 rm "s3://${bucket_name}" --recursive >/dev/null 2>&1 || true
    aws_ s3api delete-bucket --bucket "$bucket_name" >/dev/null 2>&1 \
      && ok "deleted bucket ${bucket_name}" || warn "bucket not deleted (not empty?)"
  else
    warn "bucket ${bucket_name} does not exist"
  fi

  info "Destroy complete"
  exit 0
fi

# ═════════════════════════════════════════════════════════════════════════════
# APPLY
# ═════════════════════════════════════════════════════════════════════════════

# ─── S3 bucket ───────────────────────────────────────────────────────────────
# Idempotent: skip creation if we already own the bucket; fail clearly if the
# (globally-unique) name is owned by someone else.
info "S3 bucket: ${bucket_name}"
if aws_ s3api head-bucket --bucket "$bucket_name" >/dev/null 2>/tmp/headbucket.err; then
  ok "bucket already exists"
elif grep -q '403' /tmp/headbucket.err 2>/dev/null; then
  die "bucket name '${bucket_name}' is already owned by another AWS account (S3 names are global)"
else
  if [[ "$aws_region" == "us-east-1" ]]; then
    create_out="$(aws_ s3api create-bucket --bucket "$bucket_name" --region "$aws_region" 2>&1)" || true
  else
    create_out="$(aws_ s3api create-bucket --bucket "$bucket_name" --region "$aws_region" \
      --create-bucket-configuration "LocationConstraint=${aws_region}" 2>&1)" || true
  fi
  if echo "$create_out" | grep -q 'BucketAlreadyOwnedByYou'; then
    ok "bucket already exists"
  elif echo "$create_out" | grep -qi 'error'; then
    die "failed to create bucket: ${create_out}"
  else
    ok "bucket created"
  fi
fi

# ─── Server-side encryption (AES256) ─────────────────────────────────────────
aws_ s3api put-bucket-encryption --bucket "$bucket_name" \
  --server-side-encryption-configuration \
  '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}' >/dev/null
ok "server-side encryption = AES256"

# ─── Public access block ─────────────────────────────────────────────────────
aws_ s3api put-public-access-block --bucket "$bucket_name" \
  --public-access-block-configuration \
  BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true >/dev/null
ok "public access blocked"

# ─── IAM role + trust policy ─────────────────────────────────────────────────
info "IAM role: ${rekognition_role_name}"
if aws_ iam get-role --role-name "$rekognition_role_name" >/dev/null 2>&1; then
  aws_ iam update-assume-role-policy --role-name "$rekognition_role_name" \
    --policy-document "$(trust_policy)" >/dev/null
  ok "role exists — trust policy updated"
else
  aws_ iam create-role --role-name "$rekognition_role_name" \
    --assume-role-policy-document "$(trust_policy)" >/dev/null
  ok "role created"
fi

# ─── Inline policy (rekognition:DetectText + S3 read) ────────────────────────
aws_ iam put-role-policy --role-name "$rekognition_role_name" \
  --policy-name "rekognition-and-s3-access" \
  --policy-document "$(role_inline_policy)" >/dev/null
ok "inline policy 'rekognition-and-s3-access' set"

# ─── Bucket policy (grant the role read access) ──────────────────────────────
# IAM is eventually consistent; retry briefly so the freshly-created role ARN
# is recognised as a valid principal by S3.
info "Bucket policy"
attempt=0
until aws_ s3api put-bucket-policy --bucket "$bucket_name" --policy "$(bucket_policy)" >/dev/null 2>&1; do
  attempt=$((attempt + 1))
  [[ "$attempt" -ge 6 ]] && die "failed to set bucket policy after several retries"
  warn "waiting for IAM role to propagate (attempt ${attempt})…"
  sleep 5
done
ok "bucket policy set"

# ─── Outputs (mirror outputs.tf) ─────────────────────────────────────────────
echo
info "Outputs"
echo "    bucket_name         = ${bucket_name}"
echo "    bucket_arn          = ${BUCKET_ARN}"
echo "    rekognition_role_arn = ${REKOGNITION_ROLE_ARN}"
echo
ok "Done. Set REKOGNITION_ROLE_ARN=${REKOGNITION_ROLE_ARN} in the agent runtime."
