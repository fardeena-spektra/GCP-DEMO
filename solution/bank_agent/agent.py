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
