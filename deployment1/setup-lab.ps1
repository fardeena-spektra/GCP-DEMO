$projectname = $projectname

$repo    = "https://raw.githubusercontent.com/fardeena-spektra/GCP-DEMO/refs/heads/main/assets"
$agentSa = "bank-agent-sa@$projectname.iam.gserviceaccount.com"

$apis = @(
    "aiplatform.googleapis.com",
    "run.googleapis.com",
    "cloudbuild.googleapis.com",
    "artifactregistry.googleapis.com",
    "storage.googleapis.com",
    "logging.googleapis.com",
    "iam.googleapis.com",
    "compute.googleapis.com",
    "iap.googleapis.com"
)

$agentRoles = @(
    "roles/aiplatform.user",
    "roles/logging.logWriter"
)

gcloud config set project $projectname --quiet

# 1. Enable the APIs the labs need
foreach ($api in $apis) {
    gcloud services enable $api --project $projectname --quiet | Out-Null
    if ($LASTEXITCODE -eq 0) { Write-Host "SUCCESS: Enabled $api" -ForegroundColor Green }
    else { Write-Host "FAILED: $api" -ForegroundColor Red }
}

# 2. Find the knowledge-base bucket and its region
$bucket = gcloud storage buckets list --project $projectname --format="value(name)" --filter="name~^nbkb-" | Select-Object -First 1
$region = (gcloud storage buckets describe "gs://$bucket" --format="value(location)").ToLower()
Write-Host "Bucket: $bucket | Region: $region"

# 3. Upload the knowledge files
$tmp = [IO.Path]::GetTempPath()
Invoke-WebRequest -UseBasicParsing -Uri "$repo/products.json" -OutFile (Join-Path $tmp "products.json")
Invoke-WebRequest -UseBasicParsing -Uri "$repo/archive/products_2023.json" -OutFile (Join-Path $tmp "products_2023.json")
gcloud storage cp (Join-Path $tmp "products.json") "gs://$bucket/products.json" --quiet | Out-Null
if ($LASTEXITCODE -eq 0) { Write-Host "SUCCESS: Uploaded products.json" -ForegroundColor Green } else { Write-Host "FAILED: products.json" -ForegroundColor Red }
gcloud storage cp (Join-Path $tmp "products_2023.json") "gs://$bucket/archive/products_2023.json" --quiet | Out-Null
if ($LASTEXITCODE -eq 0) { Write-Host "SUCCESS: Uploaded archive/products_2023.json" -ForegroundColor Green } else { Write-Host "FAILED: archive/products_2023.json" -ForegroundColor Red }

# 4. Agent identity: read this bucket only + project roles
gcloud storage buckets add-iam-policy-binding "gs://$bucket" --member "serviceAccount:$agentSa" --role "roles/storage.objectViewer" --quiet | Out-Null
if ($LASTEXITCODE -eq 0) { Write-Host "SUCCESS: $agentSa can read gs://$bucket" -ForegroundColor Green } else { Write-Host "FAILED: bucket read for $agentSa" -ForegroundColor Red }

foreach ($role in $agentRoles) {
    gcloud projects add-iam-policy-binding $projectname --member "serviceAccount:$agentSa" --role $role --condition=None --quiet | Out-Null
    if ($LASTEXITCODE -eq 0) { Write-Host "SUCCESS: Assigned $role to $agentSa" -ForegroundColor Green }
    else { Write-Host "FAILED: $role" -ForegroundColor Red }
}

# 5. Cloud Build can build source deployments (Cloud Run route)
$projectNumber = gcloud projects describe $projectname --format="value(projectNumber)"
gcloud projects add-iam-policy-binding $projectname --member "serviceAccount:$projectNumber-compute@developer.gserviceaccount.com" --role "roles/cloudbuild.builds.builder" --condition=None --quiet | Out-Null
if ($LASTEXITCODE -eq 0) { Write-Host "SUCCESS: Cloud Build role for the compute service account" -ForegroundColor Green } else { Write-Host "FAILED: Cloud Build role" -ForegroundColor Red }

gcloud artifacts repositories create cloud-run-source-deploy --repository-format docker --location $region --project $projectname --quiet | Out-Null
if ($LASTEXITCODE -eq 0) { Write-Host "SUCCESS: Artifact Registry repo in $region" -ForegroundColor Green } else { Write-Host "INFO: Artifact Registry repo already exists or not needed" }
