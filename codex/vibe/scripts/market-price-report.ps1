[CmdletBinding()]
param(
    [int]$SinceDays = 1,
    [string]$Project = "",
    [string]$Delegate = "vibe",
    [double]$InputPerMillion = 5.00,
    [double]$OutputPerMillion = 30.00,
    [string]$PriceBasis = "gpt-5.5 standard short-context, OpenAI API pricing checked 2026-06-10"
)

$ErrorActionPreference = "Stop"

function Get-JsonNumber {
    param(
        [Parameter(Mandatory = $true)]$Object,
        [Parameter(Mandatory = $true)][string]$Name,
        [double]$Default = 0
    )

    if ($Object.PSObject.Properties.Name -contains $Name -and $null -ne $Object.$Name) {
        return [double]$Object.$Name
    }

    return $Default
}

$logPath = Join-Path $HOME ".local\share\delegate-runs.jsonl"
if (-not (Test-Path -LiteralPath $logPath -PathType Leaf)) {
    throw "Delegate log not found: $logPath"
}

$cutoff = [DateTimeOffset]::UtcNow.AddDays(-1 * $SinceDays)
$entries = foreach ($line in Get-Content -LiteralPath $logPath -Encoding UTF8) {
    if ([string]::IsNullOrWhiteSpace($line)) { continue }
    try {
        $entry = $line | ConvertFrom-Json
    } catch {
        continue
    }

    if ($Delegate -and $entry.delegate -ne $Delegate) { continue }
    if ($Project -and $entry.project -ne $Project) { continue }
    if (-not $entry.ts) { continue }

    $ts = [DateTimeOffset]::Parse($entry.ts)
    if ($ts -lt $cutoff) { continue }

    $tokensIn = Get-JsonNumber -Object $entry -Name "tokens_in"
    $tokensOut = Get-JsonNumber -Object $entry -Name "tokens_out"
    $tokensTotal = Get-JsonNumber -Object $entry -Name "tokens_total" -Default ($tokensIn + $tokensOut)
    $delegateCost = Get-JsonNumber -Object $entry -Name "cost_usd"
    $marketCost = ($tokensIn / 1000000.0 * $InputPerMillion) + ($tokensOut / 1000000.0 * $OutputPerMillion)
    $saved = $marketCost - $delegateCost
    $ratio = if ($delegateCost -gt 0) { $marketCost / $delegateCost } else { $null }

    [pscustomobject]@{
        Timestamp = $entry.ts
        Project = $entry.project
        Model = $entry.model
        TokensIn = [int]$tokensIn
        TokensOut = [int]$tokensOut
        TokensTotal = [int]$tokensTotal
        DelegateCostUsd = [math]::Round($delegateCost, 6)
        Gpt55MarketUsd = [math]::Round($marketCost, 6)
        SavedVsGpt55Usd = [math]::Round($saved, 6)
        Ratio = if ($ratio) { [math]::Round($ratio, 2) } else { $null }
    }
}

$rows = @($entries)
if ($rows.Count -eq 0) {
    Write-Output "No matching delegate runs found."
    Write-Output "Basis: $PriceBasis"
    exit 0
}

$rows | Format-Table -AutoSize

$delegateTotal = ($rows | Measure-Object -Property DelegateCostUsd -Sum).Sum
$marketTotal = ($rows | Measure-Object -Property Gpt55MarketUsd -Sum).Sum
$savedTotal = $marketTotal - $delegateTotal
$ratioTotal = if ($delegateTotal -gt 0) { $marketTotal / $delegateTotal } else { $null }

Write-Output ""
Write-Output "Basis: $PriceBasis"
Write-Output ("Input price: `$" + ("{0:n2}" -f $InputPerMillion) + "/1M, output price: `$" + ("{0:n2}" -f $OutputPerMillion) + "/1M")
Write-Output ("Runs: {0}" -f $rows.Count)
Write-Output ("Delegate cost: `$" + ("{0:n6}" -f $delegateTotal))
Write-Output ("GPT-5.5 market equivalent: `$" + ("{0:n6}" -f $marketTotal))
Write-Output ("Saved vs GPT-5.5: `$" + ("{0:n6}" -f $savedTotal))
if ($ratioTotal) {
    Write-Output ("Market/delegate ratio: {0:n2}x" -f $ratioTotal)
}
