# Hardware-aware Inkling 2 Mini GGUF quant selection for setup.ps1.
$script:InklingHfBase = if ($env:INKLING_HF_BASE) { $env:INKLING_HF_BASE } else {
    "https://huggingface.co/unsloth/Inkling-2-Mini-GGUF/resolve/main"
}
$script:InklingOsHeadroomGb = if ($env:INKLING_OS_HEADROOM_GB) { [int]$env:INKLING_OS_HEADROOM_GB } else { 4 }
$script:InklingDiskBufferGb = if ($env:INKLING_DISK_BUFFER_GB) { [int]$env:INKLING_DISK_BUFFER_GB } else { 2 }

$script:InklingCatalog = @(
    @{ MinGb = 48; Quant = "UD-Q8_K_XL"; File = "Inkling-2-Mini-UD-Q8_K_XL.gguf"; SizeGb = 22.9 },
    @{ MinGb = 32; Quant = "UD-Q4_K_M"; File = "Inkling-2-Mini-UD-Q4_K_M.gguf"; SizeGb = 16.6 },
    @{ MinGb = 24; Quant = "UD-Q3_K_XL"; File = "Inkling-2-Mini-UD-Q3_K_XL.gguf"; SizeGb = 13.6 },
    @{ MinGb = 16; Quant = "UD-Q2_K_XL"; File = "Inkling-2-Mini-UD-Q2_K_XL.gguf"; SizeGb = 9.1 },
    @{ MinGb = 12; Quant = "UD-IQ1_S"; File = "Inkling-2-Mini-UD-IQ1_S.gguf"; SizeGb = 7.8 }
)

function Get-TfnDetectRamGb {
    if ($env:TFN_DETECT_RAM_GB) { return [int]$env:TFN_DETECT_RAM_GB }
    try {
        $cs = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
        $mib = [math]::Round($cs.TotalPhysicalMemory / 1MB)
        return [int][math]::Round($mib / 1024.0)
    } catch {
        return 0
    }
}

function Get-TfnDetectVramGb {
    if ($env:TFN_DETECT_VRAM_GB) { return [int]$env:TFN_DETECT_VRAM_GB }
    $smi = Get-Command nvidia-smi -ErrorAction SilentlyContinue
    if (-not $smi) { return 0 }
    try {
        $line = & nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>$null | Select-Object -First 1
        $mib = [int]($line -replace '\s', '')
        if ($mib -gt 0) { return [int][math]::Round($mib / 1024.0) }
    } catch { }
    return 0
}

function Get-TfnDetectDiskGb([string]$TargetPath) {
    if ($env:TFN_DETECT_DISK_GB) { return [int]$env:TFN_DETECT_DISK_GB }
    try {
        $root = $TargetPath
        if (-not (Test-Path -LiteralPath $root)) {
            $parent = Split-Path -Parent $root
            if ($parent) { $root = $parent }
        }
        $drive = (Resolve-Path -LiteralPath $root -ErrorAction Stop).Drive
        $free = $drive.Free
        return [int][math]::Floor($free / 1GB)
    } catch {
        return 0
    }
}

function Get-InklingEffectiveMemGb {
    $ram = Get-TfnDetectRamGb
    $vram = Get-TfnDetectVramGb
    $max = [math]::Max($ram, $vram)
    return $max
}

function Resolve-InklingQuantToken([string]$Raw) {
    $t = $Raw
    if ($t.StartsWith("UD-")) { $t = $t.Substring(3) }
    if ($t.StartsWith("AD-")) { $t = $t.Substring(3) }
    $allowed = @("IQ1_S", "Q2_K_XL", "Q3_K_XL", "Q4_K_M", "Q8_K_XL")
    if ($allowed -contains $t) { return "UD-$t" }
    foreach ($row in $script:InklingCatalog) {
        if ($row.Quant -eq $Raw) { return $Raw }
    }
    return $null
}

function Select-InklingQuant([string]$WeightsDir) {
    if ($env:INKLING_MODEL_URL) { return "explicit_url" }
    if ($env:INKLING_QUANT) {
        $norm = Resolve-InklingQuantToken $env:INKLING_QUANT
        if (-not $norm) { return "invalid_quant" }
        $row = $script:InklingCatalog | Where-Object { $_.Quant -eq $norm } | Select-Object -First 1
        if (-not $row) { return "invalid_quant" }
        $disk = Get-TfnDetectDiskGb $WeightsDir
        $need = [int][math]::Ceiling($row.SizeGb + $script:InklingDiskBufferGb)
        if ($disk -lt $need) { return "skip_low_disk" }
        return $norm
    }
    $eff = Get-InklingEffectiveMemGb
    $pick = $null
    foreach ($row in $script:InklingCatalog) {
        if ($eff -ge $row.MinGb) {
            $pick = $row
            break
        }
    }
    if (-not $pick) { return "skip_low_memory" }
    $disk = Get-TfnDetectDiskGb $WeightsDir
    $need = [int][math]::Ceiling($pick.SizeGb + $script:InklingDiskBufferGb)
    if ($disk -lt $need) { return "skip_low_disk" }
    return $pick.Quant
}

function Get-InklingModelUrl([string]$Quant) {
    if ($env:INKLING_MODEL_URL) { return $env:INKLING_MODEL_URL }
    $row = $script:InklingCatalog | Where-Object { $_.Quant -eq $Quant } | Select-Object -First 1
    if (-not $row) { return $null }
    return "$($script:InklingHfBase)/$($row.File)"
}

function Get-InklingWeightsFileName([string]$Quant) {
    $row = $script:InklingCatalog | Where-Object { $_.Quant -eq $Quant } | Select-Object -First 1
    if ($row) { return $row.File }
    if ($env:INKLING_MODEL_URL) { return [System.IO.Path]::GetFileName($env:INKLING_MODEL_URL) }
    return $null
}

function Get-InklingSkipMessages([string]$WeightsDir) {
    $sel = Select-InklingQuant $WeightsDir
    $msgs = @()
    switch ($sel) {
        "skip_low_memory" {
            $msgs += "local Inkling not recommended: effective RAM/VRAM below 12 GB after OS headroom"
        }
        "skip_low_disk" {
            $msgs += "local Inkling not recommended: insufficient free disk for weights"
        }
        default {
            $msgs += "local Inkling not recommended for this hardware profile"
        }
    }
    $msgs += "use host or cloud inference or set INKLING_QUANT / INKLING_MODEL_URL to override"
    return $msgs
}