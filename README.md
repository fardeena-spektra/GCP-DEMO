# Fast Lane GCP AI Engineering: Day 1 Lab Package (CloudLabs)

Two linked labs that share **one GCP project per learner**:

- **Lab 01A, Builder:** build an AI agent (ADK + Gemini) with a Cloud Storage tool and deploy it to Cloud Run.
- **Lab 01B, Support:** troubleshoot the same agent (IAM 403 and a stale knowledge source).

## Package contents

| Path | Purpose |
|---|---|
| `deployment/param.yaml` | CloudLabs parameters (same wrapper as the standard GCP VM template) |
| `deployment/deployment.yaml` | VPC, subnet, firewalls, Windows lab VM, knowledge-base bucket, agent service account, bucket read access |
| `scripts/setup-environment.sh` | Post-deployment: APIs, knowledge files, Vertex AI role, Cloud Run deploy prerequisites |
| `scripts/inject-fault-lab01b.sh` | Lab 01B start action: deploys the reference agent if missing, then injects 2 faults |
| `validation/` | Python validators for the 5 Validate buttons |
| `lab-guides/` | Lab 01A and Lab 01B guides |
| `assets/`, `solution/` | Knowledge files and reference agent (already embedded in the scripts) |
| `DEMO-RUN-SHEET.md` | Demo flow and fallbacks |

## Onboarding steps

1. **Template:** upload `deployment/param.yaml` and `deployment/deployment.yaml`. Set the region to **europe-west2** and use a per-learner project.
2. **Bootstrap (automatic):** `deployment.yaml` creates `setupvm-<deploymentId>`, which downloads `scripts/setup-environment.sh` from GitHub, runs it once and then stops itself. Log: `/var/log/cloudlabs-setup.log` on that VM.
3. **Lab 01B start action:** run `scripts/inject-fault-lab01b.sh` with `PROJECT_ID`. The runner needs `gcloud`, `pip` and Python 3.10+.
4. **VM configuration** (web-based RDP), same as the standard template:

    | Field | Output |
    |---|---|
    | Name | `labvm-{GET-DEPLOYMENT-ID}` |
    | Type | RDP |
    | Server DNS Name | `vmPublicIp` |
    | Server Username | `vmUsername` |
    | Server Password | `vmPassword` |
    | Private IP | `vmPrivateIp` |
    | VPC ID | `vpcId` |
    | Subnet ID | `subnetId` |

5. **Lab guide inject keys:**

    | Inject key | Source |
    |---|---|
    | `ProjectId`, `KbBucket`, `AgentServiceAccount` | Deployment outputs |
    | `GCPUsername`, `GCPPassword` | CloudLabs learner identity |

6. **Validation:** wire each guide step ID to its script and task. Validators run as an identity with Owner (or Viewer + Cloud Run Invoker) on the learner project and print `{"status": "Succeeded" | "Failed", "message": "..."}`.

    | Guide step ID | Command | Points |
    |---|---|:---:|
    | `LAB01A-EX3-TASK1` | `python validate_lab01a.py --task ex3-task1 --project <PROJECT_ID>` | 50 |
    | `LAB01A-EX3-TASK2` | `python validate_lab01a.py --task ex3-task2 --project <PROJECT_ID>` | 50 |
    | `LAB01B-EX2-TASK2` | `python validate_lab01b.py --task ex2-task2 --project <PROJECT_ID>` | 50 |
    | `LAB01B-EX3-TASK2` | `python validate_lab01b.py --task ex3-task2 --project <PROJECT_ID>` | 50 |
    | `LAB01B-EX4-TASK1` | `python validate_lab01b.py --task ex4-task1 --project <PROJECT_ID>` | 50 |

## Notes

- **Model:** `gemini-2.5-flash` (override with `AGENT_MODEL`). Gemini 2.5 Flash retires around 16 Oct 2026, so switch to Gemini 3 Flash for the real programme.
- **Bucket name:** `nbkb-<deploymentId>`. The guides and validators find it automatically.
- **VM size:** `e2-standard-2` (the sample used `e2-medium`, which is slow for the Cloud Console in Edge).
