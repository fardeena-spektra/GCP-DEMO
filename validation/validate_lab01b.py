"""Lab 01B (Support/Engineering) - automated validation.

Tasks
  ex2-task2  Fault A fixed: runtime identity can read the knowledge base again
  ex3-task2  Fault B fixed: service points at the current knowledge file
  ex4-task1  Incident resolved: live agent returns current, grounded rates

Usage: python validate_lab01b.py --task ex2-task2 --project <PROJECT_ID> [--region europe-west2]
"""
from common import (EXPECTED_RATE, STALE_RATE, agent_sa, ask_agent, get_service,
                    kb_bucket, run, service_env, session)

READ_ROLES = {"roles/storage.objectViewer", "roles/storage.objectUser",
              "roles/storage.objectAdmin", "roles/storage.admin"}


def _member_has_read(policy, member):
    return any(b.get("role") in READ_ROLES and member in b.get("members", []) and not b.get("condition")
               for b in policy.get("bindings", []))


def ex2_task2(project, region):
    member = f"serviceAccount:{agent_sa(project)}"
    s = session()
    bucket_policy = s.get(f"https://storage.googleapis.com/storage/v1/b/{kb_bucket(project)}/iam",
                          timeout=30).json()
    if _member_has_read(bucket_policy, member):
        return True, "The agent's runtime identity can read the knowledge-base bucket again."
    project_policy = s.post(
        f"https://cloudresourcemanager.googleapis.com/v1/projects/{project}:getIamPolicy",
        json={}, timeout=30).json()
    if _member_has_read(project_policy, member):
        return True, ("Access restored at project level. It works, but least privilege would grant "
                      "roles/storage.objectViewer on the bucket only.")
    return False, f"{agent_sa(project)} still cannot read gs://{kb_bucket(project)}. Check the bucket permissions."


def ex3_task2(project, region):
    svc = get_service(project, region)
    if not svc:
        return False, "Cloud Run service 'bank-agent' was not found."
    kb_file = service_env(svc).get("KB_FILE", "products.json")
    if kb_file != "products.json":
        return False, f"The service still reads '{kb_file}'. It should use the current file 'products.json'."
    return True, "The service is configured to use the current knowledge file."


def ex4_task1(project, region):
    svc = get_service(project, region)
    if not svc or not svc.get("uri"):
        return False, "Cloud Run service 'bank-agent' was not found."
    text, tool_called = ask_agent(svc["uri"])
    if STALE_RATE in text:
        return False, "The agent is still quoting the archived 2023 rate - the stale knowledge source is in use."
    if not tool_called or EXPECTED_RATE not in text:
        return False, f"The agent is not yet returning the current grounded rate. Response: {text[:200]}"
    return True, "Incident resolved: the agent returns current, grounded product information."


if __name__ == "__main__":
    run({"ex2-task2": ex2_task2, "ex3-task2": ex3_task2, "ex4-task1": ex4_task1})
