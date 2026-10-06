#!/bin/bash
# =============================================================================
# Startup script for agent-vm (Compute Engine). Runs on every boot.
# - first boot: installs Python + ADK, downloads the agent code
# - every boot: reads KB_BUCKET / KB_FILE from VM metadata, (re)starts the agent
# - ships the agent's JSON logs (KB_LOOKUP, KB_READ_FAILED) to Cloud Logging
#   under the log name "bank-agent"
# Agent API: http://localhost:8080 (reachable only through IAP)
# Setup log: /var/log/agent-setup.log
# =============================================================================
exec >> /var/log/agent-setup.log 2>&1
echo "[agent] boot `date -u`"
md()   { curl -s -H "Metadata-Flavor: Google" "http://metadata.google.internal/computeMetadata/v1/$1"; }
attr() { md "instance/attributes/$1"; }

PROJECT="`md project/project-id`"
KB_BUCKET="`attr KB_BUCKET`"
KB_FILE="`attr KB_FILE`"; [ -z "$KB_FILE" ] && KB_FILE=products.json
LOCATION="`attr GOOGLE_CLOUD_LOCATION`"
REF=https://raw.githubusercontent.com/fardeena-spektra/GCP-DEMO/refs/heads/main/solution/bank_agent
APP=/opt/agent/app

# 1. Python + ADK (first boot only)
if [ ! -x /opt/agent/venv/bin/adk ]; then
  echo "[agent] installing Python and ADK"
  apt-get update -y && apt-get install -y python3-venv
  python3 -m venv /opt/agent/venv
  /opt/agent/venv/bin/pip install -q --upgrade pip google-adk google-cloud-storage
fi

# 2. Agent code (first boot only): learner upload in the bucket, else the reference agent
if [ ! -f "$APP/bank_agent/agent.py" ]; then
  mkdir -p "$APP"
  if gcloud storage cp -r "gs://$KB_BUCKET/app/bank_agent" "$APP/"; then
    echo "[agent] code copied from gs://$KB_BUCKET/app/bank_agent"
  else
    echo "[agent] no uploaded code, using the reference agent"
    mkdir -p "$APP/bank_agent"
    curl -fsSL "$REF/agent.py" -o "$APP/bank_agent/agent.py"
    echo "from . import agent" > "$APP/bank_agent/__init__.py"
  fi
fi
rm -f "$APP/bank_agent/.env"

# 3. Settings from VM metadata (every boot)
cat > /etc/bank-agent.env <<ENV
GOOGLE_GENAI_USE_VERTEXAI=TRUE
GOOGLE_CLOUD_PROJECT=$PROJECT
GOOGLE_CLOUD_LOCATION=$LOCATION
KB_BUCKET=$KB_BUCKET
KB_FILE=$KB_FILE
ENV
echo "[agent] KB_BUCKET=$KB_BUCKET KB_FILE=$KB_FILE LOCATION=$LOCATION"

# 4. Agent service + log shipper
cat > /etc/systemd/system/bank-agent.service <<UNIT
[Unit]
Description=Northbridge banking agent (ADK API server)
After=network-online.target
[Service]
EnvironmentFile=/etc/bank-agent.env
ExecStart=/opt/agent/venv/bin/adk api_server --host 0.0.0.0 --port 8080 $APP
Restart=always
[Install]
WantedBy=multi-user.target
UNIT
cat > /usr/local/bin/bank-agent-logs.sh <<'SHIP'
#!/bin/bash
journalctl -u bank-agent -f -n 0 -o cat | while read -r line; do
  case "$line" in
    \{*\"message\"*) gcloud logging write bank-agent "$line" --payload-type=json >/dev/null 2>&1 ;;
  esac
done
SHIP
chmod +x /usr/local/bin/bank-agent-logs.sh
cat > /etc/systemd/system/bank-agent-logs.service <<UNIT
[Unit]
Description=Ship bank-agent JSON logs to Cloud Logging
After=bank-agent.service
[Service]
ExecStart=/usr/local/bin/bank-agent-logs.sh
Restart=always
[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
systemctl enable bank-agent bank-agent-logs >/dev/null 2>&1
systemctl restart bank-agent bank-agent-logs
echo "[agent] AGENT STARTED `date -u`"
