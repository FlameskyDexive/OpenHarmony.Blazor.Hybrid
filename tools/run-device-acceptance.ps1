[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('arm64-v8a', 'x86_64')]
    [string] $Abi,

    [Parameter(Mandatory = $true)]
    [string] $HapPath,

    [string] $HdcPath = 'hdc',

    [string] $Target,

    [int] $ApiLevel = 26,

    [string] $EvidenceRoot = 'artifacts/device-evidence'
)

$ErrorActionPreference = 'Stop'

function Invoke-Hdc {
    param([Parameter(Mandatory = $true)][string[]] $Arguments)
    $effectiveArguments = if ($Target -and $Arguments[0] -ne 'list') {
        @('-t', $Target) + $Arguments
    }
    else {
        $Arguments
    }
    $output = & $HdcPath @effectiveArguments 2>&1
    if ($LASTEXITCODE -ne 0) { throw "hdc $($Arguments -join ' ') failed:`n$($output -join [Environment]::NewLine)" }
    return @($output)
}

if (-not (Test-Path -LiteralPath $HapPath -PathType Leaf)) { throw "Signed HAP was not found: $HapPath" }
$availableTargets = @(Invoke-Hdc -Arguments @('list', 'targets') | ForEach-Object { $_.ToString().Trim() } | Where-Object { $_ -and $_ -ne '[Empty]' })
if ($Target) {
    if ($availableTargets -notcontains $Target) { throw "Requested HDC target '$Target' was not found; available targets: $($availableTargets -join ', ')" }
    $targets = @($Target)
}
else {
    if ($availableTargets.Count -ne 1) { throw "Exactly one dedicated HDC target is required; found $($availableTargets.Count): $($availableTargets -join ', ')" }
    $targets = $availableTargets
}

$deviceArch = ((Invoke-Hdc -Arguments @('shell', 'uname', '-m')) -join '').Trim()
$expectedArch = if ($Abi -eq 'arm64-v8a') { '^(aarch64|arm64)$' } else { '^x86_64$' }
if ($deviceArch -notmatch $expectedArch) { throw "HDC target architecture '$deviceArch' does not match $Abi." }

$deviceApiText = ((Invoke-Hdc -Arguments @('shell', 'param', 'get', 'const.ohos.apiversion')) -join '').Trim()
if ($deviceApiText -notmatch '\d+') { throw "Unable to read target API level: $deviceApiText" }
$deviceApi = [int]$Matches[0]
if ($deviceApi -ne $ApiLevel) { throw "Expected HarmonyOS API $ApiLevel target, found API $deviceApi." }

Invoke-Hdc -Arguments @('shell', 'hilog', '-r') | Out-Null
Invoke-Hdc -Arguments @('install', '-r', (Resolve-Path -LiteralPath $HapPath).Path) | Out-Null
Invoke-Hdc -Arguments @('shell', 'aa', 'start', '-a', 'EntryAbility', '-b', 'com.example.blazorapp') | Out-Null
Start-Sleep -Seconds 10
$log = (Invoke-Hdc -Arguments @('shell', 'hilog', '-x')) -join [Environment]::NewLine

$required = @(
    'Dotnet10Smoke',
    'status=PASS',
    'runtime=10.',
    "api=$ApiLevel",
    "abi=$Abi",
    'runtimeSource=76bde136efafd0e193234e38d169752b93e3bce6',
    'runtimePackage=ee65d55',
    'bindings=2b68d3c',
    'publishAot=94e69fb',
    'startup=True',
    'gc=True',
    'thread=True',
    'file=True',
    'network=True',
    'icu=True',
    'hilog=True',
    'ipc=True',
    'callback=True'
)
foreach ($token in $required) {
    if ($log.IndexOf($token, [StringComparison]::Ordinal) -lt 0) { throw "Device smoke log is missing '$token'." }
}

New-Item -ItemType Directory -Path $EvidenceRoot -Force | Out-Null
$logPath = Join-Path $EvidenceRoot "api$ApiLevel-$Abi-hilog.txt"
[IO.File]::WriteAllText($logPath, $log, [Text.UTF8Encoding]::new($false))
$evidence = [ordered]@{
    schemaVersion = 1
    result = 'PASS'
    target = $targets[0]
    apiLevel = $deviceApi
    abi = $Abi
    architecture = $deviceArch
    hapSha256 = (Get-FileHash -LiteralPath $HapPath -Algorithm SHA256).Hash.ToLowerInvariant()
    hilogSha256 = (Get-FileHash -LiteralPath $logPath -Algorithm SHA256).Hash.ToLowerInvariant()
    runtimeSourceCommit = '76bde136efafd0e193234e38d169752b93e3bce6'
    runtimePackageCommit = 'ee65d55'
    bindingsCommit = '2b68d3c'
    publishAotCrossCommit = '94e69fb'
}
$evidencePath = Join-Path $EvidenceRoot "api$ApiLevel-$Abi-evidence.json"
[IO.File]::WriteAllText($evidencePath, (($evidence | ConvertTo-Json -Depth 4) + "`n"), [Text.UTF8Encoding]::new($false))

Write-Output "PASS: HarmonyOS API $deviceApi $Abi acceptance evidence written to '$evidencePath'."
