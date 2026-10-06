# Day 1 – Builder Pathway: Build Your First Banking Agent on Google Cloud

### Estimated Duration: 25 Minutes

### Pathway: AI Developer / Builder &nbsp;|&nbsp; Level: Foundation &nbsp;|&nbsp; Points: 100

## Lab Scenario

Northbridge Bank wants a customer helpdesk assistant that answers questions about its savings and current-account products. The compliance team has one non-negotiable rule: **the assistant must never invent a rate or fee.** Every figure must come from the bank's approved product knowledge base.

In this lab, you play the role of an AI developer on the bank's digital team. You will build an AI agent with Google's **Agent Development Kit (ADK)** and **Gemini on Vertex AI**, give it a tool that reads the approved knowledge base from **Cloud Storage**, and deploy it as a secure, private service on a **Compute Engine** virtual machine.

> **Note:** This lab shares its environment with **Day 1 – Support Pathway (Lab 01B)**. The agent you build here is the service that the Support/Engineering team will operate and troubleshoot.

## Lab Objectives

In this lab, you will complete the following exercises:

- Exercise 1: Explore your lab environment
- Exercise 2: Build and test the agent with the Agent Development Kit
- Exercise 3: Deploy the agent to Compute Engine

## Architecture

```
 Learner (Cloud Shell)
        │  IAP tunnel (no public port)
        ▼
 ┌───────────────────────────┐      get_product_info()     ┌──────────────────────────┐
 │ Compute Engine: agent-vm  │ ──────────────────────────▶ │ Cloud Storage            │
 │ ADK agent "Nova"          │   (runs as bank-agent-sa)    │ gs://nbkb-<deploymentId> │
 │ (private, IAP only)       │                              │   products.json          │
 └────────────┬──────────────┘                              └──────────────────────────┘
              │ Gemini 2.5 Flash (lab region)
              ▼
        Vertex AI                                   Cloud Logging ◀── structured logs
```

## Lab Environment Details

Your isolated Google Cloud project has been pre-provisioned with the following:

| Resource | Value |
|---|---|
| Project ID | <inject key="ProjectId" enableCopy="true"/> |
| Region | **<inject key="Region" enableCopy="true"/>** |
| Knowledge-base bucket | <inject key="KbBucket" enableCopy="true"/> |
| Agent runtime service account | <inject key="AgentServiceAccount" enableCopy="true"/> |

---

## Exercise 1: Explore your lab environment

In this exercise, you will sign in to the Google Cloud console, open Cloud Shell and review the knowledge base that your agent will use.

### Task 1: Sign in to the Google Cloud console

1. On the lab VM desktop, double-click the **Google Cloud Console** shortcut.

1. On the **Sign in** page, enter the following email and select **Next**:

   - Email/Username: <inject key="AzureADUserEmail" enableCopy="true"/>

1. Enter the following password and select **Next**:

   - Password: <inject key="AzureADUserPassword" enableCopy="true"/>

1. If prompted, accept the **Terms of Service** and select **Agree and continue**.

1. From the project selector at the top of the console, select your project <inject key="ProjectId" enableCopy="false"/>.

1. Select the **Activate Cloud Shell** icon (**>_**) in the top-right corner of the console. When prompted, select **Continue** and then **Authorize**.

1. In Cloud Shell, run the following commands to set your working variables:

   ```bash
   export PROJECT_ID=${DEVSHELL_PROJECT_ID:-$(gcloud projects list --format='value(projectId)' --limit=1)}
   export KB_BUCKET=$(gcloud storage buckets list --project=$PROJECT_ID --format='value(name)' --filter='name~^nbkb-')
   export REGION=$(gcloud storage buckets describe gs://$KB_BUCKET --format='value(location)' | tr '[:upper:]' '[:lower:]')
   export AGENT_SA=bank-agent-sa@${PROJECT_ID}.iam.gserviceaccount.com
   gcloud config set project $PROJECT_ID
   echo "Project: $PROJECT_ID | Region: $REGION | Bucket: $KB_BUCKET"
   ```

   The last line prints your project ID, region and knowledge-base bucket. Confirm all three values are shown.

   > **Note:** If Cloud Shell restarts at any point during the lab, re-run the commands above.

### Task 2: Review the approved knowledge base

1. In Cloud Shell, list the contents of the knowledge-base bucket:

   ```bash
   gcloud storage ls -r gs://$KB_BUCKET
   ```

   You will see `products.json` (the current approved catalogue) and an `archive/` folder.

1. View the current product catalogue:

   ```bash
   gcloud storage cat gs://$KB_BUCKET/products.json
   ```

1. Note the **Everyday Saver** rate (**4.15% AER**) and the catalogue `version`. You will use these to verify that your agent answers from the knowledge base rather than from the model's general knowledge.

   > **Note:** Do not use the files in `archive/`. They are superseded and are kept for audit purposes only.

---

## Exercise 2: Build and test the agent with the Agent Development Kit

In this exercise, you will create an ADK agent with a single tool, `get_product_info`, and test it locally in Cloud Shell before deploying it.

### Task 1: Install ADK and create the agent project

1. Install the Agent Development Kit:

   ```bash
   pip install --quiet --upgrade google-adk
   export PATH=$HOME/.local/bin:$PATH
   adk telemetry disable
   adk --version
   ```

1. Create the agent folder. ADK expects one folder per agent containing `__init__.py`, `agent.py` and `requirements.txt`:

   ```bash
   mkdir -p ~/bank_agent && cd ~
   echo "from . import agent" > ~/bank_agent/__init__.py
   printf "google-adk\ngoogle-cloud-storage\n" > ~/bank_agent/requirements.txt
   ```

1. Create a `.env` file so the agent uses **Gemini on Vertex AI** in your lab region:

   ```bash
   cat > ~/bank_agent/.env <<EOF
   GOOGLE_GENAI_USE_VERTEXAI=TRUE
   GOOGLE_CLOUD_PROJECT=$PROJECT_ID
   GOOGLE_CLOUD_LOCATION=$REGION
   EOF
   ```

### Task 2: Write the agent and its knowledge-base tool

1. Create `agent.py`. Read through the code before you run it. It has three parts:

   - **`_log`** writes structured JSON logs that Cloud Logging indexes automatically. The Support team relies on these.
   - **`get_product_info`** is the **tool**. ADK reads the function's docstring and type hints to tell Gemini when and how to call it.
   - **`root_agent`** is the **agent**: a model, an instruction (the guardrail) and a list of tools.

   ```bash
   cat > ~/bank_agent/agent.py <<'EOF'
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
       except Exception as exc:
           _log("ERROR", "KB_READ_FAILED", bucket=bucket_name, file=file_name, error=str(exc))
           return {"status": "error", "message": "The product knowledge base is unavailable."}

       query = product_name.lower()
       matches = [
           p for p in data.get("products", [])
           if query in p["name"].lower() or any(k in query or query in k for k in p.get("keywords", []))
       ]
       _log("INFO", "KB_LOOKUP", query=product_name, file=file_name,
            kb_version=data.get("version"), matches=len(matches))
       return {"status": "success", "kb_version": data.get("version"),
               "products": matches or data.get("products", [])}

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
   EOF
   ```

### Task 3: Test the agent locally

1. Start the ADK developer UI from your home folder:

   ```bash
   cd ~ && adk web --port 8080
   ```

1. In the Cloud Shell toolbar, select **Web Preview** > **Preview on port 8080**. A new browser tab opens the ADK Dev UI.

1. In the top-left drop-down, select **bank_agent**.

1. In the chat box, enter the following prompts one at a time and review the answers:

   - `What is the interest rate on the Everyday Saver account?`
   - `Do you charge a fee for using my debit card abroad?`
   - `What's the best stock to invest in?`

1. Select the **Events** tab on the left and select the first response. Confirm that the agent issued a **functionCall** to `get_product_info`, received a **functionResponse**, and quoted **4.15% AER**. This trace proves that the answer is grounded in the knowledge base.

   > **Note:** If Web Preview does not load, stop the server with **Ctrl+C** and test in the terminal instead by running `adk run bank_agent`.

1. Return to Cloud Shell and press **Ctrl+C** to stop the local server.

---

## Exercise 3: Deploy the agent to Compute Engine

In this exercise, you will deploy the agent to a private Compute Engine virtual machine that runs under its own least-privilege identity, and then call it securely through Identity-Aware Proxy (IAP).

### Task 1: Deploy the agent to a private VM

1. Upload your agent code to the deployment folder in the knowledge-base bucket:

   ```bash
   gcloud storage cp -r ~/bank_agent gs://$KB_BUCKET/app/
   ```

1. Download the VM startup script. It installs ADK, loads your agent and starts it on port 8080 every time the VM boots:

   ```bash
   curl -fsSL https://raw.githubusercontent.com/fardeena-spektra/GCP-DEMO/refs/heads/main/deployment1/agentvmstartup.sh -o ~/agent-vm-startup.sh
   ```

1. Find the zone and subnet of your lab network:

   ```bash
   export ZONE=$(gcloud compute instances list --filter='name~^labvm-' --format='value(zone.basename())')
   export SUBNET=$(gcloud compute networks subnets list --filter='name~^clgsubnet-' --format='value(name)')
   echo "Zone: $ZONE | Subnet: $SUBNET"
   ```

1. Create the agent VM. It runs as **bank-agent-sa**, carries the **agent** network tag (reachable only through IAP) and reads its settings from VM metadata:

   ```bash
   gcloud compute instances create agent-vm \
     --zone=$ZONE \
     --machine-type=e2-medium \
     --subnet=$SUBNET \
     --tags=agent \
     --service-account=$AGENT_SA \
     --scopes=cloud-platform \
     --image-family=debian-12 \
     --image-project=debian-cloud \
     --metadata=KB_BUCKET=$KB_BUCKET,KB_FILE=products.json,GOOGLE_CLOUD_LOCATION=$REGION \
     --metadata-from-file=startup-script=$HOME/agent-vm-startup.sh
   ```

1. The first boot installs ADK and takes about **3–5 minutes**. Run the following command and wait for **AGENT READY**:

   ```bash
   for i in $(seq 1 40); do
     gcloud compute ssh agent-vm --zone=$ZONE --tunnel-through-iap --quiet \
       --command="curl -s -o /dev/null -w '%{http_code}' localhost:8080/list-apps" 2>/dev/null | grep -q 200 \
       && { echo "AGENT READY"; break; } || { echo "Waiting for the agent... ($i)"; sleep 15; }
   done
   ```

1. In the Google Cloud console, navigate to **Compute Engine** > **VM instances** and select **agent-vm**. Confirm that the service account is **bank-agent-sa** and that the network tag is **agent**.

   > **Congratulations** on completing the task! Now, it's time to validate it. Here are the steps:
   >
   > - Select the **Validate** button for the corresponding task. If you receive a success message, you can proceed to the next task.
   > - If not, carefully read the error message and retry the step, following the instructions in the lab guide.
   > - If you need any assistance, please contact us at cloudlabs-support@spektrasystems.com. We are available 24/7 to help you out.

   <validation step="a53704ee-648c-4671-83fc-4a8d539a0d88" />

### Task 2: Call the deployed agent securely

1. Open a private IAP tunnel from Cloud Shell to the agent. Local port **8081** now forwards to port 8080 on the VM:

   ```bash
   nohup gcloud compute start-iap-tunnel agent-vm 8080 --local-host-port=localhost:8081 --zone=$ZONE > /tmp/iap.log 2>&1 &
   sleep 8
   ```

1. Create a conversation session:

   ```bash
   curl -s -X POST "http://localhost:8081/apps/bank_agent/users/learner/sessions/s1" \
     -H "Content-Type: application/json" -d '{}'
   ```

1. Ask the agent a question and print its final answer:

   ```bash
   curl -s -X POST "http://localhost:8081/run" \
     -H "Content-Type: application/json" \
     -d '{"app_name":"bank_agent","user_id":"learner","session_id":"s1",
          "new_message":{"role":"user","parts":[{"text":"What is the interest rate on the Everyday Saver account?"}]}}' \
     | jq -r '.[-1].content.parts[0].text'
   ```

   The agent should reply with **4.15% AER**.

   > **Note:** The VM has no open public port. Your request reached it only because IAP checked your Google identity first.

1. Wait about **1 minute** for the agent's log entry to reach Cloud Logging before you validate.

   > **Congratulations** on completing the task! Now, it's time to validate it. Here are the steps:
   >
   > - Select the **Validate** button for the corresponding task. If you receive a success message, you can proceed to the next task.
   > - If not, carefully read the error message and retry the step, following the instructions in the lab guide.
   > - If you need any assistance, please contact us at cloudlabs-support@spektrasystems.com. We are available 24/7 to help you out.

   <validation step="ed2be13a-73d2-438c-a144-f5a161b2a830" />

---

## Summary

In this lab, you have:

- Built an AI agent with the **Agent Development Kit** and **Gemini on Vertex AI**.
- Grounded the agent's answers in an approved knowledge source with a **tool** backed by **Cloud Storage**.
- Deployed the agent to a **private Compute Engine VM**, reachable only through IAP, with a dedicated, least-privilege service account.
- Verified, through the event trace and automated validation, that every figure the agent quotes comes from the knowledge base.

**Coming up on Day 2 (Builder):** connect Nova to the bank's systems through an **MCP server**.

### Select **Next >>** to continue to the Knowledge Check.
