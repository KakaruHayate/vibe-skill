[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Workdir,

    [Parameter(Mandatory = $true)]
    [string]$PromptFile,

    [int]$MaxTurns = 10,

    [string]$Agent = "",

    [int]$TimeoutSeconds = 180,

    [string[]]$Require = @()
)

$ErrorActionPreference = "Stop"

function Convert-ToGitBashPath {
    param([Parameter(Mandatory = $true)][string]$Path)
    return ($Path -replace "\\", "/")
}

if (-not (Test-Path -LiteralPath $Workdir -PathType Container)) {
    throw "Workdir does not exist: $Workdir"
}

if (-not (Test-Path -LiteralPath $PromptFile -PathType Leaf)) {
    throw "PromptFile does not exist: $PromptFile"
}

$delegatePath = Join-Path $HOME "tools\vibe-delegate"
if (-not (Test-Path -LiteralPath $delegatePath -PathType Leaf)) {
    throw "Missing delegate script: $delegatePath"
}

$bashCandidates = @(
    (Join-Path ${env:ProgramFiles} "Git\usr\bin\bash.exe"),
    (Join-Path ${env:ProgramFiles} "Git\bin\bash.exe"),
    "bash.exe"
)

$bash = $null
foreach ($candidate in $bashCandidates) {
    $command = Get-Command $candidate -ErrorAction SilentlyContinue
    if ($command) {
        $bash = $command.Source
        break
    }
}

if (-not $bash) {
    throw "Git Bash was not found. Install Git for Windows or add bash.exe to PATH."
}

$resolvedWorkdir = (Resolve-Path -LiteralPath $Workdir).Path
$resolvedPrompt = (Resolve-Path -LiteralPath $PromptFile).Path
$runnerPath = Join-Path $PSScriptRoot "run-vibe.sh"

if (-not (Test-Path -LiteralPath $runnerPath -PathType Leaf)) {
    throw "Missing Bash runner: $runnerPath"
}

if (-not $env:VIBE_WIN_PREAMBLE) {
    $env:VIBE_WIN_PREAMBLE = "on"
}

$agentArg = if ([string]::IsNullOrEmpty($Agent)) { "__VIBE_DEFAULT_AGENT__" } else { $Agent }

$argsList = @(
    (Convert-ToGitBashPath $runnerPath),
    (Convert-ToGitBashPath $resolvedPrompt),
    (Convert-ToGitBashPath $delegatePath),
    (Convert-ToGitBashPath $resolvedWorkdir),
    [string]$MaxTurns,
    $agentArg,
    [string]$TimeoutSeconds
)

foreach ($required in $Require) {
    $argsList += "--require"
    $argsList += $required
}

& $bash @argsList
exit $LASTEXITCODE
