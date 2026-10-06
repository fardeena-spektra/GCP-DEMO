<#
 CloudLabs validation | LAB01A-EX1-TASK1
 Exercise 1, Task 1: Prepare your lab environment
 Lab: Day 1 Builder: Build Your First Banking Agent

 Script Type : PowerShellV2      Run As : System
 Parameters  : DeploymentId = GET-DEPLOYMENT-ID (System)
               projectname  = GET-GCP-PROJECT   (System)

 Passes when:
   - the lab setup completes (safe to click again):
     Service Usage + lab APIs on, knowledge files uploaded,
     bank-agent-sa can read the bucket, use Gemini and write logs
#>
param(
    [string]$DeploymentId,
    [string]$projectname
)

$vmName  = "agent-vm"
$agentSa = "bank-agent-sa@$projectname.iam.gserviceaccount.com"
$zone    = ""
$message = $null

function New-Result([string]$Status, [string]$Message) {
    @{ Status = $Status; Message = $Message } | ConvertTo-Json
}

# Knowledge-base bucket created by the deployment (nbkb-<deploymentId>)
function Get-KbBucket {
    $b = @(gcloud storage buckets list --project $projectname --format="value(name)" --filter="name~^nbkb-" 2>$null) | Where-Object { $_ }
    if ($DeploymentId -and ($b -contains "nbkb-$DeploymentId")) { return "nbkb-$DeploymentId" }
    return ($b | Select-Object -First 1)
}

# Lab setup, safe to run many times: APIs, knowledge files, agent permissions
function Invoke-LabPrep {
    $repo = "https://raw.githubusercontent.com/fardeena-spektra/GCP-DEMO/refs/heads/main/assets"
    $failed = @()

    Write-Host "[1/5] Turning on Service Usage, then the lab APIs"
    gcloud services enable serviceusage.googleapis.com --project $projectname --quiet 2>&1 | Write-Host
    if ($LASTEXITCODE -ne 0) { $failed += "Service Usage API" }
    $apis = @("aiplatform.googleapis.com", "compute.googleapis.com", "iap.googleapis.com", "storage.googleapis.com",
              "logging.googleapis.com", "iam.googleapis.com", "cloudresourcemanager.googleapis.com")
    gcloud services enable $apis --project $projectname --async --quiet 2>&1 | Write-Host
    if ($LASTEXITCODE -ne 0) { $failed += "lab APIs" }

    Write-Host "[2/5] Knowledge-base bucket"
    $bucket = Get-KbBucket
    if (-not $bucket) { return @{ Ok = $false; Text = "The knowledge-base bucket (nbkb-*) was not found. The lab deployment may still be running." } }
    Write-Host "      gs://$bucket"

    Write-Host "[3/5] Uploading the knowledge files"
    $tmp = [IO.Path]::GetTempPath()
    foreach ($f in @("products.json", "archive/products_2023.json")) {
        $local = Join-Path $tmp ($f.Replace("/", "_"))
        Invoke-WebRequest -UseBasicParsing -Uri "$repo/$f" -OutFile $local
        gcloud storage cp $local "gs://$bucket/$f" --project $projectname --quiet 2>&1 | Write-Host
        if ($LASTEXITCODE -ne 0) { $failed += "upload $f" }
    }

    Write-Host "[4/5] Agent can read this bucket only"
    gcloud storage buckets add-iam-policy-binding "gs://$bucket" --member "serviceAccount:$agentSa" --role "roles/storage.objectViewer" --quiet 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { $failed += "bucket read for bank-agent-sa" }

    Write-Host "[5/5] Agent can use Gemini and write logs"
    foreach ($role in @("roles/aiplatform.user", "roles/logging.logWriter")) {
        gcloud projects add-iam-policy-binding $projectname --member "serviceAccount:$agentSa" --role $role --condition=None --quiet 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { $failed += $role }
    }

    if ($failed.Count -gt 0) { return @{ Ok = $false; Text = "Setup incomplete: " + ($failed -join ", ") + ". Please validate again in a minute." } }
    return @{ Ok = $true; Text = "Lab environment ready: services turned on, knowledge files uploaded to gs://$bucket, agent permissions set." }
}

try {
    if (-not $projectname) { throw "The projectname parameter is empty. Map it to GET-GCP-PROJECT." }
    Write-Host "Project: $projectname | DeploymentId: $DeploymentId"
    gcloud config set project $projectname --quiet 2>$null | Out-Null

    $prep = Invoke-LabPrep
    if ($prep.Ok) { $message = New-Result "Succeeded" $prep.Text }
    else { $message = New-Result "Failed" $prep.Text }
}
catch {
    Write-Host "`nERROR:"
    Write-Host $_
    $message = New-Result "Failed" "The check could not complete. Please wait a minute and validate again. Details: $_"
}

Write-Host "`n=== FINAL RESPONSE ==="
Write-Host $message

Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
    StatusCode = [System.Net.HttpStatusCode]::OK
    Body       = $message
})
