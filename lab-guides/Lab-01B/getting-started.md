<h1 align="center">🤖 Day 1 Support: Troubleshoot the Banking Agent</h1>
<p align="center"><b>Fast Lane AI Academy</b> | <b>Support Pathway</b> | ⏱️ <b>Estimated Timing: 25 Minutes</b> | 🏆 <b>Points: 150</b></p>

---

## 🎯 About This Lab

Nova, the Northbridge Bank helpdesk agent built in the Builder lab, is now in production on **Cloud Run**. After an overnight change, customers report that it can no longer answer product questions.

In this lab, you act as the on-call AI support engineer. You use **Cloud Logging**, **IAM** and **Cloud Run** to find the root causes, fix them, verify the agent's behaviour and close the incident safely. This lab runs in the same environment as the Builder lab.

**In this lab, you will:**

1. 🔁 Reproduce the reported incident.
1. 🔐 Diagnose and fix a knowledge-base access failure.
1. 🗂️ Diagnose and fix a stale knowledge source.
1. ✅ Verify the agent's behaviour and close the incident.

---

## 🖥️ Lab Environment

The lab window is split into two parts:

- **Left side:** your lab virtual machine (VM), a Windows workstation with a browser.
- **Right side:** the lab guide, with the steps to complete each task.

![Lab layout](./media/images/gs-lab-layout.png)

Your environment is an **isolated Google Cloud project** created only for you. It has been pre-provisioned with:

| Resource | Value |
|---|---|
| ☁️ **Project ID** | <inject key="ProjectId" enableCopy="true"/> |
| 🌍 **Region** | **europe-west2** (London) |
| 🗂️ **Knowledge-base bucket** | <inject key="KbBucket" enableCopy="true"/> |
| 🔐 **Agent service account** | <inject key="AgentServiceAccount" enableCopy="true"/> |

---

## 🧭 Lab Window Controls

![Lab window controls](./media/images/gs-topbar.png)

| # | Control | Use |
|:---:|---|---|
| 1 | **VM selector** | Shows the lab VM you are connected to. |
| 2 | **Timer** | Time remaining in your lab session. |
| 3 | **Progress bar** | Your progress through the lab. |
| 4 | **A↕** | Change the text size of the lab guide. |
| 5 | **Refresh** | Reconnect the VM if the screen stops responding. |
| 6 | **More (...)** | Language, Delete and VM Native Clipboard options. |
| 7 | **Lab guide menu** | Guide, Environment, Progress, Resources and Help. |
| 8 | **Split window** | Split the lab guide and the VM into separate windows. |

### 6️⃣ More Options

| Option | Use |
|---|---|
| 🌍 **Language** | Switch the lab language, if multi-language support is enabled. |
| 🗑️ **Delete** | Delete the environment once your lab is complete. |
| 📋 **VM Native Clipboard** | Allows copying files within the VM. While it is on, text copied from your local PC cannot be pasted into the VM using keyboard shortcuts. You can turn it off at any time from **More (...)**. |

### 7️⃣ Lab Guide Menu

| Option | Use |
|---|---|
| 📖 **Guide** | All tasks and lab information. |
| 🔑 **Environment** | All required credentials and lab details. |
| 📈 **Progress** | Your points for validations. |
| ⚙️ **Resources** | Start and stop the lab VM. |
| ❓ **Help** | Support information. |

---

## 🔐 Sign In to Google Cloud

1. On the lab VM desktop, double-click the **Google Cloud Console** shortcut.
1. Sign in with the following credentials:

    | Detail | Value |
    |---|---|
    | 👤 **Username** | <inject key="GCPUsername" enableCopy="true"/> |
    | 🔒 **Password** | <inject key="GCPPassword" enableCopy="true"/> |

1. If prompted, accept the **Terms of Service**.
1. From the project selector, select your project <inject key="ProjectId" enableCopy="false"/>.

> ⚠️ **Note:** Use only the credentials above. Do not sign in with a personal Google account.

---

## ✅ Validate Your Work

1. Complete the task.
1. Scroll to the **Validation Check** under the task.
1. Click **Validate**.

![Validate button](./media/images/gs-validate.png)

- On success, the status shows **Success** and the points are added to your **Progress**.
- If a check fails, read the message, fix the issue and click **Validate** again.

---

## 🆘 Support Contact

The CloudLabs support team is available 24/7 via email and live chat.

- 📧 **Email:** <a href="mailto:cloudlabs-support@spektrasystems.com">cloudlabs-support@spektrasystems.com</a>
- 💬 **Live chat:** <a href="https://support.cloudlabs.ai/isv">https://support.cloudlabs.ai/isv</a>

---

Click **Next** to begin the lab.

## 🎉 Happy Labbing!
