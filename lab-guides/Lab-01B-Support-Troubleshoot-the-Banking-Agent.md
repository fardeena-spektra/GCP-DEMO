# Day 1 – Support Pathway: Troubleshoot the Banking Agent in Production

### Estimated Duration: 25 Minutes

### Pathway: AI Support / Engineering &nbsp;|&nbsp; Level: Foundation &nbsp;|&nbsp; Points: 150

## Lab Scenario

It's 08:45 on a Monday at Northbridge Bank. The service desk has raised a **P2 incident** against **Nova**, the customer helpdesk agent that runs on Cloud Run:

> **INC-20431 – Nova not answering product questions**
> *"Since the overnight change window, customers asking about savings rates get 'product information is temporarily unavailable'. Please investigate and restore service. Compliance reminds us that Nova must only quote rates from the current approved catalogue."*

You are the AI support engineer on call. You will use **Cloud Logging**, **IAM** and **Cloud Run** to find the root cause, fix it, verify the agent's behaviour and close the incident safely.

> **Note:** This lab runs in the **same environment** as **Day 1 – Builder Pathway (Lab 01A)**. If you did not complete Lab 01A, the reference agent has been deployed for you.

## Lab Objectives

In this lab, you will complete the following exercises:

- Exercise 1: Reproduce the incident
- Exercise 2: Diagnose and fix the knowledge-base access failure
- Exercise 3: Diagnose and fix the stale knowledge source
- Exercise 4: Verify agent behaviour and close the incident

## Lab Environment Details

| Resource | Value |
|---|---|
| Project ID | <inject key="ProjectId" enableCopy="true"/> |
| Region | **europe-west2** (London) |
| Cloud Run service | **bank-agent** |
| Knowledge-base bucket | <inject key="KbBucket" enableCopy="true"/> |
| Agent runtime service account | <inject key="AgentServiceAccount" enableCopy="true"/> |

---

## Exercise 1: Reproduce the incident

Always confirm a reported symptom yourself before changing anything in production.

### Task 1: Prepare your Cloud Shell session

1. On the lab VM desktop, double-click the **Google Cloud Console** shortcut. Sign in with the following credentials, if you are not already signed in:

   - Email/Username: <inject key="GCPUsername" enableCopy="true"/>
   - Password: <inject key="GCPPassword" enableCopy="true"/>

1. Open **Cloud Shell** and run the following commands:

   ```bash
   export PROJECT_ID=${DEVSHELL_PROJECT_ID:-$(gcloud projects list --format='value(projectId)' --limit=1)}
   export REGION=europe-west2
   export KB_BUCKET=$(gcloud storage buckets list --project=$PROJECT_ID --format='value(name)' --filter='name~^nbkb-')
   export AGENT_SA=bank-agent-sa@${PROJECT_ID}.iam.gserviceaccount.com
   gcloud config set project $PROJECT_ID
   export AGENT_URL=$(gcloud run services describe bank-agent --region=$REGION --format='value(status.url)')
   echo "Project: $PROJECT_ID | Bucket: $KB_BUCKET"
   ```

1. Create a small helper function that sends one question to Nova in a new session:

   ```bash
   ask() {
     local sid="s$RANDOM" token=$(gcloud auth print-identity-token)
     curl -s -X POST "$AGENT_URL/apps/bank_agent/users/support/sessions/$sid" \
       -H "Authorization: Bearer $token" -H "Content-Type: application/json" -d '{}' >/dev/null
     curl -s -X POST "$AGENT_URL/run" \
       -H "Authorization: Bearer $token" -H "Content-Type: application/json" \
       -d "{\"app_name\":\"bank_agent\",\"user_id\":\"support\",\"session_id\":\"$sid\",
            \"new_message\":{\"role\":\"user\",\"parts\":[{\"text\":\"$1\"}]}}" \
       | jq -r '.[-1].content.parts[0].text'
   }
   ```

### Task 2: Reproduce the customer-reported symptom

1. Ask Nova the same question that customers are asking:

   ```bash
   ask "What is the interest rate on the Everyday Saver account?"
   ```

1. Confirm that Nova responds that product information is **temporarily unavailable**. The agent itself is up and the model is responding, so the failure is somewhere in the **tool path**.

---

## Exercise 2: Diagnose and fix the knowledge-base access failure

### Task 1: Find the error in Cloud Logging

1. In the Google Cloud console, navigate to **Logging** > **Logs Explorer**.

1. Turn on **Show query**, paste the following query and select **Run query**:

   ```
   resource.type="cloud_run_revision"
   resource.labels.service_name="bank-agent"
   jsonPayload.message="KB_READ_FAILED"
   ```

1. Expand the most recent entry and review the `jsonPayload.error` field. You should see a **403** error stating that `bank-agent-sa@...` does not have **storage.objects.get** access to the bucket.

   > **Note:** You can run the same query from Cloud Shell:
   >
   > `gcloud logging read 'resource.type="cloud_run_revision" AND resource.labels.service_name="bank-agent" AND jsonPayload.message="KB_READ_FAILED"' --limit=3 --format='value(jsonPayload.error)'`

1. Check which identity the service runs as, then check who can read the bucket:

   ```bash
   gcloud run services describe bank-agent --region=$REGION --format='value(spec.template.spec.serviceAccountName)'
   gcloud storage buckets get-iam-policy gs://$KB_BUCKET --format=json | jq '.bindings'
   ```

   **Root cause #1:** the agent's runtime service account no longer has read access to the knowledge-base bucket.

### Task 2: Restore least-privilege access

1. Grant the runtime identity **read-only** access to **this bucket only**. Do not grant project-wide access.

   ```bash
   gcloud storage buckets add-iam-policy-binding gs://$KB_BUCKET \
     --member="serviceAccount:$AGENT_SA" --role="roles/storage.objectViewer"
   ```

1. Wait about **60 seconds** for the IAM change to propagate.

   > **Congratulations** on completing the task! Now, it's time to validate it. Here are the steps:
   >
   > - Select the **Validate** button for the corresponding task. If you receive a success message, you can proceed to the next task.
   > - If not, carefully read the error message and retry the step, following the instructions in the lab guide.
   > - If you need any assistance, please contact us at cloudlabs-support@spektrasystems.com. We are available 24/7 to help you out.

   <validation step="LAB01B-EX2-TASK2" />

---

## Exercise 3: Diagnose and fix the stale knowledge source

### Task 1: Re-test, and don't stop at "it works"

1. Ask Nova the question again:

   ```bash
   ask "What is the interest rate on the Everyday Saver account?"
   ```

1. Nova now answers confidently. Compare the rate it quotes with the approved catalogue you saw in Lab 01A (**4.15% AER**):

   ```bash
   gcloud storage cat gs://$KB_BUCKET/products.json | jq '.version, .products[0].rate_aer'
   ```

   Nova is quoting **3.10%**, which is wrong. An agent that answers confidently with incorrect data is a more serious compliance risk than an agent that is down.

1. Find out which knowledge file the agent is actually reading. Run the following query in **Logs Explorer**:

   ```
   resource.type="cloud_run_revision"
   resource.labels.service_name="bank-agent"
   jsonPayload.message="KB_LOOKUP"
   ```

   Expand the latest entry and review `jsonPayload.file` and `jsonPayload.kb_version`. The agent is reading `archive/products_2023.json` (version **2023-04**).

1. Confirm the misconfiguration on the service:

   ```bash
   gcloud run services describe bank-agent --region=$REGION --format=json \
     | jq '.spec.template.spec.containers[0].env'
   ```

   **Root cause #2:** the overnight change re-pointed `KB_FILE` at the archived 2023 catalogue.

### Task 2: Point the agent at the approved catalogue

1. Update the service configuration. This change creates a new Cloud Run revision:

   ```bash
   gcloud run services update bank-agent --region=$REGION --update-env-vars=KB_FILE=products.json
   ```

   > **Congratulations** on completing the task! Now, it's time to validate it. Here are the steps:
   >
   > - Select the **Validate** button for the corresponding task. If you receive a success message, you can proceed to the next task.
   > - If not, carefully read the error message and retry the step, following the instructions in the lab guide.
   > - If you need any assistance, please contact us at cloudlabs-support@spektrasystems.com. We are available 24/7 to help you out.

   <validation step="LAB01B-EX3-TASK2" />

---

## Exercise 4: Verify agent behaviour and close the incident

### Task 1: Run a quick behaviour check

1. Run this mini evaluation set. It covers a factual answer, a second product and an out-of-scope request that Nova should decline:

   ```bash
   for q in "What is the interest rate on the Everyday Saver account?" \
            "Do you charge a fee for using my debit card abroad?" \
            "Which stock should I buy this week?"; do
     echo "Q: $q"; echo "A: $(ask "$q")"; echo "---"
   done
   ```

1. Confirm the following expected behaviour:

   | Question | Expected |
   |---|---|
   | Everyday Saver rate | **4.15% AER** (current catalogue) |
   | Debit card abroad | **0%** fee |
   | Stock tip | Politely declines; doesn't invent advice |

1. In **Logs Explorer**, re-run the `KB_LOOKUP` query and confirm that the newest entries show `kb_version: 2026-10` and that no new `KB_READ_FAILED` entries appear.

   > **Congratulations** on completing the task! Now, it's time to validate it. Here are the steps:
   >
   > - Select the **Validate** button for the corresponding task. If you receive a success message, you can proceed to the next task.
   > - If not, carefully read the error message and retry the step, following the instructions in the lab guide.
   > - If you need any assistance, please contact us at cloudlabs-support@spektrasystems.com. We are available 24/7 to help you out.

   <validation step="LAB01B-EX4-TASK1" />

### Task 2: Record the resolution

1. Write a short resolution note for **INC-20431** in your lab notes, using this format:

   - **Symptom:** what customers saw
   - **Root cause(s):** the two causes and how you proved each one
   - **Fix:** the commands you ran, and why the access fix is least-privilege
   - **Prevention:** one control that would have caught this before customers did

   > **Hint:** Consider an alert on `KB_READ_FAILED` log entries, or a post-deployment check that compares the `kb_version` in the logs with the approved catalogue version.

---

## Summary

In this lab, you have:

- Reproduced a production incident on a deployed AI agent before making any changes.
- Used **structured logs in Cloud Logging** to trace a failure to an **IAM** root cause, and restored **least-privilege** access.
- Identified a more dangerous **silent failure**: confident answers grounded in a **stale knowledge source**.
- Verified the fix with a behaviour check before closing the incident.

**Coming up on Day 2 (Support):** set up log-based **alerting and dashboards** for Nova, so the next incident is caught before customers notice it.

### You have successfully completed the lab. Select **Next >>** to continue to the Day 1 leaderboard.
