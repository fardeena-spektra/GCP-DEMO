# Demo Run-Sheet: Fast Lane × CloudLabs, GCP AI Engineering Lab Experience

**Call:** Tuesday 6 Oct 2026 | **Audience:** Fred Jewell (Head of Sales), Simon Keeble (Operations Director), Fast Lane
**CloudLabs team:** Mir Taqi (AM), Akhil Dixit (Pre-Sales), Suraj (Lab build/demo)
**Goal:** Show that CloudLabs can deliver their 24-lab, two-pathway "12 Days" programme at scale (white-labelled, auto-scored and reusable) using a live Day 1 pair of labs that share one environment.

---

## 1. Build checklist (today)

| # | Item | Owner | Done |
|---|---|---|---|
| 1 | Create GCP lab template: isolated project per learner, region **europe-west2** | Suraj | ☐ |
| 2 | Attach `scripts/setup-environment.sh` as post-provisioning script; map outputs to `KbBucket`, `AgentServiceAccount`, `ProjectId`, `GCPUsername`, `GCPPassword` inject keys | Suraj | ☐ |
| 3 | Check Vertex AI **gemini-2.5-flash** quota/access in europe-west2 on the lab subscription | Suraj | ☐ |
| 4 | Create **Lab 01A** and **Lab 01B** on the same environment template; attach `inject-fault-lab01b.sh` as the 01B start action | Suraj | ☐ |
| 5 | Load the lab guides; wire the 5 `<validation step=…>` IDs to `validation/*.py` tasks (see the table below) | Suraj | ☐ |
| 6 | Apply **Fast Lane branding** (logo, colours, portal name, e.g. "Fast Lane AI Academy") | Suraj | ☐ |
| 7 | Course structure: "12 Days of AI" with **two tracks** (Builder / Support), Day 1 unlocked, Days 2–12 shown as locked placeholders | Suraj | ☐ |
| 8 | Enable points and the **leaderboard**; seed 8–10 test learners with varied scores so the leaderboard looks real | Suraj | ☐ |
| 9 | Full dry run of 01A → 01B end to end, timing each step | Suraj + Akhil | ☐ |
| 10 | **Backup instance:** one environment with 01A already completed (agent deployed), plus one with 01B faults injected | Suraj | ☐ |

**Validation wiring**

| Guide step ID | Script and task | Points |
|---|---|---|
| LAB01A-EX3-TASK1 | `validate_lab01a.py --task ex3-task1` | 50 |
| LAB01A-EX3-TASK2 | `validate_lab01a.py --task ex3-task2` | 50 |
| LAB01B-EX2-TASK2 | `validate_lab01b.py --task ex2-task2` | 50 |
| LAB01B-EX3-TASK2 | `validate_lab01b.py --task ex3-task2` | 50 |
| LAB01B-EX4-TASK1 | `validate_lab01b.py --task ex4-task1` | 50 |

---

## 2. Demo flow (about 35 min, leaving time for commercials)

| Time | Segment | What to show | Fast Lane ask it answers |
|---|---|---|---|
| 0–3 | Frame | Restate their brief: 24 labs, 2 pathways, shared environments, 100–500+ learners, Fast Lane keeps customer + IP | — |
| 3–7 | **Branded learner portal** | Fast Lane-branded landing page; "12 Days of AI" with both tracks; Day 1 unlocked | White-label · Self-service |
| 7–15 | **Lab 01A – Builder** (backup instance) | Lab guide side-by-side with the console; walk through `agent.py` (tool + guardrail); ADK Dev UI **Events** trace showing the functionCall → grounded 4.15% answer; Cloud Run service is private and runs as its own SA | GCP provisioning & isolation · AI/agent scenarios |
| 15–16 | **Auto-validation** | Click **Validate** → success; show a failure message example (e.g. wrong SA) | Automated validation & scoring · no manual marking |
| 16–24 | **Lab 01B – Support** (fault-injected instance) | Same project, now broken: "unavailable" → Logs Explorer 403 → fix IAM → agent now *confidently wrong* (3.10%) → `KB_LOOKUP` log shows archived file → fix → validate | Support pathway · troubleshooting · evaluating agent behaviour · **content reuse/branching between roles** |
| 24–28 | **Progress & leaderboard** | Learner progress dashboard, points, leaderboard, admin/cohort view, bulk enrolment | Progress tracking · gamification · scale |
| 28–32 | **Scale & operations** | Per-learner project isolation, auto-cleanup, cost controls; concurrency figures for 500+ learners | 100–500+ learners · self-service at scale |
| 32–35 | **Build model & IP** | Guides are Markdown in Git, environment as scripts, validators as code. Fast Lane owns and can export them; updates roll out by template version | Update/maintain · retain/export IP |

**Key talking points**

- **One environment, two journeys.** The Support lab reuses the Builder lab's environment plus a fault-injection script. Across 12 days that is far less to build and maintain than 24 independent labs, which addresses their commercial-efficiency point.
- **Zero manual intervention.** Provisioning, fault injection (including auto-deploying the reference agent for learners who skipped 01A), scoring and teardown are all automated.
- **FS-appropriate by design.** London region, private services, least-privilege identities, grounded answers and audit logs.
- **Roadmap preview (Days 2–12):** MCP tool servers · Vertex AI Search grounding · agent-to-agent · Agent Engine deployment · evaluation pipelines · monitoring/alerting · production-readiness.

---

## 3. Risks and fallbacks

| Risk | Mitigation |
|---|---|
| Cloud Run source deploy takes 3–5 min live | Don't deploy live. Use the backup instance and walk through the already-deployed service. |
| Gemini latency or quota error during the demo | Pre-warm the service 10 min before the call (run the `ask` helper twice). Keep a screenshot of the Events trace. |
| ADK Dev UI won't load through Cloud Shell Web Preview | Fall back to `adk run bank_agent` in the terminal, or the curl call. |
| IAM fix not yet propagated when re-testing in 01B | Talk through the log query for about 60 s before re-asking. |
| **Gemini 2.5 Flash retires around 16 Oct 2026** | Fine for the demo. For the real programme, switch `AGENT_MODEL` to **Gemini 3 Flash** after confirming it's available in europe-west2. Worth mentioning proactively as an example of "how labs are maintained". |

---

## 4. Questions to ask Fast Lane

1. Delivery window and learner volume per day (peak concurrency drives the GCP quota plan)?
2. Will the customer's own GCP organisation be used, or CloudLabs-hosted projects?
3. Data residency or security requirements from the FS customer (UK-only regions, SSO, LMS/SCORM integration)?
4. Mix of self-service, expert-coach and facilitated cohorts?
5. Who authors content: Fast Lane SMEs, CloudLabs, or co-development? Preferred IP handover format?
6. Leaderboard scope: individual, team, or departmental?
