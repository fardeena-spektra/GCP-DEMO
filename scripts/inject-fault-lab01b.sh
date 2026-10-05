#!/usr/bin/env bash
# =============================================================================
# CloudLabs | Lab 01B (Support) - fault injection
# Run when the learner starts Lab 01B, in the SAME project as Lab 01A.
#
# 1. If the learner never finished Lab 01A, deploys the reference agent so every
#    learner starts 01B from a known state (no manual intervention).
# 2. Injects two production faults:
#    Fault A - the agent loses read access to the knowledge base (403 in logs)
#    Fault B - the agent is pointed at the ARCHIVED 2023 file (wrong rates)
#    Fault B only shows after Fault A is fixed, like a real incident.
#
# Required:  PROJECT_ID
# Optional:  REGION (default europe-west2), KB_BUCKET (default: nbkb-* bucket)
# Self-contained: the reference agent is embedded below.
# =============================================================================
set -euo pipefail

: "${PROJECT_ID:?PROJECT_ID is required}"
REGION="${REGION:-europe-west2}"
SERVICE="bank-agent"
AGENT_SA="bank-agent-sa@${PROJECT_ID}.iam.gserviceaccount.com"
log() { echo "[fault $(date +%H:%M:%S)] $*"; }

gcloud config set project "${PROJECT_ID}" --quiet >/dev/null
if [ -z "${KB_BUCKET:-}" ]; then
  KB_BUCKET="$(gcloud storage buckets list --format='value(name)' --filter='name~^nbkb-' | head -1)"
fi
: "${KB_BUCKET:?No nbkb-* bucket found - run setup-environment.sh first}"
log "[1/4] Project ${PROJECT_ID}, bucket gs://${KB_BUCKET}"

# --- Baseline: make sure a healthy agent exists ----------------------------------
if ! gcloud run services describe "${SERVICE}" --region="${REGION}" >/dev/null 2>&1; then
  log "[2/4] ${SERVICE} not found - deploying the reference agent"
  SRC="$(mktemp -d)/bank_agent"; mkdir -p "${SRC}"
  echo "from . import agent" > "${SRC}/__init__.py"
  printf "google-adk\ngoogle-cloud-storage\n" > "${SRC}/requirements.txt"
  cat > "${SRC}/agent.py" <<'PY'
"""Northbridge Bank helpdesk agent - reference solution (Day 1, Lab 01A)."""
import json
import os

from google.adk.agents import Agent
from google.cloud import storage


def _log(severity: str, message: str, **fields) -> None:
    """Write a structured log line that Cloud Logging parses automatically."""
    print(json.dumps({"severity": severity, "message": message, **fields}), flush=True)


def get_product_info(product_name: str) -> dict:
    """Looks up official Northbridge Bank product details (rates, fees, eligibility).

    Args:
        product_name: A product name or keyword, for example "Everyday Saver" or "overdraft".

    Returns:
        A dict with a status, the knowledge-base version and the matching products.
    """
    bucket_name = os.environ.get("KB_BUCKET")
    file_name = os.environ.get("KB_FILE", "products.json")
    try:
        blob = storage.Client().bucket(bucket_name).blob(file_name)
        data = json.loads(blob.download_as_text())
    except Exception as exc:  # surfaced in Cloud Logging for the Support pathway
        _log("ERROR", "KB_READ_FAILED", bucket=bucket_name, file=file_name, error=str(exc))
        return {"status": "error", "message": "The product knowledge base is unavailable."}

    query = product_name.lower()
    matches = [
        p for p in data.get("products", [])
        if query in p["name"].lower() or any(k in query or query in k for k in p.get("keywords", []))
    ]
    _log("INFO", "KB_LOOKUP", query=product_name, file=file_name,
         kb_version=data.get("version"), matches=len(matches))
    return {
        "status": "success",
        "kb_version": data.get("version"),
        "products": matches or data.get("products", []),
    }


root_agent = Agent(
    name="northbridge_helpdesk",
    model=os.environ.get("AGENT_MODEL", "gemini-2.5-flash"),
    description="Answers customer questions about Northbridge Bank products.",
    instruction=(
        "You are Nova, the Northbridge Bank helpdesk assistant. "
        "For ANY question about products, interest rates, fees or eligibility you MUST call "
        "the get_product_info tool and answer only from its result. Never guess or invent figures. "
        "Quote rates exactly as returned (for example '4.15% AER'). "
        "If the tool returns an error, apologise, say product information is temporarily "
        "unavailable, and suggest the customer contacts Northbridge support."
    ),
    tools=[get_product_info],
)
PY
  pip install --quiet --upgrade google-adk >/dev/null
  export PATH="$HOME/.local/bin:$PATH"
  adk deploy cloud_run --project="${PROJECT_ID}" --region="${REGION}" \
    --service_name="${SERVICE}" --app_name=bank_agent --with_ui "${SRC}" \
    -- --service-account="${AGENT_SA}" --no-allow-unauthenticated --quiet
else
  log "[2/4] ${SERVICE} already exists - reusing the learner's Lab 01A agent"
fi

# Healthy baseline config before breaking it
gcloud run services update "${SERVICE}" --region="${REGION}" --quiet \
  --service-account="${AGENT_SA}" \
  --update-env-vars="GOOGLE_GENAI_USE_VERTEXAI=TRUE,GOOGLE_CLOUD_PROJECT=${PROJECT_ID},GOOGLE_CLOUD_LOCATION=${REGION},KB_BUCKET=${KB_BUCKET},KB_FILE=products.json" \
  >/dev/null

# --- Fault A: remove knowledge-base read access ----------------------------------
log "[3/4] Injecting Fault A (knowledge-base access)"
gcloud storage buckets remove-iam-policy-binding "gs://${KB_BUCKET}" \
  --member="serviceAccount:${AGENT_SA}" --role="roles/storage.objectViewer" --quiet >/dev/null || true

# --- Fault B: point the service at the archived 2023 file -------------------------
log "[4/4] Injecting Fault B (stale knowledge source)"
gcloud run services update "${SERVICE}" --region="${REGION}" --quiet \
  --update-env-vars="KB_FILE=archive/products_2023.json" >/dev/null

log "Faults injected. Lab 01B is ready."
