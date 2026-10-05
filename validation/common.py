"""Shared helpers for CloudLabs automated validation, Fast Lane GCP AI Day 1.

Runs with the CloudLabs validation service account (GOOGLE_APPLICATION_CREDENTIALS
or ambient ADC). Uses only REST APIs: google-auth + requests.
Every check returns (passed: bool, message: str); main() prints the JSON
result that the CloudLabs validation engine records against the task.
"""
import argparse
import json
import sys
import uuid

import google.auth
import google.auth.transport.requests
import requests
from google.oauth2 import id_token

SERVICE = "bank-agent"
APP_NAME = "bank_agent"
AGENT_SA_NAME = "bank-agent-sa"
TOOL_NAME = "get_product_info"
TEST_PROMPT = "What is the interest rate on the Everyday Saver account?"
EXPECTED_RATE = "4.15"
STALE_RATE = "3.10"

_SCOPES = ["https://www.googleapis.com/auth/cloud-platform"]


def session():
    creds, _ = google.auth.default(scopes=_SCOPES)
    return google.auth.transport.requests.AuthorizedSession(creds)


def agent_sa(project):
    return f"{AGENT_SA_NAME}@{project}.iam.gserviceaccount.com"


_BUCKET_CACHE = {}


def kb_bucket(project):
    """Return the knowledge-base bucket created by deployment.yaml (nbkb-<deploymentId>)."""
    if project not in _BUCKET_CACHE:
        r = session().get("https://storage.googleapis.com/storage/v1/b",
                          params={"project": project, "prefix": "nbkb-"}, timeout=30)
        r.raise_for_status()
        items = r.json().get("items", [])
        _BUCKET_CACHE[project] = items[0]["name"] if items else f"nbkb-{project}"
    return _BUCKET_CACHE[project]


def get_service(project, region):
    """Return the Cloud Run v2 service resource, or None if it doesn't exist."""
    url = f"https://run.googleapis.com/v2/projects/{project}/locations/{region}/services/{SERVICE}"
    r = session().get(url, timeout=30)
    if r.status_code == 404:
        return None
    r.raise_for_status()
    return r.json()


def service_env(svc):
    containers = svc.get("template", {}).get("containers", [])
    return {e["name"]: e.get("value") for c in containers for e in c.get("env", [])}


def ask_agent(url, prompt=TEST_PROMPT, attempts=2):
    """Call the deployed ADK API server. Returns (final_text, tool_was_called)."""
    token = id_token.fetch_id_token(google.auth.transport.requests.Request(), url)
    headers = {"Authorization": f"Bearer {token}", "Content-Type": "application/json"}
    last_text, last_tool = "", False
    for _ in range(attempts):
        user, sid = "cloudlabs-validator", f"val-{uuid.uuid4().hex[:8]}"
        requests.post(f"{url}/apps/{APP_NAME}/users/{user}/sessions/{sid}",
                      headers=headers, json={}, timeout=120).raise_for_status()
        body = {"app_name": APP_NAME, "user_id": user, "session_id": sid,
                "new_message": {"role": "user", "parts": [{"text": prompt}]}}
        r = requests.post(f"{url}/run", headers=headers, json=body, timeout=180)
        r.raise_for_status()
        texts, tool_called = [], False
        for event in r.json():
            for part in (event.get("content") or {}).get("parts", []) or []:
                if part.get("functionCall", {}).get("name") == TOOL_NAME:
                    tool_called = True
                if part.get("text"):
                    texts.append(part["text"])
        last_text, last_tool = (texts[-1] if texts else ""), tool_called
        if EXPECTED_RATE in last_text and tool_called:
            break
    return last_text, last_tool


def run(checks):
    """CLI entry point: --task <id> --project <id> [--region]."""
    p = argparse.ArgumentParser()
    p.add_argument("--task", required=True, choices=sorted(checks))
    p.add_argument("--project", required=True)
    p.add_argument("--region", default="europe-west2")
    a = p.parse_args()
    try:
        ok, msg = checks[a.task](a.project, a.region)
    except Exception as exc:  # never crash the validation engine
        ok, msg = False, f"Validation could not complete: {exc}"
    print(json.dumps({"task": a.task, "status": "Succeeded" if ok else "Failed", "message": msg}))
    sys.exit(0 if ok else 1)
