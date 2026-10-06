<#
 CloudLabs validation | LAB01B-EX1-TASK1
 Exercise 1, Task 1: Start the incident (injects the two faults)
 Lab: Day 1 Support: Troubleshoot the Banking Agent

 Script Type : PowerShellV2      Run As : System
 Parameters  : DeploymentId = GET-DEPLOYMENT-ID (System)
               projectname  = GET-GCP-PROJECT   (System)

 Passes when:
   - always (score 0). Deploys the reference agent-vm if Lab 01A was skipped,
     then injects Fault A (no bucket read for bank-agent-sa) and
     Fault B (KB_FILE = archive/products_2023.json, VM restarted)
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

# agent-vm as JSON (any zone), or $null. Sets $script:zone.
function Get-AgentVm {
    $json = gcloud compute instances list --project $projectname --filter="name=$vmName" --format="json" 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $json) { return $null }
    $list = @($json | Out-String | ConvertFrom-Json)
    if ($list.Count -eq 0 -or -not $list[0]) { return $null }
    $script:zone = ($list[0].zone -split "/")[-1]
    Write-Host "Found $vmName in zone $script:zone (status $($list[0].status))"
    return $list[0]
}

# VM metadata as a hashtable
function Get-VmMeta($vm) {
    $m = @{}
    foreach ($i in @($vm.metadata.items)) { if ($i.key) { $m[$i.key] = $i.value } }
    return $m
}

# Knowledge-base bucket created by the deployment (nbkb-<deploymentId>)
function Get-KbBucket {
    $b = @(gcloud storage buckets list --project $projectname --format="value(name)" --filter="name~^nbkb-" 2>$null) | Where-Object { $_ }
    if ($DeploymentId -and ($b -contains "nbkb-$DeploymentId")) { return "nbkb-$DeploymentId" }
    return ($b | Select-Object -First 1)
}

# Ask the live agent on agent-vm through IAP SSH. Returns @{ Text; ToolCalled }
function Invoke-Agent([string]$Prompt) {
    $bash = @"
S=val`$RANDOM
curl -s -X POST localhost:8080/apps/bank_agent/users/validator/sessions/`$S -H 'Content-Type: application/json' -d '{}' >/dev/null
curl -s --max-time 60 -X POST localhost:8080/run -H 'Content-Type: application/json' -d '{"app_name":"bank_agent","user_id":"validator","session_id":"'`$S'","new_message":{"role":"user","parts":[{"text":"$Prompt"}]}}'
"@
    $b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(($bash -replace "`r", "")))
    $out = gcloud compute ssh $vmName --zone $script:zone --project $projectname --tunnel-through-iap --quiet --command "echo $b64 | base64 -d | bash" 2>$null | Out-String
    $start = $out.IndexOf("[")
    if ($start -lt 0) { return @{ Text = ""; ToolCalled = $false } }
    $events = $out.Substring($start) | ConvertFrom-Json
    $texts = @(); $tool = $false
    foreach ($ev in @($events)) {
        foreach ($part in @($ev.content.parts)) {
            if ($part.functionCall -and $part.functionCall.name -eq "get_product_info") { $tool = $true }
            if ($part.text) { $texts += $part.text }
        }
    }
    $last = if ($texts.Count) { $texts[-1] } else { "" }
    return @{ Text = $last; ToolCalled = $tool }
}

try {
    if (-not $projectname) { throw "The projectname parameter is empty. Map it to GET-GCP-PROJECT." }
    Write-Host "Project: $projectname | DeploymentId: $DeploymentId"
    gcloud config set project $projectname --quiet 2>$null | Out-Null

    $bucket = Get-KbBucket
    if (-not $bucket) { throw "The knowledge-base bucket (nbkb-*) was not found." }
    $staleFile = "archive/products_2023.json"
    $vm = Get-AgentVm

    if (-not $vm) {
        Write-Host "agent-vm not found - deploying the reference agent with the stale file"
        $labZone = gcloud compute instances list --project $projectname --filter="name~^labvm-" --format="value(zone.basename())" 2>$null | Select-Object -First 1
        $subnet  = gcloud compute networks subnets list --project $projectname --filter="name~^clgsubnet-" --format="value(name)" 2>$null | Select-Object -First 1
        $region  = ($labZone -replace "-[a-z]$", "")
        $startup = Join-Path ([IO.Path]::GetTempPath()) "agent-vm-startup.sh"
        Invoke-WebRequest -UseBasicParsing -Uri "https://raw.githubusercontent.com/fardeena-spektra/GCP-DEMO/refs/heads/main/deployment1/agentvmstartup.sh" -OutFile $startup
        gcloud compute instances create $vmName --project $projectname --zone $labZone --machine-type e2-medium `
            --subnet $subnet --tags agent --service-account $agentSa --scopes cloud-platform `
            --image-family debian-12 --image-project debian-cloud `
            --metadata "KB_BUCKET=$bucket,KB_FILE=$staleFile,GOOGLE_CLOUD_LOCATION=$region" `
            --metadata-from-file "startup-script=$startup" --quiet 2>&1 | Write-Host
        $created = $true
    }
    else {
        Write-Host "Fault B: pointing agent-vm at $staleFile"
        gcloud compute instances add-metadata $vmName --zone $script:zone --project $projectname --metadata "KB_FILE=$staleFile" --quiet 2>&1 | Write-Host
        $created = $false
    }

    Write-Host "Fault A: removing read access for $agentSa on gs://$bucket"
    gcloud storage buckets remove-iam-policy-binding "gs://$bucket" --member "serviceAccount:$agentSa" --role "roles/storage.objectViewer" --quiet 2>&1 | Write-Host

    if (-not $created) {
        Write-Host "Restarting agent-vm so the change takes effect"
        gcloud compute instances reset $vmName --zone $script:zone --project $projectname --quiet 2>&1 | Write-Host
    }

    $wait = if ($created) { "about 5 minutes (the reference agent is being deployed)" } else { "about 2 minutes" }
    $message = New-Result "Succeeded" "Incident INC-20431 started. Wait $wait, then continue with Task 2."
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
