#!/usr/bin/env bash
# =============================================================================
# CloudLabs | Fast Lane GCP AI Engineering - Day 1 shared environment
# Post-deployment script. Runs ONCE per learner project, after deployment.yaml.
# Serves Lab 01A (Builder) and Lab 01B (Support). Self-contained: the knowledge
# files are embedded below, so nothing else needs to be downloaded.
#
# Required:  PROJECT_ID
# Optional:  REGION         (default europe-west2)
#            KB_BUCKET      (default: the nbkb-* bucket created by deployment.yaml)
#            LEARNER_EMAIL  (if set, learner roles are granted)
# Runs as the CloudLabs automation identity (Owner on PROJECT_ID). Idempotent.
# =============================================================================
set -euo pipefail

: "${PROJECT_ID:?PROJECT_ID is required}"
REGION="${REGION:-europe-west2}"
AGENT_SA="bank-agent-sa@${PROJECT_ID}.iam.gserviceaccount.com"
log() { echo "[setup $(date +%H:%M:%S)] $*"; }

gcloud config set project "${PROJECT_ID}" --quiet >/dev/null
PROJECT_NUMBER="$(gcloud projects describe "${PROJECT_ID}" --format='value(projectNumber)')"
COMPUTE_SA="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"

# --- 1. APIs -----------------------------------------------------------------
log "[1/6] Enabling APIs"
gcloud services enable \
  aiplatform.googleapis.com run.googleapis.com cloudbuild.googleapis.com \
  artifactregistry.googleapis.com storage.googleapis.com logging.googleapis.com \
  iam.googleapis.com cloudresourcemanager.googleapis.com --quiet

# --- 2. Knowledge-base bucket (created by deployment.yaml) ---------------------
if [ -z "${KB_BUCKET:-}" ]; then
  KB_BUCKET="$(gcloud storage buckets list --format='value(name)' --filter='name~^nbkb-' | head -1)"
fi
if [ -z "${KB_BUCKET}" ]; then
  KB_BUCKET="nbkb-${PROJECT_ID}"
  log "[2/6] No nbkb-* bucket found, creating gs://${KB_BUCKET}"
  gcloud storage buckets create "gs://${KB_BUCKET}" --location="${REGION}" --uniform-bucket-level-access --quiet
else
  log "[2/6] Using knowledge-base bucket gs://${KB_BUCKET}"
fi

TMP="$(mktemp -d)"; mkdir -p "${TMP}/archive"
cat > "${TMP}/products.json" <<'JSON'
{
  "bank": "Northbridge Bank",
  "version": "2026-10",
  "published": "2026-10-01",
  "products": [
    {
      "name": "Everyday Saver",
      "type": "Easy-access savings",
      "keywords": ["saver", "savings", "easy access", "everyday"],
      "rate_aer": "4.15%",
      "minimum_deposit": "£1",
      "withdrawals": "Unlimited, no notice required",
      "eligibility": "UK residents aged 16+ with a Northbridge current account"
    },
    {
      "name": "1-Year Fixed Rate Bond",
      "type": "Fixed-term savings",
      "keywords": ["bond", "fixed", "fixed rate", "1 year", "one year"],
      "rate_aer": "4.60%",
      "minimum_deposit": "£2,000",
      "withdrawals": "Not permitted until maturity",
      "eligibility": "UK residents aged 18+"
    },
    {
      "name": "Northbridge Current Account",
      "type": "Current account",
      "keywords": ["current", "current account", "debit", "overdraft", "card"],
      "monthly_fee": "£0",
      "arranged_overdraft_ear": "39.9% EAR variable",
      "overseas_card_fee": "0% on debit card purchases abroad",
      "eligibility": "UK residents aged 18+"
    }
  ]
}
JSON
cat > "${TMP}/archive/products_2023.json" <<'JSON'
{
  "bank": "Northbridge Bank",
  "version": "2023-04",
  "published": "2023-04-03",
  "note": "ARCHIVED - superseded. Do not use for customer quotes.",
  "products": [
    {
      "name": "Everyday Saver",
      "type": "Easy-access savings",
      "keywords": ["saver", "savings", "easy access", "everyday"],
      "rate_aer": "3.10%",
      "minimum_deposit": "£1",
      "withdrawals": "Up to 3 per year",
      "eligibility": "UK residents aged 16+ with a Northbridge current account"
    },
    {
      "name": "1-Year Fixed Rate Bond",
      "type": "Fixed-term savings",
      "keywords": ["bond", "fixed", "fixed rate", "1 year", "one year"],
      "rate_aer": "3.85%",
      "minimum_deposit": "£5,000",
      "withdrawals": "Not permitted until maturity",
      "eligibility": "UK residents aged 18+"
    },
    {
      "name": "Northbridge Current Account",
      "type": "Current account",
      "keywords": ["current", "current account", "debit", "overdraft", "card"],
      "monthly_fee": "£3",
      "arranged_overdraft_ear": "35.9% EAR variable",
      "overseas_card_fee": "2.75% on debit card purchases abroad",
      "eligibility": "UK residents aged 18+"
    }
  ]
}
JSON
gcloud storage cp "${TMP}/products.json" "gs://${KB_BUCKET}/products.json" --quiet
gcloud storage cp "${TMP}/archive/products_2023.json" "gs://${KB_BUCKET}/archive/products_2023.json" --quiet
rm -rf "${TMP}"

# --- 3. Agent runtime identity (created by deployment.yaml) ---------------------
log "[3/6] Checking runtime service account ${AGENT_SA}"
if ! gcloud iam service-accounts describe "${AGENT_SA}" >/dev/null 2>&1; then
  gcloud iam service-accounts create bank-agent-sa --display-name="Northbridge helpdesk agent runtime" --quiet
  sleep 10
fi
gcloud storage buckets add-iam-policy-binding "gs://${KB_BUCKET}" \
  --member="serviceAccount:${AGENT_SA}" --role="roles/storage.objectViewer" --quiet >/dev/null
for role in roles/aiplatform.user roles/logging.logWriter; do
  gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
    --member="serviceAccount:${AGENT_SA}" --role="${role}" --condition=None --quiet >/dev/null
done

# --- 4. Cloud Run source-deploy prerequisites (no prompts for learners) ---------
log "[4/6] Preparing Cloud Run source deploy"
gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
  --member="serviceAccount:${COMPUTE_SA}" --role="roles/cloudbuild.builds.builder" \
  --condition=None --quiet >/dev/null
if ! gcloud artifacts repositories describe cloud-run-source-deploy --location="${REGION}" >/dev/null 2>&1; then
  gcloud artifacts repositories create cloud-run-source-deploy --repository-format=docker \
    --location="${REGION}" --description="Cloud Run source deployments" --quiet
fi

# --- 5. Learner permissions ------------------------------------------------------
if [ -n "${LEARNER_EMAIL:-}" ]; then
  log "[5/6] Granting learner roles to ${LEARNER_EMAIL}"
  for role in roles/editor roles/run.admin roles/storage.admin \
              roles/iam.serviceAccountUser roles/logging.viewer roles/aiplatform.user; do
    gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
      --member="user:${LEARNER_EMAIL}" --role="${role}" --condition=None --quiet >/dev/null
  done
else
  log "[5/6] LEARNER_EMAIL not set, skipping learner roles"
fi

# --- 6. Done ---------------------------------------------------------------------
log "[6/6] Environment ready: project=${PROJECT_ID} region=${REGION} bucket=${KB_BUCKET} sa=${AGENT_SA}"
