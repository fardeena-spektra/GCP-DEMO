<#
 CloudLabs validation | LAB01A-EX3-TASK2
 Exercise 3, Task 2: Call the deployed agent securely
 Lab: Day 1 Builder: Build Your First Banking Agent

 Script Type : PowerShellV2      Run As : System
 Parameters  : projectname = GET-GCP-PROJECT (System)

 Passes when:
   - the live agent calls the get_product_info tool
   - and returns the current Everyday Saver rate, 4.15%
#>
param(
    [string]$projectname
)

$region  = "any region"   # detected automatically from the service
$service = "bank-agent"
$agentSa = "bank-agent-sa@$projectname.iam.gserviceaccount.com"
$message = $null

function New-Result([string]$Status, [string]$Message) {
    @{ Status = $Status; Message = $Message } | ConvertTo-Json
}

# Cloud Run service as JSON, searched in ALL regions, or $null if it does not exist.
# Sets $script:region to the region where the service was found.
function Get-AgentService {
    $json = gcloud run services list --project $projectname --filter="metadata.name=$service" --format="json" 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $json) { return $null }
    $list = @($json | Out-String | ConvertFrom-Json)
    if ($list.Count -eq 0 -or -not $list[0]) { return $null }
    $svc = $list[0]
    $loc = $svc.metadata.labels.'cloud.googleapis.com/location'
    if ($loc) { $script:region = $loc }
    Write-Host "Found '$service' in region: $script:region"
    return $svc
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
    if (-not $svc -or -not $svc.status.url) {
        $message = New-Result "Failed" "Cloud Run service 'bank-agent' was not found. Complete Exercise 3, Task 1 first."
    }
    else {
        Write-Host "Asking the agent at $($svc.status.url)..."
        $ans = Invoke-Agent -Url $svc.status.url -Prompt "What is the interest rate on the Everyday Saver account?"
        Write-Host "Tool called: $($ans.ToolCalled) | Answer: $($ans.Text)"
        $short = $ans.Text.Substring(0, [Math]::Min(200, $ans.Text.Length))
        if (-not $ans.ToolCalled) {
            $message = New-Result "Failed" "The agent answered without calling get_product_info. Check that the tool is registered and the instruction requires it."
        }
        elseif ($ans.Text -notmatch "4\.15") {
            $message = New-Result "Failed" "The agent did not return the current Everyday Saver rate (4.15% AER). Response: $short"
        }
        else {
            $message = New-Result "Succeeded" "The deployed agent called the knowledge-base tool and returned the correct, grounded answer (4.15% AER)."
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
