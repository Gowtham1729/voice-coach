#!/usr/bin/env bash
# One-time setup for Firebase Hosting deploys from GitHub Actions.
#
# Run once while gcloud is logged in as an owner of ichido-511210:
#   scripts/setup-firebase-wif.sh
#
# The script does not create a billing account and does not create a
# service account key. It enables Firebase Hosting only: no Auth,
# Firestore, Storage, Functions, or Analytics.

set -euo pipefail

PROJECT_ID="ichido-511210"
POOL_ID="github"
PROVIDER_ID="github-actions"
SA_NAME="website-deploy"
SA_EMAIL="${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
REPO="Gowtham1729/voice-coach"
ATTR_CONDITION="assertion.repository=='${REPO}' && assertion.ref=='refs/heads/main' && assertion.event_name=='push'"
ATTR_MAPPING="google.subject=assertion.sub,attribute.repository=assertion.repository,attribute.ref=assertion.ref,attribute.event_name=assertion.event_name"

export CLOUDSDK_CORE_DISABLE_PROMPTS=1

tmpfiles=()
cleanup() {
  if ((${#tmpfiles[@]} > 0)); then
    rm -f -- "${tmpfiles[@]}"
  fi
}
trap cleanup EXIT

new_tmp() {
  local file
  file="$(mktemp)"
  tmpfiles+=("$file")
  printf '%s\n' "$file"
}

die() {
  printf '%s\n' "$*" >&2
  exit 1
}

need() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

need gcloud
need curl
need python3

active_account="$(gcloud auth list --filter='status:ACTIVE' --format='value(account)')"
[[ -n "$active_account" ]] || die "gcloud has no active account. Run 'gcloud auth login' as an owner of ${PROJECT_ID} and rerun this script."
printf 'Using gcloud account %s\n' "$active_account"

gcloud config set project "$PROJECT_ID" >/dev/null
gcloud projects describe "$PROJECT_ID" >/dev/null \
  || die "gcloud cannot see project ${PROJECT_ID}. Log in as an owner of that project. This script does not create a project."

billing_enabled="$(gcloud billing projects describe "$PROJECT_ID" --format='value(billingEnabled)' 2>/dev/null || true)"
case "$billing_enabled" in
  True | true | TRUE) ;;
  *)
    die "Billing is not linked on ${PROJECT_ID} (billingEnabled='${billing_enabled:-unknown}'). Link the existing billing account in the Google Cloud console. This script will not create a billing account."
    ;;
esac
printf 'Billing is linked on %s.\n' "$PROJECT_ID"

printf 'Enabling Hosting and Workload Identity APIs.\n'
gcloud services enable \
  firebase.googleapis.com \
  firebasehosting.googleapis.com \
  iam.googleapis.com \
  iamcredentials.googleapis.com \
  sts.googleapis.com \
  cloudresourcemanager.googleapis.com \
  serviceusage.googleapis.com \
  --project="$PROJECT_ID"

# HEADER_FILE and HTTP_STATUS are set in this shell. Do not call these
# functions inside $(...), or the token file would escape the cleanup trap.
HEADER_FILE=""
HTTP_STATUS=""

auth_header() {
  local token
  token="$(gcloud auth print-access-token)"
  HEADER_FILE="$(mktemp)"
  tmpfiles+=("$HEADER_FILE")
  chmod 600 "$HEADER_FILE"
  printf 'Authorization: Bearer %s\nx-goog-user-project: %s\n' "$token" "$PROJECT_ID" >"$HEADER_FILE"
}

# Body goes to the path in $3. Status is left in HTTP_STATUS.
api() {
  local method="$1" url="$2" body_file="$3" data="${4:-}"
  auth_header
  if [[ -n "$data" ]]; then
    HTTP_STATUS="$(curl -sS -o "$body_file" -w '%{http_code}' -X "$method" \
      -H @"$HEADER_FILE" -H 'Content-Type: application/json' \
      --data "$data" "$url")"
  else
    HTTP_STATUS="$(curl -sS -o "$body_file" -w '%{http_code}' -X "$method" \
      -H @"$HEADER_FILE" "$url")"
  fi
}

json_done() {
  python3 -c 'import json,sys; d=json.load(open(sys.argv[1]));
print("error" if d.get("error") else ("done" if d.get("done") else "pending"))' "$1"
}

add_firebase_if_missing() {
  local body http op state attempts
  body="$(new_tmp)"
  api GET "https://firebase.googleapis.com/v1beta1/projects/${PROJECT_ID}" "$body" \
    || die "Could not read the Firebase project record."
  http="$HTTP_STATUS"
  if [[ "$http" == "200" ]]; then
    printf 'Firebase is already on %s.\n' "$PROJECT_ID"
    return
  fi
  if [[ "$http" == "403" ]]; then
    printf 'Permission denied reading Firebase for %s:\n' "$PROJECT_ID" >&2
    cat "$body" >&2
    die "Log in as an owner of ${PROJECT_ID} and rerun this script."
  fi
  [[ "$http" == "404" ]] || {
    printf 'Unexpected Firebase project lookup (%s):\n' "$http" >&2
    cat "$body" >&2
    exit 1
  }

  printf 'Adding Firebase to %s. Hosting only; not enabling Auth, Firestore, Storage, Functions, or Analytics.\n' "$PROJECT_ID"
  attempts=0
  while ((attempts < 12)); do
    api POST "https://firebase.googleapis.com/v1beta1/projects/${PROJECT_ID}:addFirebase" "$body" '{}' \
      || die "addFirebase request failed."
    http="$HTTP_STATUS"
    if [[ "$http" == "409" ]]; then
      printf 'Firebase was already added.\n'
      return
    fi
    if [[ "$http" == "200" ]]; then
      break
    fi
    attempts=$((attempts + 1))
    printf 'addFirebase not ready (%s). Retrying.\n' "$http"
    sleep 5
  done
  [[ "$http" == "200" ]] || {
    printf 'addFirebase failed (%s):\n' "$http" >&2
    cat "$body" >&2
    exit 1
  }

  op="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["name"])' "$body")"
  [[ -n "$op" ]] || die "addFirebase did not return an operation name."
  attempts=0
  while ((attempts < 30)); do
    api GET "https://firebase.googleapis.com/v1beta1/${op}" "$body" \
      || die "Could not read the addFirebase operation."
    http="$HTTP_STATUS"
    [[ "$http" == "200" ]] || die "addFirebase operation lookup failed (${http})."
    state="$(json_done "$body")"
    if [[ "$state" == "done" ]]; then
      printf 'Firebase is on %s.\n' "$PROJECT_ID"
      return
    fi
    if [[ "$state" == "error" ]]; then
      printf 'addFirebase operation failed:\n' >&2
      cat "$body" >&2
      exit 1
    fi
    attempts=$((attempts + 1))
    sleep 2
  done
  die "Timed out waiting for Firebase to be added to ${PROJECT_ID}."
}

ensure_hosting_site() {
  local body http attempts
  body="$(new_tmp)"
  attempts=0
  while ((attempts < 12)); do
    api GET "https://firebasehosting.googleapis.com/v1beta1/projects/${PROJECT_ID}/sites/${PROJECT_ID}" "$body" \
      || die "Could not read the Hosting site."
    http="$HTTP_STATUS"
    if [[ "$http" == "200" ]]; then
      printf 'Hosting site %s already exists.\n' "$PROJECT_ID"
      return
    fi
    if [[ "$http" == "404" ]]; then
      api POST "https://firebasehosting.googleapis.com/v1beta1/projects/${PROJECT_ID}/sites?siteId=${PROJECT_ID}" "$body" '{}' \
        || die "Could not create the Hosting site."
      http="$HTTP_STATUS"
      if [[ "$http" == "200" || "$http" == "409" ]]; then
        printf 'Hosting site %s is ready (https://%s.web.app).\n' "$PROJECT_ID" "$PROJECT_ID"
        return
      fi
    fi
    attempts=$((attempts + 1))
    printf 'Hosting site not ready (%s). Retrying.\n' "$http"
    sleep 5
  done
  printf 'Could not ensure Hosting site %s. Last response:\n' "$PROJECT_ID" >&2
  cat "$body" >&2
  exit 1
}

add_firebase_if_missing
ensure_hosting_site

if ! gcloud iam workload-identity-pools describe "$POOL_ID" \
  --location=global --project="$PROJECT_ID" >/dev/null 2>&1; then
  printf 'Creating Workload Identity pool %s.\n' "$POOL_ID"
  gcloud iam workload-identity-pools create "$POOL_ID" \
    --location=global \
    --project="$PROJECT_ID" \
    --display-name="GitHub Actions" \
    --description="Trusts pushes to ${REPO} main for the public promo site."
else
  printf 'Workload Identity pool %s already exists.\n' "$POOL_ID"
fi

if ! gcloud iam workload-identity-pools providers describe "$PROVIDER_ID" \
  --workload-identity-pool="$POOL_ID" \
  --location=global --project="$PROJECT_ID" >/dev/null 2>&1; then
  printf 'Creating GitHub OIDC provider %s.\n' "$PROVIDER_ID"
  gcloud iam workload-identity-pools providers create-oidc "$PROVIDER_ID" \
    --workload-identity-pool="$POOL_ID" \
    --location=global \
    --project="$PROJECT_ID" \
    --display-name="GitHub Actions" \
    --issuer-uri="https://token.actions.githubusercontent.com" \
    --attribute-mapping="$ATTR_MAPPING" \
    --attribute-condition="$ATTR_CONDITION"
else
  printf 'Updating GitHub OIDC provider %s.\n' "$PROVIDER_ID"
  gcloud iam workload-identity-pools providers update-oidc "$PROVIDER_ID" \
    --workload-identity-pool="$POOL_ID" \
    --location=global \
    --project="$PROJECT_ID" \
    --issuer-uri="https://token.actions.githubusercontent.com" \
    --attribute-mapping="$ATTR_MAPPING" \
    --attribute-condition="$ATTR_CONDITION"
fi

if ! gcloud iam service-accounts describe "$SA_EMAIL" --project="$PROJECT_ID" >/dev/null 2>&1; then
  printf 'Creating deploy service account %s with no key.\n' "$SA_EMAIL"
  gcloud iam service-accounts create "$SA_NAME" \
    --project="$PROJECT_ID" \
    --display-name="Ichido website deploy" \
    --description="Deploys Firebase Hosting for the public promo site. No JSON keys."
else
  printf 'Deploy service account %s already exists.\n' "$SA_EMAIL"
fi

# Refuse keys. This script never calls `gcloud iam service-accounts keys create`.
user_keys="$(gcloud iam service-accounts keys list \
  --iam-account="$SA_EMAIL" \
  --project="$PROJECT_ID" \
  --managed-by=user \
  --format='value(name)')"
if [[ -n "$user_keys" ]]; then
  die "Refusing to continue: ${SA_EMAIL} has user-managed keys. Delete them in the console. This script does not create or use service account keys."
fi

gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:${SA_EMAIL}" \
  --role="roles/firebasehosting.admin" \
  --condition=None \
  --quiet >/dev/null
printf 'Granted roles/firebasehosting.admin on %s only.\n' "$PROJECT_ID"

project_number="$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)')"
[[ "$project_number" =~ ^[0-9]+$ ]] || die "Could not read the project number for ${PROJECT_ID}."
provider_resource="projects/${project_number}/locations/global/workloadIdentityPools/${POOL_ID}/providers/${PROVIDER_ID}"
principal="principalSet://iam.googleapis.com/projects/${project_number}/locations/global/workloadIdentityPools/${POOL_ID}/attribute.repository/${REPO}"

gcloud iam service-accounts add-iam-policy-binding "$SA_EMAIL" \
  --project="$PROJECT_ID" \
  --role="roles/iam.workloadIdentityUser" \
  --member="$principal" \
  --condition=None \
  --quiet >/dev/null
printf 'Granted roles/iam.workloadIdentityUser to pushes of %s main.\n' "$REPO"

cat <<EOF

Workload Identity provider:
  ${provider_resource}

Deploy service account:
  ${SA_EMAIL}

Set these GitHub Actions variables (not secrets) before merging the deploy workflow:

gh variable set WORKLOAD_IDENTITY_PROVIDER --repo ${REPO} --body "${provider_resource}"
gh variable set WORKLOAD_IDENTITY_SERVICE_ACCOUNT --repo ${REPO} --body "${SA_EMAIL}"

No service account key was created. No billing account was created.
After the variables are set, a push to main deploys Hosting to https://${PROJECT_ID}.web.app
EOF
