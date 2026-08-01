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

    [string] $EvidenceRoot = 'artifacts/device-evidence',

    [string] $JavaPath = 'java',

    [Parameter(Mandatory = $true)]
    [string] $HapSignToolPath
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
New-Item -ItemType Directory -Path $EvidenceRoot -Force | Out-Null
$signature = & (Join-Path $PSScriptRoot 'verify-hap-signature.ps1') `
    -HapPath $HapPath `
    -HapSignToolPath $HapSignToolPath `
    -JavaPath $JavaPath `
    -OutputDirectory $EvidenceRoot `
    -ArtifactPrefix "api$ApiLevel-$Abi"
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
$expectedManagedArchitecture = if ($Abi -eq 'arm64-v8a') { 'Arm64' } else { 'X64' }
$smokePattern = '^\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2}\.\d{3}\s+\d+\s+\d+\s+[A-Z]\s+A00000/Dotnet10Smoke:\s*(?<payload>' +
    'status=PASS;runtime=10\.\d+\.\d+;arch=' + [regex]::Escape($expectedManagedArchitecture) +
    ';api=' + $ApiLevel +
    ';abi=' + [regex]::Escape($Abi) +
    ';runtimeSource=76bde136efafd0e193234e38d169752b93e3bce6' +
    ';runtimePackage=ee65d55;bindings=2b68d3c;publishAot=94e69fb' +
    ';startup=True;gc=True;thread=True;file=True;network=True;icu=True' +
    ';hilog=True;ipc=True;callback=True)\s*$'
$smokeRecords = @(Invoke-Hdc -Arguments @('shell', 'hilog', '-x') | ForEach-Object {
    $match = [regex]::Match($_.ToString(), $smokePattern)
    if ($match.Success) { $match.Groups['payload'].Value }
})
if ($smokeRecords.Count -ne 1) {
    throw "Expected exactly one valid Dotnet10Smoke record, found $($smokeRecords.Count)."
}
$log = $smokeRecords[0]

$required = @(
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
    schemaVersion = 2
    result = 'PASS'
    targetSha256 = (Get-FileHash -InputStream ([IO.MemoryStream]::new(
        [Text.Encoding]::UTF8.GetBytes($targets[0]))) -Algorithm SHA256).Hash.ToLowerInvariant()
    apiLevel = $deviceApi
    abi = $Abi
    architecture = $deviceArch
    hapSha256 = (Get-FileHash -LiteralPath $HapPath -Algorithm SHA256).Hash.ToLowerInvariant()
    signatureVerified = [bool]$signature.SignatureVerified
    certificateChainSha256 = $signature.CertificateChainSha256
    profileCertificateSha256 = $signature.ProfileCertificateSha256
    signerCertificateSha256 = $signature.SignerCertificateSha256
    profilePublicKeySha256 = $signature.ProfilePublicKeySha256
    signerPublicKeySha256 = $signature.SignerPublicKeySha256
    signerResolutionLogSha256 = $signature.SignerResolutionLogSha256
    signerResolverSha256 = $signature.SignerResolverSha256
    signingProfileSha256 = $signature.SigningProfileSha256
    signingProfileVerificationSha256 = $signature.ProfileVerificationSha256
    signingProfileVerificationLogSha256 = $signature.ProfileVerificationLogSha256
    signatureVerificationLogSha256 = $signature.VerificationLogSha256
    signatureVerifierSha256 = $signature.VerifierSha256
    hilogSha256 = (Get-FileHash -LiteralPath $logPath -Algorithm SHA256).Hash.ToLowerInvariant()
    runtimeSourceCommit = '76bde136efafd0e193234e38d169752b93e3bce6'
    runtimePackageCommit = 'ee65d55'
    bindingsCommit = '2b68d3c'
    publishAotCrossCommit = '94e69fb'
}
$evidencePath = Join-Path $EvidenceRoot "api$ApiLevel-$Abi-evidence.json"
[IO.File]::WriteAllText($evidencePath, (($evidence | ConvertTo-Json -Depth 4) + "`n"), [Text.UTF8Encoding]::new($false))

Write-Output "PASS: HarmonyOS API $deviceApi $Abi acceptance evidence written to '$evidencePath'."
