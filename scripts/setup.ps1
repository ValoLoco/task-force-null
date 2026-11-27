# Guided Task Force Null setup for native Windows PowerShell.
#Requires -Version 5.1
param(
    [switch]$DryRun,
    [switch]$NonInteractive,
    [switch]$SkipLlm,
    [switch]$SkipKeys,
    [switch]$SkipDeploy,
    [string]$Harness = "",
    [string]$MissionSlug = "",
    [string]$InstallHarness = ""
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$DefaultSlug = "setup-mission"
if (-not $MissionSlug) { $MissionSlug = $env:SETUP_MISSION_SLUG }
if (-not $Harness -and $env:SETUP_HARNESS) { $Harness = $env:SETUP_HARNESS }

$LocalLlmDir = if ($env:LOCAL_LLM_DIR) { $env:LOCAL_LLM_DIR } else {
    if (Test-Path "/workspace/local-llm") { "/workspace/local-llm" }
    else { Join-Path $env:USERPROFILE "local-llm" }
}
$WeightsFile = Join-Path $LocalLlmDir "weights\Inkling-2-Mini-AD-IQ1_S.gguf"
$EnsureScript = Join-Path $LocalLlmDir "ensure-running.sh"

function Write-SetupLog($msg) {
    Write-Host "[setup] $msg"
}

function Invoke-SetupCmd([scriptblock]$Action, [string]$Label) {
    if ($DryRun) {
        Write-SetupLog "[dry-run] would run: $Label"
        return
    }
    Write-SetupLog "run: $Label"
    & $Action
}

function Test-YesNo($question, $defaultYes) {
    if ($NonInteractive) { return $defaultYes }
    $suffix = if ($defaultYes) { "Y/n" } else { "y/N" }
    $ans = Read-Host "$question [$suffix]"
    if (-not $ans) { return $defaultYes }
    return $ans -match '^[Yy]'
}

function Get-WindowsPkgManager {
    if (Get-Command winget -ErrorAction SilentlyContinue) { return "winget" }
    if (Get-Command choco -ErrorAction SilentlyContinue) { return "choco" }
    return "none"
}

function Get-DetectedHarnesses {
    $found = @()
    if (Get-Command hermes -ErrorAction SilentlyContinue) { $found += "hermes" }
    if ($env:HERMES_HOME) { if ($found -notcontains "hermes") { $found += "hermes" } }
    if (Get-Command pi -ErrorAction SilentlyContinue) { $found += "pi" }
    if (Get-Command claude -ErrorAction SilentlyContinue) { $found += "claude" }
    if ($env:XAI_API_KEY -or $env:GROK_BOT) { $found += "grok" }
    if ($env:CURSOR_AGENT -or $env:CURSOR_TRACE_ID) { $found += "cursor" }
  return $found
}

function Select-Harness {
    param([string]$Chosen, [string]$Install)
    if ($Chosen) {
        Write-SetupLog "using harness: $Chosen"
        return $Chosen
    }
    $detected = @(Get-DetectedHarnesses)
    if ($detected.Count -eq 0) {
        Write-SetupLog "no harness installed"
        if ($NonInteractive) {
            return $(if ($Install) { $Install } else { "generic" })
        }
        Write-Host "Install Hermes (h), Pi (p), or skip (s)?"
        $pick = Read-Host
        switch -Regex ($pick) {
            '^[hH]' { $script:InstallHarness = "hermes"; return "hermes" }
            '^[pP]' { $script:InstallHarness = "pi"; return "pi" }
            default { return "generic" }
        }
    }
    if ($detected.Count -eq 1) {
        $h = $detected[0]
        if (-not (Test-YesNo "Use harness '$h'?" $true)) { return "generic" }
        return $h
    }
    if ($NonInteractive) { return $detected[0] }
    $i = 1
    foreach ($h in $detected) { Write-Host "  $i) $h"; $i++ }
    $sel = Read-Host "Select harness [1]"
    if (-not $sel) { $sel = "1" }
    $idx = [int]$sel - 1
    if ($idx -lt 0 -or $idx -ge $detected.Count) { $idx = 0 }
    return $detected[$idx]
}

function Install-HarnessIfNeeded($target) {
    if (-not $target) { return }
    switch ($target) {
        "hermes" {
            if (Get-Command hermes -ErrorAction SilentlyContinue) {
                Write-SetupLog "hermes already installed"
                return
            }
            if (-not (Test-YesNo "Install Hermes Agent via pip?" $true)) { return }
            Invoke-SetupCmd { python -m pip install --user hermes-agent } "pip install hermes-agent"
        }
        "pi" {
            if (Get-Command pi -ErrorAction SilentlyContinue) {
                Write-SetupLog "pi already installed"
                return
            }
            if (-not (Test-YesNo "Install Pi Coding Agent (pi.dev)?" $true)) { return }
            if ($DryRun) {
                Write-SetupLog "[dry-run] would run: irm https://pi.dev/install.ps1 | iex"
                Write-SetupLog "[dry-run] would run: pi install npm:pi-agents"
                return
            }
            Invoke-Expression (Invoke-RestMethod -Uri "https://pi.dev/install.ps1")
            if (Get-Command pi -ErrorAction SilentlyContinue) {
                pi install npm:pi-agents
            }
        }
    }
}

function Test-LlmHealthy {
    try {
        $r = Invoke-WebRequest -Uri "http://127.0.0.1:8080/v1/models" -TimeoutSec 2 -UseBasicParsing
        return $r.StatusCode -eq 200
    } catch {
        try {
            $r = Invoke-WebRequest -Uri "http://127.0.0.1:8080/health" -TimeoutSec 2 -UseBasicParsing
            return $r.StatusCode -eq 200
        } catch { return $false }
    }
}

function Show-LlamaInstallHint {
    $pkg = Get-WindowsPkgManager
    switch ($pkg) {
        "winget" { Write-SetupLog "Install: winget install ggml.llamacpp" }
        "choco" { Write-SetupLog "Install: choco install llama-cpp" }
        default { Write-SetupLog "Install prebuilt llama-server.exe from github.com/ggml-org/llama.cpp" }
    }
}

function Setup-LocalLlm {
    if ($SkipLlm) { Write-SetupLog "skip local LLM"; return }
    $ready = ((Test-Path $WeightsFile) -and (Test-Path $EnsureScript)) -or (Test-LlmHealthy)
    if ($ready) {
        Write-SetupLog "reusing existing local LLM at $LocalLlmDir"
        if (-not (Test-LlmHealthy) -and (Test-Path $EnsureScript)) {
            if (Get-Command bash -ErrorAction SilentlyContinue) {
                Invoke-SetupCmd { bash $EnsureScript } "ensure-running.sh"
            }
        }
        return
    }
    if (-not (Test-YesNo "Set up llama.cpp + Inkling 2 Mini (6.5 GB) on 127.0.0.1:8080?" $false)) {
        Write-SetupLog "skipped local LLM setup"
        return
    }
    $url = if ($env:INKLING_MODEL_URL) { $env:INKLING_MODEL_URL } else {
        "https://huggingface.co/FUN-GAL/Inkling-2-Mini-gguf/resolve/main/Inkling-2-Mini-AD-IQ1_S.gguf"
    }
    $weightsDir = Join-Path $LocalLlmDir "weights"
    if ($DryRun) {
        Write-SetupLog "[dry-run] would mkdir $weightsDir"
        Write-SetupLog "[dry-run] would download Inkling weights"
        Write-SetupLog "[dry-run] would start llama-server.exe on :8080"
        return
    }
    New-Item -ItemType Directory -Force -Path $weightsDir | Out-Null
    if (-not (Test-Path $WeightsFile)) {
        Invoke-WebRequest -Uri $url -OutFile $WeightsFile
    } else {
        Write-SetupLog "weights already present"
    }
    $llama = Get-Command llama-server -ErrorAction SilentlyContinue
    if (-not $llama) {
        $llama = Get-Command llama-server.exe -ErrorAction SilentlyContinue
    }
    if (-not $llama) {
        Show-LlamaInstallHint
        Write-SetupLog "llama-server not found; install and re-run or use cloud keys"
        return
    }
    if (-not (Test-LlmHealthy)) {
        Start-Process -FilePath $llama.Source -ArgumentList @(
            "-m", $WeightsFile, "--host", "127.0.0.1", "--port", "8080",
            "--load-mode", "mmap", "--lazy-mode", "on", "--n-gpu-layers", "0", "--ctx-size", "2048"
        ) -WindowStyle Hidden
        Start-Sleep -Seconds 2
    }
}

function Get-EnvValue($key) {
    $file = Join-Path $RepoRoot ".env"
    if (-not (Test-Path $file)) { return $null }
    foreach ($line in Get-Content $file) {
        if ($line -match "^$key=(.*)$") { return $Matches[1] }
    }
    return $null
}

function Set-EnvValue($key, $plain) {
    $file = Join-Path $RepoRoot ".env"
    $lines = @()
    if (Test-Path $file) {
        $lines = @(Get-Content $file | Where-Object { $_ -notmatch "^$key=" })
    }
    $lines += "$key=$plain"
    if ($DryRun) {
        Write-SetupLog "[dry-run] would set ${key}=*** in .env"
        return
    }
    $lines | Set-Content -Path $file -Encoding utf8
}

function Prompt-ApiKeys {
    if ($SkipKeys) { Write-SetupLog "skip API keys"; return }
    foreach ($key in @("NVIDIA_API_KEY", "OPENAI_API_KEY", "XAI_API_KEY")) {
        $cur = Get-EnvValue $key
        if ($NonInteractive) {
            if ($cur) { Write-SetupLog "${key} already set in .env" }
            continue
        }
        $prompt = "Enter $key (leave empty to keep existing)"
        if ($cur) { $prompt += " [masked]" }
        Write-Host $prompt
        $sec = Read-Host -AsSecureString
        $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
        try {
            $plain = [Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
        } finally {
            [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
        }
        if (-not $plain) { continue }
        Set-EnvValue $key $plain
        Write-SetupLog "${key} saved"
    }
}

function Invoke-BashScript($relative, [string[]]$ExtraArgs) {
    $scriptPath = Join-Path $RepoRoot $relative
    if (Get-Command bash -ErrorAction SilentlyContinue) {
        if ($DryRun) {
            Write-SetupLog "[dry-run] would run: bash $relative $($ExtraArgs -join ' ')"
            return
        }
        Push-Location $RepoRoot
        try {
            & bash $scriptPath @ExtraArgs
        } finally {
            Pop-Location
        }
        return
    }
    Write-SetupLog "bash not found; run Git Bash or WSL: bash $relative"
}

function Deploy-HarnessNotes($chosen) {
    switch ($chosen) {
        "hermes" { Write-SetupLog "Hermes: workspace $RepoRoot; see harnesses/hermes-agent.md" }
        "pi" { Write-SetupLog "Pi: workspace $RepoRoot; see harnesses/pi-agent.md" }
        "claude" { Write-SetupLog "Claude Code: open $RepoRoot" }
        "grok" { Write-SetupLog "Grok Bot: mount repo and load AGENTS.md" }
        "cursor" { Write-SetupLog "Cursor: agent workspace $RepoRoot" }
        default { Write-SetupLog "Generic: load AGENTS.md from $RepoRoot" }
    }
}

function Bootstrap-Deploy($slug, $chosen) {
    if ($SkipDeploy) { Write-SetupLog "skip bootstrap deploy"; return }
    if (-not $slug) { $slug = $DefaultSlug }
    Invoke-BashScript "scripts/sync-armory.sh" @("--allow-offline")
    $env:MISSION_SLUG = $slug
    Invoke-BashScript "scripts/detect-models.sh" @("--slug", $slug)
    $missionDir = Join-Path $RepoRoot "missions\$slug"
    if (Test-Path $missionDir) {
        Write-SetupLog "mission $slug already exists; skipping deploy-squad.sh"
    } else {
        $env:SKIP_SYNC_ARMORY = "1"
        $env:SKIP_DETECT_MODELS = "1"
        Invoke-BashScript "scripts/deploy-squad.sh" @($slug, "Task Force Null setup mission")
    }
    $env:MISSION_SLUG = $slug
    Invoke-BashScript "scripts/start.sh" @()
    Deploy-HarnessNotes $chosen
}

Write-SetupLog "Task Force Null setup (repo=$RepoRoot, pkg=$(Get-WindowsPkgManager))"
if ($DryRun) { Write-SetupLog "[dry-run] mode enabled" }

$ChosenHarness = Select-Harness -Chosen $Harness -Install $InstallHarness
if ($InstallHarness) {
    Install-HarnessIfNeeded $InstallHarness
} elseif ($script:InstallHarness) {
    Install-HarnessIfNeeded $script:InstallHarness
}

Setup-LocalLlm
Prompt-ApiKeys
Bootstrap-Deploy -slug $MissionSlug -chosen $ChosenHarness
Write-SetupLog "setup complete"