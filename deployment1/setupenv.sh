#!/usr/bin/env bash
# =============================================================================
# CloudLabs | Fast Lane GCP AI Day 1 - lab setup (runs once on setupvm)
# Downloaded and run by setupvm's startup script (see deployment.yaml).
#   1. turn on the lab APIs
#   2. upload the knowledge files (embedded below) to the nbkb-* bucket
#   3. bank-agent-sa: read this bucket only + Vertex AI user + Logs writer
# Every step retries, because new service accounts and APIs take time to appear.
# Exit 0 = everything done (setupvm then stops itself). Exit 1 = retry at next boot.
# Required: PROJECT_ID   Optional: REGION
# =============================================================================
set -uo pipefail
: "${PROJECT_ID:?PROJECT_ID is required}"
AGENT_SA="bank-agent-sa@${PROJECT_ID}.iam.gserviceaccount.com"
log() { echo "[setup $(date +%H:%M:%S)] $*"; }
retry() { # retry <tries> <sleep> <description> <command...>
  local n=$1 s=$2 d=$3; shift 3
  for i in $(seq 1 "$n"); do
    if "$@" >/tmp/retry.out 2>&1; then log "OK      $d"; return 0; fi
    log "waiting $d (attempt $i/$n): $(tail -c 200 /tmp/retry.out | tr '\n' ' ')"; sleep "$s"
  done
  log "FAILED  $d"; return 1
}
FAILED=0
gcloud config set project "${PROJECT_ID}" --quiet >/dev/null 2>&1

log "[1/4] Turning on the lab APIs"
retry 10 15 "lab APIs enabled" gcloud services enable aiplatform.googleapis.com compute.googleapis.com \
  iap.googleapis.com storage.googleapis.com logging.googleapis.com iam.googleapis.com \
  cloudresourcemanager.googleapis.com --quiet || FAILED=1

log "[2/4] Finding the knowledge-base bucket"
KB_BUCKET=""
for i in $(seq 1 20); do
  KB_BUCKET="$(gcloud storage buckets list --format='value(name)' --filter='name~^nbkb-' 2>/dev/null | head -1)"
  [ -n "$KB_BUCKET" ] && break; sleep 10
done
if [ -z "$KB_BUCKET" ]; then log "FAILED  no nbkb-* bucket found"; exit 1; fi
log "OK      bucket gs://${KB_BUCKET}"

log "[3/4] Uploading the knowledge files"
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
retry 5 10 "products.json uploaded" gcloud storage cp "${TMP}/products.json" "gs://${KB_BUCKET}/products.json" --quiet || FAILED=1
retry 5 10 "archive/products_2023.json uploaded" gcloud storage cp "${TMP}/archive/products_2023.json" "gs://${KB_BUCKET}/archive/products_2023.json" --quiet || FAILED=1

log "[4/4] Permissions for ${AGENT_SA}"
retry 20 15 "agent service account exists" gcloud iam service-accounts describe "${AGENT_SA}" || FAILED=1
retry 10 15 "agent can read gs://${KB_BUCKET}" gcloud storage buckets add-iam-policy-binding "gs://${KB_BUCKET}" \
  --member="serviceAccount:${AGENT_SA}" --role="roles/storage.objectViewer" --quiet || FAILED=1
for role in roles/aiplatform.user roles/logging.logWriter; do
  retry 10 15 "agent has ${role}" gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
    --member="serviceAccount:${AGENT_SA}" --role="${role}" --condition=None --quiet || FAILED=1
done

if [ "$FAILED" -eq 0 ]; then log "ALL DONE - environment ready"; exit 0; fi
log "SOME STEPS FAILED - will retry at the next boot"; exit 1
