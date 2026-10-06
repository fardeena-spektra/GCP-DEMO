<#
 CloudLabs validation | LAB01A-EX3-TASK1
 Exercise 3, Task 1: Deploy the agent to a private VM
 Lab: Day 1 Builder: Build Your First Banking Agent

 Script Type : PowerShellV2      Run As : System
 Parameters  : DeploymentId = GET-DEPLOYMENT-ID (System)
               projectname  = GET-GCP-PROJECT   (System)

 Passes when:
   - VM agent-vm exists and is RUNNING
   - it runs as bank-agent-sa and has the network tag 'agent'
   - metadata KB_BUCKET is the nbkb-* bucket and KB_FILE is products.json
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

    $vm = Get-AgentVm
    if (-not $vm) {
        $message = New-Result "Failed" "The VM 'agent-vm' was not found. Complete Exercise 3, Task 1."
    }
    elseif ($vm.status -ne "RUNNING") {
        $message = New-Result "Failed" "The VM 'agent-vm' is $($vm.status). It must be RUNNING."
    }
    elseif (@($vm.serviceAccounts)[0].email -ne $agentSa) {
        $message = New-Result "Failed" "The VM runs as '$(@($vm.serviceAccounts)[0].email)'. It must run as $agentSa."
    }
    elseif (@($vm.tags.items) -notcontains "agent") {
        $message = New-Result "Failed" "The VM does not have the network tag 'agent', so it is not reachable through IAP."
    }
    else {
        $bucket = Get-KbBucket
        $meta   = Get-VmMeta $vm
        $kbFile = if ($meta["KB_FILE"]) { $meta["KB_FILE"] } else { "products.json" }
        Write-Host "Bucket: $bucket | KB_BUCKET: $($meta['KB_BUCKET']) | KB_FILE: $kbFile"
        if ($meta["KB_BUCKET"] -ne $bucket) {
            $message = New-Result "Failed" "VM metadata KB_BUCKET is missing or incorrect. It must be '$bucket'."
        }
        elseif ($kbFile -ne "products.json") {
            $message = New-Result "Failed" "VM metadata KB_FILE is '$kbFile'. It must be 'products.json'."
        }
        else {
            $message = New-Result "Succeeded" "agent-vm is running as $agentSa, private (IAP only), with the correct knowledge-base settings."
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
