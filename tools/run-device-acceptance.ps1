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
    [string] $HapSignToolPath,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[0-9a-f]{40}$')]
    [string] $SampleCommit,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[A-Za-z0-9._-]{1,128}$')]
    [string] $EvidenceRunId,

    [string] $PrivateEvidenceRoot
)

$ErrorActionPreference = 'Stop'
$bundleName = 'com.example.blazorapp'

function Resolve-ToolPath {
    param([Parameter(Mandatory = $true)][string] $Path)

    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        return (Resolve-Path -LiteralPath $Path).Path
    }
    $command = Get-Command -Name $Path -ErrorAction Stop
    if (-not $command.Source) { throw "Executable path could not be resolved: $Path" }
    return $command.Source
}

function Get-Sha256 {
    param([Parameter(Mandatory = $true)][string] $Path)

    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function New-RandomNonce {
    $bytes = [byte[]]::new(32)
    $generator = [Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $generator.GetBytes($bytes)
        return [Convert]::ToBase64String($bytes)
    }
    finally {
        $generator.Dispose()
    }
}

function Write-Utf8File {
    param(
        [Parameter(Mandatory = $true)][string] $Path,
        [AllowEmptyString()][string] $Value
    )

    [IO.File]::WriteAllText($Path, $Value, [Text.UTF8Encoding]::new($false))
}

function Invoke-Hdc {
    param([Parameter(Mandatory = $true)][string[]] $Arguments)

    $effectiveArguments = if ($Target -and $Arguments[0] -ne 'list') {
        @('-t', $Target) + $Arguments
    }
    else {
        $Arguments
    }
    $previousErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $output = @(& $script:resolvedHdcPath @effectiveArguments 2>&1)
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
    $text = (($output | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine)
    if ($exitCode -ne 0) { throw "HDC command '$($Arguments[0])' failed with exit code $exitCode." }
    if ($text.IndexOf('msg:error:', [StringComparison]::Ordinal) -ge 0) {
        throw "HDC command '$($Arguments[0])' reported a semantic error."
    }
    return [pscustomobject]@{
        Output = @($output | ForEach-Object { $_.ToString() })
        Text = $text
    }
}

function Assert-HdcSemanticResult {
    param(
        [Parameter(Mandatory = $true)] $Result,
        [Parameter(Mandatory = $true)][string] $Operation,
        [Parameter(Mandatory = $true)][string[]] $AllowedResults
    )

    if ($Result.Text.IndexOf('msg:error:', [StringComparison]::Ordinal) -ge 0) {
        throw "HDC $Operation reported a semantic error."
    }
    $matches = @($AllowedResults | Where-Object { $Result.Text.IndexOf($_, [StringComparison]::Ordinal) -ge 0 })
    if ($matches.Count -ne 1) {
        throw "HDC $Operation did not report exactly one allowed semantic result."
    }
}

function Save-PrivateOutput {
    param(
        [Parameter(Mandatory = $true)][string] $Name,
        [AllowEmptyString()][string] $Value
    )

    $path = Join-Path $privateRoot $Name
    Write-Utf8File -Path $path -Value $Value
    return [pscustomobject]@{ Path = $path; Sha256 = Get-Sha256 -Path $path }
}

New-Item -ItemType Directory -Path $EvidenceRoot -Force | Out-Null
$evidenceRootPath = (Resolve-Path -LiteralPath $EvidenceRoot).Path
$publicEvidencePath = Join-Path $evidenceRootPath "api$ApiLevel-$Abi-evidence.json"
$publicLogPath = Join-Path $evidenceRootPath "api$ApiLevel-$Abi-hilog.txt"
Remove-Item -LiteralPath $publicEvidencePath, $publicLogPath -Force -ErrorAction SilentlyContinue

if (-not (Test-Path -LiteralPath $HapPath -PathType Leaf)) { throw "Signed HAP was not found: $HapPath" }
if (-not (Test-Path -LiteralPath $HapSignToolPath -PathType Leaf)) { throw "HAP signing tool was not found: $HapSignToolPath" }

$resolvedHdcPath = Resolve-ToolPath -Path $HdcPath
$resolvedJavaPath = Resolve-ToolPath -Path $JavaPath
$producerPath = (Resolve-Path -LiteralPath $PSCommandPath).Path
if ([string]::IsNullOrWhiteSpace($PrivateEvidenceRoot)) {
    $PrivateEvidenceRoot = Join-Path ([IO.Path]::GetTempPath()) ("openharmony-device-evidence-{0}" -f [Guid]::NewGuid().ToString('N'))
}
New-Item -ItemType Directory -Path $PrivateEvidenceRoot -Force | Out-Null
$privateRoot = (Resolve-Path -LiteralPath $PrivateEvidenceRoot).Path

$snapshotPath = Join-Path $privateRoot ("api{0}-{1}-{2}.hap" -f $ApiLevel, $Abi, [Guid]::NewGuid().ToString('N'))
Copy-Item -LiteralPath $HapPath -Destination $snapshotPath
$hapSnapshotSha256 = Get-Sha256 -Path $snapshotPath
$snapshotHandle = [IO.File]::Open($snapshotPath, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
try {
    $signature = & (Join-Path $PSScriptRoot 'verify-hap-signature.ps1') `
        -HapPath $snapshotPath `
        -HapSignToolPath $HapSignToolPath `
        -JavaPath $resolvedJavaPath `
        -OutputDirectory $privateRoot `
        -ArtifactPrefix "api$ApiLevel-$Abi"
    if ((Get-Sha256 -Path $snapshotPath) -cne $hapSnapshotSha256) {
        throw 'The HAP snapshot changed during signature verification.'
    }

    $availableTargetsResult = Invoke-Hdc -Arguments @('list', 'targets')
    $availableTargets = @($availableTargetsResult.Output | ForEach-Object { $_.Trim() } | Where-Object { $_ -and $_ -ne '[Empty]' })
    if ($Target) {
        if ($availableTargets -notcontains $Target) { throw 'The requested HDC target was not found.' }
        $targets = @($Target)
    }
    else {
        if ($availableTargets.Count -ne 1) { throw "Exactly one dedicated HDC target is required; found $($availableTargets.Count)." }
        $targets = $availableTargets
    }

    $deviceArchResult = Invoke-Hdc -Arguments @('shell', 'uname', '-m')
    $deviceArch = $deviceArchResult.Text.Trim()
    $expectedArch = if ($Abi -eq 'arm64-v8a') { '^(aarch64|arm64)$' } else { '^x86_64$' }
    if ($deviceArch -notmatch $expectedArch) { throw "HDC target architecture '$deviceArch' does not match $Abi." }

    $deviceApiResult = Invoke-Hdc -Arguments @('shell', 'param', 'get', 'const.ohos.apiversion')
    $deviceApiText = $deviceApiResult.Text.Trim()
    if ($deviceApiText -notmatch '\d+') { throw "Unable to read target API level: $deviceApiText" }
    $deviceApi = [int]$Matches[0]
    if ($deviceApi -ne $ApiLevel) { throw "Expected HarmonyOS API $ApiLevel target, found API $deviceApi." }

    $bundleQueryResult = Invoke-Hdc -Arguments @('shell', 'bm', 'dump', '-a')
    Save-PrivateOutput -Name 'hdc-bundle-query.txt' -Value $bundleQueryResult.Text | Out-Null
    if (@($bundleQueryResult.Output | Where-Object { $_.Trim() -match '^ID:\s*\d+:$' }).Count -eq 0) {
        throw 'The installed bundle query did not return a recognizable bundle list.'
    }
    $bundleMatches = @($bundleQueryResult.Output | Where-Object {
        $_.Trim().Equals($bundleName, [StringComparison]::Ordinal)
    })
    if ($bundleMatches.Count -gt 1) {
        throw 'The installed bundle query returned the expected bundle more than once.'
    }
    if ($bundleMatches.Count -eq 1) {
        $uninstallResult = Invoke-Hdc -Arguments @('uninstall', $bundleName)
        Assert-HdcSemanticResult -Result $uninstallResult -Operation 'uninstall' -AllowedResults @(
            'uninstall bundle successfully.')
        $uninstallSemanticResult = 'removed-existing'
        $uninstallOutputSha256 = (Save-PrivateOutput -Name 'hdc-uninstall.txt' -Value $uninstallResult.Text).Sha256
    }
    else {
        $uninstallSemanticResult = 'already-absent'
        $uninstallOutputSha256 = (Save-PrivateOutput `
            -Name 'hdc-uninstall-attestation.txt' `
            -Value ("bundle={0};installed=False" -f $bundleName)).Sha256
    }

    $preInstallProcessResult = Invoke-Hdc -Arguments @('shell', 'pidof', $bundleName)
    $preInstallProcesses = @($preInstallProcessResult.Text -split '\s+' | Where-Object { $_ })
    if ($preInstallProcesses.Count -ne 0) { throw 'The bundle process remained after uninstall.' }
    Save-PrivateOutput -Name 'hdc-preinstall-process.txt' -Value $preInstallProcessResult.Text | Out-Null

    $installResult = Invoke-Hdc -Arguments @('install', $snapshotPath)
    Assert-HdcSemanticResult -Result $installResult -Operation 'install' -AllowedResults @('install bundle successfully.')
    $installOutput = Save-PrivateOutput -Name 'hdc-install.txt' -Value $installResult.Text
    if ((Get-Sha256 -Path $snapshotPath) -cne $hapSnapshotSha256) {
        throw 'The HAP snapshot changed during installation.'
    }

    $hilogResetResult = Invoke-Hdc -Arguments @('shell', 'hilog', '-r')
    Assert-HdcSemanticResult -Result $hilogResetResult -Operation 'HiLog reset' -AllowedResults @(
        'Log type core,app,only_prerelease buffer clear successfully')
    Save-PrivateOutput -Name 'hdc-hilog-reset.txt' -Value $hilogResetResult.Text | Out-Null
    $launchResult = Invoke-Hdc -Arguments @('shell', 'aa', 'start', '-a', 'EntryAbility', '-b', $bundleName)
    Assert-HdcSemanticResult -Result $launchResult -Operation 'launch' -AllowedResults @('start ability successfully.')
    $launchOutput = Save-PrivateOutput -Name 'hdc-launch.txt' -Value $launchResult.Text

    $processResult = $null
    $processIds = @()
    $processDeadline = [DateTime]::UtcNow.AddSeconds(20)
    do {
        $processResult = Invoke-Hdc -Arguments @('shell', 'pidof', $bundleName)
        $processIds = @($processResult.Text -split '\s+' | Where-Object { $_ })
        if ($processIds.Count -eq 1 -and $processIds[0] -match '^\d+$') { break }
        if ($processIds.Count -gt 1 -or ($processIds.Count -eq 1 -and $processIds[0] -notmatch '^\d+$')) {
            throw 'Expected exactly one numeric bundle process identifier.'
        }
        Start-Sleep -Milliseconds 500
    } while ([DateTime]::UtcNow -lt $processDeadline)
    if ($processIds.Count -ne 1 -or $processIds[0] -notmatch '^\d+$') {
        throw 'The launched bundle process was not observed before the timeout.'
    }
    $processId = $processIds[0]
    Save-PrivateOutput -Name 'hdc-process.txt' -Value $processResult.Text | Out-Null

    $expectedManagedArchitecture = if ($Abi -eq 'arm64-v8a') { 'Arm64' } else { 'X64' }
    $smokePattern = '^\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2}\.\d{3}\s+(?<pid>\d+)\s+\d+\s+[A-Z]\s+A00000/Dotnet10Smoke:\s*(?<payload>' +
        'status=PASS;runtime=10\.\d+\.\d+;arch=' + [regex]::Escape($expectedManagedArchitecture) +
        ';api=' + $ApiLevel +
        ';abi=' + [regex]::Escape($Abi) +
        ';sample=' + [regex]::Escape($SampleCommit) +
        ';run=' + [regex]::Escape($EvidenceRunId) +
        ';runtimeSource=76bde136efafd0e193234e38d169752b93e3bce6' +
        ';runtimePackage=ee65d55;bindings=2b68d3c;publishAot=94e69fb' +
        ';startup=True;gc=True;thread=True;file=True;network=True;icu=True' +
        ';hilog=True;ipc=True;callback=True)\s*$'
    $smokeRecords = @()
    $hilogResult = $null
    $smokeDeadline = [DateTime]::UtcNow.AddSeconds(20)
    do {
        $hilogResult = Invoke-Hdc -Arguments @('shell', 'hilog', '-x')
        $smokeRecords = @($hilogResult.Output | ForEach-Object {
            $match = [regex]::Match($_, $smokePattern)
            if ($match.Success -and $match.Groups['pid'].Value -ceq $processId) {
                $match.Groups['payload'].Value
            }
        })
        if ($smokeRecords.Count -eq 1) { break }
        if ($smokeRecords.Count -gt 1) { throw "Expected exactly one PID-bound Dotnet10Smoke record, found $($smokeRecords.Count)." }
        Start-Sleep -Milliseconds 500
    } while ([DateTime]::UtcNow -lt $smokeDeadline)
    if ($smokeRecords.Count -ne 1) {
        throw "Expected exactly one PID-bound Dotnet10Smoke record, found $($smokeRecords.Count)."
    }
    $log = $smokeRecords[0]
    Save-PrivateOutput -Name 'hdc-hilog.txt' -Value $hilogResult.Text | Out-Null

    $required = @(
        'status=PASS',
        'runtime=10.',
        "api=$ApiLevel",
        "abi=$Abi",
        "sample=$SampleCommit",
        "run=$EvidenceRunId",
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
        'callback=True')
    foreach ($token in $required) {
        if ($log.IndexOf($token, [StringComparison]::Ordinal) -lt 0) { throw "Device smoke log is missing '$token'." }
    }
    if ((Get-Sha256 -Path $snapshotPath) -cne $hapSnapshotSha256) {
        throw 'The HAP snapshot changed during device acceptance.'
    }

    $logPath = $publicLogPath
    Write-Utf8File -Path $logPath -Value $log
    $privateManifestPath = Join-Path $privateRoot "api$ApiLevel-$Abi-private-evidence.json"
    $privateFiles = @(Get-ChildItem -LiteralPath $privateRoot -File | Where-Object { $_.FullName -cne $privateManifestPath } | Sort-Object Name | ForEach-Object {
        [ordered]@{ name = $_.Name; sha256 = Get-Sha256 -Path $_.FullName }
    })
    $privateManifest = [ordered]@{
        schemaVersion = 1
        nonce = New-RandomNonce
        evidenceRunId = $EvidenceRunId
        sampleCommit = $SampleCommit
        target = $targets[0]
        bundleName = $bundleName
        processId = $processId
        files = $privateFiles
    }
    Write-Utf8File -Path $privateManifestPath -Value (($privateManifest | ConvertTo-Json -Depth 6) + "`n")

    $evidence = [ordered]@{
        schemaVersion = 3
        result = 'PASS'
        evidenceRunId = $EvidenceRunId
        completedAtUtc = [DateTime]::UtcNow.ToString('o')
        sampleCommit = $SampleCommit
        evidenceProducerSha256 = Get-Sha256 -Path $producerPath
        signaturePolicySha256 = Get-Sha256 -Path (Join-Path $PSScriptRoot 'verify-hap-signature.ps1')
        hdcExecutableSha256 = Get-Sha256 -Path $resolvedHdcPath
        javaExecutableSha256 = Get-Sha256 -Path $resolvedJavaPath
        privateEvidenceManifestSha256 = Get-Sha256 -Path $privateManifestPath
        privateEvidenceRetention = 'controlled-local'
        apiLevel = $deviceApi
        abi = $Abi
        architecture = $deviceArch
        bundleName = $bundleName
        hapSnapshotSha256 = $hapSnapshotSha256
        hapArtifactRetention = 'controlled-local'
        signatureVerified = [bool]$signature.SignatureVerified
        signatureAttestation = [ordered]@{
            status = 'PASS'
            verifier = 'hap-sign-tool verify-app and verify-profile'
            outputSha256 = $signature.VerificationLogSha256
        }
        uninstallAttestation = [ordered]@{
            status = 'PASS'
            semanticResult = $uninstallSemanticResult
            outputSha256 = $uninstallOutputSha256
        }
        installAttestation = [ordered]@{
            status = 'PASS'
            semanticResult = 'install bundle successfully.'
            outputSha256 = $installOutput.Sha256
        }
        launchAttestation = [ordered]@{
            status = 'PASS'
            semanticResult = 'start ability successfully.'
            outputSha256 = $launchOutput.Sha256
        }
        processAttestation = [ordered]@{
            status = 'PASS'
            bundleName = $bundleName
            processCount = 1
            pidBound = $true
        }
        smokeAttestation = [ordered]@{
            status = 'PASS'
            pidBound = $true
            hilogSha256 = Get-Sha256 -Path $logPath
        }
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
        hilogSha256 = Get-Sha256 -Path $logPath
        runtimeSourceCommit = '76bde136efafd0e193234e38d169752b93e3bce6'
        runtimePackageCommit = 'ee65d55'
        bindingsCommit = '2b68d3c'
        publishAotCrossCommit = '94e69fb'
    }
    $evidencePath = $publicEvidencePath
    Write-Utf8File -Path $evidencePath -Value (($evidence | ConvertTo-Json -Depth 6) + "`n")

    Write-Output "PASS: HarmonyOS API $deviceApi $Abi acceptance evidence written to '$evidencePath'."
}
finally {
    $snapshotHandle.Dispose()
}
