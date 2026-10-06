P=$(gcloud config get-value project 2>/dev/null)
echo "==== [1/5] Project: $P ===="
echo "==== [2/5] Services turned on ===="
gcloud services list --enabled --format="value(config.name)" | grep -E "serviceusage|aiplatform|compute|iap|logging|^storage.googleapis" | sort
echo "==== [3/5] Rate files in the bucket ===="
B=$(gcloud storage buckets list --format='value(name)' --filter='name~^nbkb-'); echo "Bucket: $B"
gcloud storage ls -r gs://$B
gcloud storage cat gs://$B/products.json | grep -E '"version"|rate_aer' | head -2
gcloud storage cat gs://$B/archive/products_2023.json | grep -E '"version"' | head -1
echo "==== [4/5] Chatbot account permissions ===="
gcloud projects get-iam-policy $P --flatten="bindings[].members" --filter="bindings.members:bank-agent-sa" --format="value(bindings.role)"
gcloud storage buckets get-iam-policy gs://$B --format=json | python3 -c "
import sys,json
for b in json.load(sys.stdin).get('bindings',[]):
    if any('bank-agent-sa' in m for m in b['members']): print(b['role'])"
echo "==== [5/5] VMs and IAP firewall rule ===="
gcloud compute instances list --format="table(name,status)"
gcloud compute firewall-rules list --filter="name~^allow-iap-agent" --format="value(name)"
