<#
 CloudLabs validation | LAB01A-EX3-TASK2
 Exercise 3, Task 2: Call the deployed agent securely
 Lab: Day 1 Builder: Build Your First Banking Agent

 Script Type : PowerShellV2      Run As : System
 Parameters  : DeploymentId = GET-DEPLOYMENT-ID (System)
               projectname  = GET-GCP-PROJECT   (System)

 Passes when:
   - agent-vm exists and is RUNNING
   - in the last 60 minutes the agent called its knowledge-base tool
     (KB_LOOKUP log) and read products.json, version 2026-10
   (no SSH needed: it reads the agent's own logs in Cloud Logging)
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

# Latest agent log entries (written by agent-vm to Cloud Logging, log name "bank-agent")
function Get-AgentLogs([string]$Message, [int]$Minutes = 60) {
    # No embedded quotes in the filter: PowerShell can strip them when calling gcloud
    $filter = "logName:bank-agent AND jsonPayload.message=$Message"
    $json = gcloud logging read $filter --project $projectname --freshness "$($Minutes)m" --limit 20 --order desc --format json 2>$null | Out-String
    Write-Host "Log query: $filter (last $Minutes min)"
    if (-not $json.Trim()) { return @() }
    return @($json | ConvertFrom-Json)
}

try {
    if (-not $projectname) { throw "The projectname parameter is empty. Map it to GET-GCP-PROJECT." }
    Write-Host "Project: $projectname | DeploymentId: $DeploymentId"
    gcloud config set project $projectname --quiet 2>$null | Out-Null

    $vm = Get-AgentVm
    if (-not $vm) {
        $message = New-Result "Failed" "The VM 'agent-vm' was not found. Complete Exercise 3, Task 1 first."
    }
    elseif ($vm.status -ne "RUNNING") {
        $message = New-Result "Failed" "The VM 'agent-vm' is $($vm.status). Start it and call the agent again."
    }
    else {
        $lookups = Get-AgentLogs -Message "KB_LOOKUP" -Minutes 60
        Write-Host "KB_LOOKUP entries in the last 60 minutes: $($lookups.Count)"
        $good = $lookups | Where-Object { $_.jsonPayload.file -eq "products.json" -and $_.jsonPayload.kb_version -eq "2026-10" } | Select-Object -First 1
        if (-not $lookups -or $lookups.Count -eq 0) {
            $message = New-Result "Failed" "No call to the agent's knowledge-base tool was found in the last 60 minutes. Complete Exercise 3, Task 2 (ask the agent the Everyday Saver question), wait 1 minute, then validate again."
        }
        elseif (-not $good) {
            $f = $lookups[0].jsonPayload.file; $v = $lookups[0].jsonPayload.kb_version
            $message = New-Result "Failed" "The agent read '$f' (version $v). It must read products.json (version 2026-10)."
        }
        else {
            $message = New-Result "Succeeded" "The deployed agent answered through its knowledge-base tool, grounded in products.json (version 2026-10)."
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
