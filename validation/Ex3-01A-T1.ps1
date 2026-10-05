<#
 CloudLabs validation | LAB01A-EX3-TASK1
 Exercise 3, Task 1: Deploy and configure the service
 Lab: Day 1 Builder: Build Your First Banking Agent

 Script Type : PowerShellV2      Run As : System
 Parameters  : projectname = GET-GCP-PROJECT (System)

 Passes when:
   - Cloud Run service bank-agent exists in europe-west2 and has a URL
   - it runs as bank-agent-sa
   - KB_BUCKET is the nbkb-* bucket and KB_FILE is products.json
#>
param(
    [string]$projectname
)

$region  = "europe-west2"
$service = "bank-agent"
$agentSa = "bank-agent-sa@$projectname.iam.gserviceaccount.com"
$message = $null

function New-Result([string]$Status, [string]$Message) {
    @{ Status = $Status; Message = $Message } | ConvertTo-Json
}

# Cloud Run service as JSON, or $null if it does not exist
function Get-AgentService {
    $json = gcloud run services describe $service --region $region --project $projectname --format="json" 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $json) { return $null }
    return ($json | Out-String | ConvertFrom-Json)
}

# Environment variables on the service, as a hashtable
function Get-ServiceEnv($svc) {
    $envMap = @{}
    foreach ($c in @($svc.spec.template.spec.containers)) {
        foreach ($e in @($c.env)) { if ($e.name) { $envMap[$e.name] = $e.value } }
    }
    return $envMap
}

# Knowledge-base bucket created by the deployment (nbkb-<deploymentId>)
function Get-KbBucket {
    $b = gcloud storage buckets list --project $projectname --format="value(name)" --filter="name~^nbkb-" 2>$null
    return (@($b) | Where-Object { $_ } | Select-Object -First 1)
}

# Ask the live agent one question. Returns @{ Text; ToolCalled }
function Invoke-Agent([string]$Url, [string]$Prompt) {
    $token = gcloud auth print-identity-token --audiences="$Url" 2>$null
    if (-not $token) { $token = gcloud auth print-identity-token 2>$null }
    $h   = @{ Authorization = "Bearer $(@($token)[0])" }
    $sid = "val-" + [guid]::NewGuid().ToString("N").Substring(0, 8)
    Invoke-RestMethod -Method Post -Uri "$Url/apps/bank_agent/users/cloudlabs-validator/sessions/$sid" `
        -Headers $h -ContentType "application/json" -Body "{}" -TimeoutSec 30 | Out-Null
    $body = @{ app_name = "bank_agent"; user_id = "cloudlabs-validator"; session_id = $sid
               new_message = @{ role = "user"; parts = @(@{ text = $Prompt }) } } | ConvertTo-Json -Depth 10 -Compress
    $events = Invoke-RestMethod -Method Post -Uri "$Url/run" -Headers $h -ContentType "application/json" `
              -Body $body -TimeoutSec 45
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
    Write-Host "Project: $projectname"
    gcloud config set project $projectname --quiet 2>$null | Out-Null

    Write-Host "Checking Cloud Run service '$service'..."
    $svc = Get-AgentService
    if (-not $svc) {
        $message = New-Result "Failed" "Cloud Run service 'bank-agent' was not found in $region. Complete Exercise 3, Task 1 and wait for the deployment to finish."
    }
    elseif (-not $svc.status.url) {
        $message = New-Result "Failed" "The service 'bank-agent' has no URL yet. Wait for the deployment to finish, then validate again."
    }
    elseif ($svc.spec.template.spec.serviceAccountName -ne $agentSa) {
        $message = New-Result "Failed" "The service runs as '$($svc.spec.template.spec.serviceAccountName)'. It must run as $agentSa."
    }
    else {
        $bucket = Get-KbBucket
        $envMap = Get-ServiceEnv $svc
        $kbFile = if ($envMap["KB_FILE"]) { $envMap["KB_FILE"] } else { "products.json" }
        Write-Host "Bucket: $bucket | KB_BUCKET: $($envMap['KB_BUCKET']) | KB_FILE: $kbFile"
        if ($envMap["KB_BUCKET"] -ne $bucket) {
            $message = New-Result "Failed" "Environment variable KB_BUCKET is missing or incorrect. It must be '$bucket'."
        }
        elseif ($kbFile -ne "products.json") {
            $message = New-Result "Failed" "Environment variable KB_FILE is '$kbFile'. It must be 'products.json'."
        }
        else {
            $message = New-Result "Succeeded" "Agent deployed at $($svc.status.url), running as $agentSa with the correct knowledge-base settings."
        }
    }
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
