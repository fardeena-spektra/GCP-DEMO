"""Lab 01A (Builder) - automated validation.

Tasks
  ex3-task1  Agent deployed to Cloud Run with the correct runtime identity and config
  ex3-task2  Deployed agent answers using the knowledge-base tool (live functional test)

Usage: python validate_lab01a.py --task ex3-task1 --project <PROJECT_ID> [--region europe-west2]
"""
from common import (EXPECTED_RATE, SERVICE, agent_sa, ask_agent, get_service,
                    kb_bucket, run, service_env)


def ex3_task1(project, region):
    svc = get_service(project, region)
    if not svc:
        return False, f"Cloud Run service '{SERVICE}' was not found in {region}. Revisit Exercise 3, Task 1."
    if svc.get("template", {}).get("serviceAccount") != agent_sa(project):
        return False, f"The service is not running as {agent_sa(project)}. Re-run the 'gcloud run services update' step."
    env = service_env(svc)
    if env.get("KB_BUCKET") != kb_bucket(project):
        return False, "Environment variable KB_BUCKET is missing or incorrect on the Cloud Run service."
    if env.get("KB_FILE", "products.json") != "products.json":
        return False, "Environment variable KB_FILE should be 'products.json'."
    if not svc.get("uri"):
        return False, "The service has no URL yet - wait for the deployment to finish and retry."
    return True, f"Agent deployed at {svc['uri']} with the correct identity and configuration."


def ex3_task2(project, region):
    svc = get_service(project, region)
    if not svc or not svc.get("uri"):
        return False, "Deploy the agent first (Exercise 3, Task 1)."
    text, tool_called = ask_agent(svc["uri"])
    if not tool_called:
        return False, "The agent answered without calling get_product_info. Check the tool is registered and the instruction requires it."
    if EXPECTED_RATE not in text:
        return False, f"The agent did not return the current Everyday Saver rate ({EXPECTED_RATE}% AER). Response: {text[:200]}"
    return True, "The deployed agent called the knowledge-base tool and returned the correct, grounded answer."


if __name__ == "__main__":
    run({"ex3-task1": ex3_task1, "ex3-task2": ex3_task2})
