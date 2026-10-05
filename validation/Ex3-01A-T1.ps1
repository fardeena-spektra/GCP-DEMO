<#
=====================================================================
 CloudLabs validation - Lab 01A, Exercise 3, Task 1: Deploy and configure the service
 Lab: Day 1 Builder: Build Your First Banking Agent
 Step ID: LAB01A-EX3-TASK1

 Runs on the CloudLabs Validator Function App (PowerShell 7 worker).
 Nothing to install: it talks to the Google Cloud REST APIs directly,
 signing in with the GCP service account key that CloudLabs passes in.

 Inputs (set by CloudLabs):
   $project_id       learner's GCP project ID
   $gcp_credentials  service account key JSON of the CloudLabs validation
                     identity (needs Owner, or Viewer + Cloud Run Invoker,
                     on the learner project)

 What passing means:
   1. Cloud Run service bank-agent exists in europe-west2 and has a URL.
   2. It runs as bank-agent-sa.
   3. KB_BUCKET is the knowledge-base bucket and KB_FILE is products.json.
=====================================================================
#>

$project_id      = $project_id
$gcp_credentials = $gcp_credentials
$region          = "europe-west2"
$service         = "bank-agent"
$agentSa         = "bank-agent-sa@$project_id.iam.gserviceaccount.com"

# ---------------------------------------------------------------------
# Google sign-in: signs a JWT with the service account key and exchanges
# it for an access token (APIs) or an ID token (calling Cloud Run).
# ---------------------------------------------------------------------
function ConvertTo-B64Url([byte[]]$Bytes) {
    [Convert]::ToBase64String($Bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_')
}

function Get-GcpToken([string]$Audience) {
    $key = $gcp_credentials | ConvertFrom-Json
    $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $claims = @{ iss = $key.client_email; aud = "https://oauth2.googleapis.com/token"; iat = $now; exp = $now + 3600 }
    if ($Audience) { $claims.target_audience = $Audience }
    else { $claims.scope = "https://www.googleapis.com/auth/cloud-platform" }
    $header   = ConvertTo-B64Url ([Text.Encoding]::UTF8.GetBytes('{"alg":"RS256","typ":"JWT"}'))
    $payload  = ConvertTo-B64Url ([Text.Encoding]::UTF8.GetBytes(($claims | ConvertTo-Json -Compress)))
    $unsigned = "$header.$payload"
    $rsa = [System.Security.Cryptography.RSA]::Create()
    $rsa.ImportFromPem($key.private_key)
    $sig = $rsa.SignData([Text.Encoding]::UTF8.GetBytes($unsigned),
                         [Security.Cryptography.HashAlgorithmName]::SHA256,
                         [Security.Cryptography.RSASignaturePadding]::Pkcs1)
    $jwt = "$unsigned." + (ConvertTo-B64Url $sig)
    $r = Invoke-RestMethod -Method Post -Uri "https://oauth2.googleapis.com/token" -TimeoutSec 20 `
         -Body @{ grant_type = "urn:ietf:params:oauth:grant-type:jwt-bearer"; assertion = $jwt }
    if ($Audience) { return $r.id_token } else { return $r.access_token }
}

# GET/POST a Google API. Returns $null on 404 so a missing resource is a
# clear check failure, not a crash.
function Invoke-Gcp([string]$Method, [string]$Uri, $Body = $null) {
    $h = @{ Authorization = "Bearer $script:token" }
    try {
        if ($Body -ne $null) {
            return Invoke-RestMethod -Method $Method -Uri $Uri -Headers $h -ContentType "application/json" `
                   -Body ($Body | ConvertTo-Json -Depth 10 -Compress) -TimeoutSec 30
        }
        return Invoke-RestMethod -Method $Method -Uri $Uri -Headers $h -TimeoutSec 30
    } catch {
        if ($_.Exception.Response -and [int]$_.Exception.Response.StatusCode -eq 404) { return $null }
        throw
    }
}

function Get-KbBucket {
    $r = Invoke-Gcp GET "https://storage.googleapis.com/storage/v1/b?project=$project_id&prefix=nbkb-"
    if ($r -and $r.items) { return $r.items[0].name }
    return $null
}

function Get-AgentService {
    Invoke-Gcp GET "https://run.googleapis.com/v2/projects/$project_id/locations/$region/services/$service"
}

function Get-ServiceEnv($svc) {
    $envMap = @{}
    foreach ($c in $svc.template.containers) { foreach ($e in $c.env) { $envMap[$e.name] = $e.value } }
    return $envMap
}

# Ask the deployed agent one question. Returns @{ Text; ToolCalled }.
function Invoke-Agent([string]$Url, [string]$Prompt) {
    $idToken = Get-GcpToken -Audience $Url
    $h   = @{ Authorization = "Bearer $idToken" }
    $sid = "val-" + [guid]::NewGuid().ToString("N").Substring(0, 8)
    Invoke-RestMethod -Method Post -Uri "$Url/apps/bank_agent/users/cloudlabs-validator/sessions/$sid" `
        -Headers $h -ContentType "application/json" -Body "{}" -TimeoutSec 30 | Out-Null
    $body = @{ app_name = "bank_agent"; user_id = "cloudlabs-validator"; session_id = $sid
               new_message = @{ role = "user"; parts = @(@{ text = $Prompt }) } } | ConvertTo-Json -Depth 10 -Compress
    $events = Invoke-RestMethod -Method Post -Uri "$Url/run" -Headers $h -ContentType "application/json" `
              -Body $body -TimeoutSec 45
    $texts = @(); $tool = $false
    foreach ($ev in $events) {
        foreach ($part in @($ev.content.parts)) {
            if ($part.functionCall -and $part.functionCall.name -eq "get_product_info") { $tool = $true }
            if ($part.text) { $texts += $part.text }
        }
    }
    return @{ Text = ($(if ($texts.Count) { $texts[-1] } else { "" })); ToolCalled = $tool }
}

function New-Result([string]$Status, [string]$Message) {
    @{ Status = $Status; Message = $Message } | ConvertTo-Json
}

# ---------------------------------------------------------------------
# The check
# ---------------------------------------------------------------------
function Test-Step {
    $svc = Get-AgentService
    if (-not $svc) {
        return New-Result "Failed" "Cloud Run service 'bank-agent' was not found in $region. Complete Exercise 3, Task 1 and wait for the deployment to finish."
    }
    if (-not $svc.uri) {
        return New-Result "Failed" "The service 'bank-agent' has no URL yet. Wait for the deployment to finish, then validate again."
    }
    if ($svc.template.serviceAccount -ne $agentSa) {
        return New-Result "Failed" "The service runs as '$($svc.template.serviceAccount)'. It must run as $agentSa. Re-run the deploy step with --service-account."
    }
    $bucket  = Get-KbBucket
    $envMap  = Get-ServiceEnv $svc
    if (-not $envMap["KB_BUCKET"] -or $envMap["KB_BUCKET"] -ne $bucket) {
        return New-Result "Failed" "Environment variable KB_BUCKET is missing or incorrect. It must be '$bucket'. Re-run the 'gcloud run services update' step."
    }
    $kbFile = $envMap["KB_FILE"]; if (-not $kbFile) { $kbFile = "products.json" }
    if ($kbFile -ne "products.json") {
        return New-Result "Failed" "Environment variable KB_FILE is '$kbFile'. It must be 'products.json'."
    }
    return New-Result "Succeeded" "Agent deployed at $($svc.uri), running as $agentSa with the correct knowledge-base settings."
}

# ---------------------------------------------------------------------
# Retry wrapper (same pattern as the other CloudLabs validators)
# ---------------------------------------------------------------------
$stopRetry       = $false
[int]$retryCount = 0
$maxRetries      = 3

do {
    try {
        if (-not $project_id -or -not $gcp_credentials) {
            throw "project_id or gcp_credentials was not provided to the validator."
        }
        $script:token = Get-GcpToken
        $message = Test-Step

        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [System.Net.HttpStatusCode]::OK
            Body       = $message
        })
        $stopRetry = $true
    }
    catch {
        $retryCount++
        if ($retryCount -ge $maxRetries) {
            $message = New-Result "Failed" "Retry for validation process has been exhausted. Please try after sometime."
            Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
                StatusCode = [System.Net.HttpStatusCode]::OK
                Body       = $message
            })
            $stopRetry = $true
        }
        else {
            Start-Sleep -Seconds 5
        }
    }
} while (-not $stopRetry)
