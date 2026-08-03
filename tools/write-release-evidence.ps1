[CmdletBinding()]
param(
    [string] $SimulatorEvidencePath = (Join-Path $PSScriptRoot '..\artifacts\simulator-evidence\compatibility-summary.json'),
    [string] $Arm64ReadinessPath = (Join-Path $PSScriptRoot '..\artifacts\arm64-readiness\arm64-readiness.json'),
    [string] $ConsumerEvidencePath = (Join-Path $PSScriptRoot '..\artifacts\xengine-consumer\clean-consumer-evidence.json'),
    [string] $RuntimeManifestPath = (Join-Path $PSScriptRoot '..\ThirdParty\OpenHarmony.NET.Runtime\release\10.0.10-ohos.2-preview.1\manifest.json'),
    [string] $HapMatrixRoot = (Join-Path $PSScriptRoot '..\artifacts\hap-matrix'),
    [string] $OutputPath = (Join-Path $PSScriptRoot '..\artifacts\release-evidence\release-evidence.json')
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $PSScriptRoot 'verify-release-evidence.ps1')

function Get-Sha256 {
    param([Parameter(Mandatory = $true)][string] $Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Read-JsonFile {
    param([Parameter(Mandatory = $true)][string] $Path, [Parameter(Mandatory = $true)][string] $Name)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "$Name was not found: $Path" }
    return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
}

function Get-SingleCommit {
    param([Parameter(Mandatory = $true)][object[]] $Records, [Parameter(Mandatory = $true)][string] $Property)
    $values = @($Records | ForEach-Object { [string]$_.$Property } | Where-Object { $_ } | Sort-Object -Unique)
    if ($values.Count -ne 1) { throw "Evidence does not resolve one immutable $Property value." }
    Assert-ReleaseCommit -Value $values[0] -Name $Property
    return $values[0]
}

function Get-SubmoduleCommit {
    param([Parameter(Mandatory = $true)][string] $Path)
    $value = (& git -C $repoRoot rev-parse "HEAD:$Path" 2>&1 | Out-String).Trim()
    if ($LASTEXITCODE -ne 0) { throw "Unable to resolve submodule commit for $Path." }
    Assert-ReleaseCommit -Value $value -Name $Path
    return $value
}

function New-LinkedRecord {
    param(
        [Parameter(Mandatory = $true)] $Source,
        [Parameter(Mandatory = $true)][string] $Result,
        [AllowNull()][Nullable[int]] $DeviceApi,
        [AllowNull()][string] $HapSha256,
        [AllowNull()][string] $Reason,
        [Parameter(Mandatory = $true)] $Commits,
        [Parameter(Mandatory = $true)][string] $ManifestSha256
    )
    $record = [ordered]@{
        testResult = $Result
        buildApi = [int]$Source.buildApi
        runtimeBaselineApi = 13
        deviceApi = if ($null -eq $DeviceApi) { $null } else { [int]$DeviceApi }
        abi = [string]$Source.abi
        hapSha256 = $HapSha256
        runtimeManifestSha256 = $ManifestSha256
        runtimeSourceCommit = $Commits.runtimeSource
        bindingsCommit = $Commits.bindings
        publishAotCrossCommit = $Commits.publishAotCross
        runtimePackageCommit = $Commits.runtimePackage
        sampleCommit = $Commits.sample
    }
    if (-not [string]::IsNullOrWhiteSpace($Reason)) { $record.reason = $Reason }
    return [pscustomobject]$record
}

foreach ($path in $SimulatorEvidencePath, $Arm64ReadinessPath, $ConsumerEvidencePath, $RuntimeManifestPath) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Release evidence input was not found: $path" }
}
New-Item -ItemType Directory -Path (Split-Path -Parent $OutputPath) -Force | Out-Null
Remove-Item -LiteralPath $OutputPath -Force -ErrorAction SilentlyContinue

$simulator = Read-JsonFile -Path $SimulatorEvidencePath -Name 'Simulator compatibility evidence'
$arm64 = Read-JsonFile -Path $Arm64ReadinessPath -Name 'arm64 readiness evidence'
$consumer = Read-JsonFile -Path $ConsumerEvidencePath -Name 'Clean consumer evidence'
$manifest = Read-JsonFile -Path $RuntimeManifestPath -Name 'Runtime release manifest'
$manifestSha256 = Get-Sha256 -Path $RuntimeManifestPath

if ($simulator.result -cne 'PASS' -or [int]$simulator.totalCount -ne 91 -or
    [int]$simulator.passCount -ne 54 -or [int]$simulator.skippedCount -ne 37) {
    throw 'Simulator compatibility evidence is not the complete 91-case result.'
}
if ($arm64.status -cne 'READY_FOR_DEVICE' -or [int]$arm64.logicalApiCount -ne 13 -or
    [int]$arm64.verifiedHapCount -ne 7 -or [int]$arm64.skippedApiCount -ne 6) {
    throw 'arm64 readiness evidence is incomplete.'
}
if ($consumer.status -cne 'PASS' -or @($consumer.cases).Count -ne 4 -or @($consumer.packages).Count -ne 3) {
    throw 'Clean consumer evidence is incomplete.'
}
if ($manifest.version -cne '10.0.10-ohos.2-preview.1' -or [int]$manifest.runtimeBaselineApi -ne 13) {
    throw 'Runtime release manifest is not the API13 baseline preview release.'
}

$simulatorPass = @($simulator.records | Where-Object status -eq 'PASS')
$commits = [ordered]@{
    runtimeSource = [string]$manifest.runtimeCommit
    bindings = Get-SingleCommit -Records $simulatorPass -Property 'bindingsCommit'
    publishAotCross = Get-SingleCommit -Records $simulatorPass -Property 'publishAotCrossCommit'
    runtimePackage = Get-SingleCommit -Records $simulatorPass -Property 'runtimeCommit'
    sample = Get-SingleCommit -Records $simulatorPass -Property 'sampleCommit'
}
Assert-ReleaseCommit -Value $commits.runtimeSource -Name 'runtimeSource'
if ($commits.bindings -cne [string]$manifest.bindingsCommit) {
    throw 'Simulator bindings commit does not match the runtime release manifest.'
}
if ((Get-SubmoduleCommit -Path 'ThirdParty/OpenHarmony.NDK.Bindings') -cne $commits.bindings -or
    (Get-SubmoduleCommit -Path 'ThirdParty/OpenHarmony.NET.Runtime') -cne $commits.runtimePackage -or
    (Get-SubmoduleCommit -Path 'ThirdParty/PublishAotCross') -cne $commits.publishAotCross) {
    throw 'Release evidence commits do not match the checked-in submodule pointers.'
}
& git -C $repoRoot merge-base --is-ancestor $commits.sample HEAD
if ($LASTEXITCODE -ne 0) { throw 'HAP sample commit is not an ancestor of the evidence producer.' }

$simulatorRecords = [Collections.Generic.List[object]]::new()
foreach ($source in @($simulator.records)) {
    $result = if ($source.status -ceq 'PASS') { 'PASS' } else { 'SKIPPED' }
    if ($result -eq 'PASS') {
        foreach ($name in 'sampleCommit', 'bindingsCommit', 'publishAotCrossCommit') {
            if ([string]$source.$name -cne [string]$commits.($name -replace 'Commit$', '')) {
                throw "Simulator record commit mismatch for $name."
            }
        }
        if ([string]$source.runtimeCommit -cne $commits.runtimePackage -or [bool]$source.runtimeManifestEntry.sourceDirty) {
            throw 'Simulator record runtime package/provenance linkage is invalid.'
        }
    }
    $record = New-LinkedRecord -Source $source -Result $result -DeviceApi ([int]$source.deviceApi) `
        -HapSha256 $(if ($result -eq 'PASS') { [string]$source.hapSha256 } else { $null }) `
        -Reason $(if ($result -eq 'SKIPPED') { [string]$source.reason } else { $null }) `
        -Commits $commits -ManifestSha256 $manifestSha256
    Assert-ReleaseEvidenceRecord -Record $record -Context "simulator API$($source.buildApi)-on-API$($source.deviceApi)"
    $simulatorRecords.Add($record)
}

$arm64Records = [Collections.Generic.List[object]]::new()
foreach ($source in @($arm64.cases)) {
    $result = if ($source.status -ceq 'READY_FOR_DEVICE') { 'READY_FOR_DEVICE' } else { 'SKIPPED' }
    $hapSha256 = $null
    if ($result -eq 'READY_FOR_DEVICE') {
        $metadataPath = Join-Path $HapMatrixRoot "api$($source.buildApi)\arm64-v8a\build-metadata.json"
        $hapPath = Join-Path $HapMatrixRoot "api$($source.buildApi)\arm64-v8a\entry-default-signed.hap"
        $metadata = Read-JsonFile -Path $metadataPath -Name "API$($source.buildApi) arm64 HAP metadata"
        if (-not (Test-Path -LiteralPath $hapPath -PathType Leaf)) { throw "API$($source.buildApi) arm64 HAP is missing." }
        $hapSha256 = Get-Sha256 -Path $hapPath
        if ($hapSha256 -cne [string]$source.hapSha256 -or $hapSha256 -cne [string]$metadata.hapSha256) {
            throw "API$($source.buildApi) arm64 HAP hash linkage is invalid."
        }
        if ([string]$metadata.commits.sample -cne $commits.sample -or
            [string]$metadata.commits.runtime -cne $commits.runtimePackage -or
            [string]$metadata.commits.bindings -cne $commits.bindings -or
            [string]$metadata.commits.publishAotCross -cne $commits.publishAotCross -or
            [bool]$metadata.runtimeManifestEntry.sourceDirty) {
            throw "API$($source.buildApi) arm64 HAP commit/provenance linkage is invalid."
        }
    }
    $record = New-LinkedRecord -Source $source -Result $result -DeviceApi $null -HapSha256 $hapSha256 `
        -Reason $(if ($result -eq 'SKIPPED') { [string]$source.reason } else { $null }) `
        -Commits $commits -ManifestSha256 $manifestSha256
    Assert-ReleaseEvidenceRecord -Record $record -Context "arm64 API$($source.buildApi)"
    $arm64Records.Add($record)
}

$deviceRecords = [Collections.Generic.List[object]]::new()
foreach ($source in @($arm64.device.cases)) {
    $result = if ($source.status -ceq 'PASS') { 'PASS' } else { 'SKIPPED' }
    $metadataPath = Join-Path $HapMatrixRoot "api$($source.buildApi)\arm64-v8a\build-metadata.json"
    $metadata = if ($result -eq 'PASS') { Read-JsonFile -Path $metadataPath -Name "device API$($source.buildApi) HAP metadata" } else { $null }
    $record = New-LinkedRecord -Source $source -Result $result -DeviceApi 24 `
        -HapSha256 $(if ($result -eq 'PASS') { [string]$metadata.hapSha256 } else { $null }) `
        -Reason $(if ($result -eq 'SKIPPED') { [string]$source.reason } else { $null }) `
        -Commits $commits -ManifestSha256 $manifestSha256
    Assert-ReleaseEvidenceRecord -Record $record -Context "device API$($source.buildApi)-on-API24"
    $deviceRecords.Add($record)
}

foreach ($case in @($consumer.cases)) {
    if ($case.status -cne 'PASS' -or [bool]$case.sourceLeak) { throw 'Clean consumer case is invalid.' }
    Assert-ReleaseHash -Value ([string]$case.elfSha256) -Name 'consumer elfSha256'
}
foreach ($package in @($consumer.packages)) {
    Assert-ReleaseHash -Value ([string]$package.sha256) -Name "consumer package $($package.name)"
}

$deviceExecuted = $arm64.device.status -ceq 'EXECUTED'
$release = [ordered]@{
    schemaVersion = 1
    status = if ($deviceExecuted) { 'PASS' } else { 'READY_WITH_DEVICE_DEFERRED' }
    generatedAtUtc = [DateTime]::UtcNow.ToString('o')
    runtimeVersion = [string]$manifest.version
    runtimeManifestSha256 = $manifestSha256
    commits = $commits
    simulator = [ordered]@{
        status = 'PASS'
        recordCount = $simulatorRecords.Count
        records = $simulatorRecords.ToArray()
    }
    arm64 = [ordered]@{
        status = 'READY_FOR_DEVICE'
        deviceStatus = [string]$arm64.device.status
        records = $arm64Records.ToArray()
        deviceRecords = $deviceRecords.ToArray()
    }
    consumer = [ordered]@{
        status = 'PASS'
        runtimeVersion = [string]$consumer.runtimeVersion
        publishAotCrossVersion = [string]$consumer.publishAotCrossVersion
        packages = @($consumer.packages)
        cases = @($consumer.cases)
    }
    sourceEvidence = [ordered]@{
        simulatorEvidenceSha256 = Get-Sha256 -Path $SimulatorEvidencePath
        arm64ReadinessSha256 = Get-Sha256 -Path $Arm64ReadinessPath
        consumerEvidenceSha256 = Get-Sha256 -Path $ConsumerEvidencePath
        producerSha256 = Get-Sha256 -Path $PSCommandPath
    }
}
[IO.File]::WriteAllText(
    $OutputPath,
    (($release | ConvertTo-Json -Depth 15) + "`n"),
    [Text.UTF8Encoding]::new($false))

& (Join-Path $PSScriptRoot 'verify-release-evidence.ps1') -EvidencePath $OutputPath
Write-Output "Wrote canonical release evidence to '$OutputPath'."
