[CmdletBinding()]
param(
    [string] $EvidencePath,
    [switch] $RequireDeviceEvidence
)

$ErrorActionPreference = 'Stop'

function Assert-ReleaseCommit {
    param(
        [AllowNull()][AllowEmptyString()][string] $Value,
        [Parameter(Mandatory = $true)][string] $Name
    )

    if ($Value -cnotmatch '^[0-9a-f]{40}$' -or $Value -in @('unknown', 'dirty')) {
        throw "$Name must be a full lowercase immutable Git commit."
    }
}

function Assert-ReleaseHash {
    param(
        [AllowNull()][AllowEmptyString()][string] $Value,
        [Parameter(Mandatory = $true)][string] $Name
    )

    if ($Value -cnotmatch '^[0-9a-f]{64}$') { throw "$Name must be a lowercase SHA-256 value." }
}

function Assert-ReleaseEvidenceRecord {
    param(
        [Parameter(Mandatory = $true)] $Record,
        [Parameter(Mandatory = $true)][string] $Context
    )

    $required = @(
        'testResult', 'buildApi', 'runtimeBaselineApi', 'deviceApi', 'abi', 'hapSha256',
        'runtimeManifestSha256', 'runtimeSourceCommit', 'bindingsCommit',
        'publishAotCrossCommit', 'runtimePackageCommit', 'sampleCommit')
    foreach ($name in $required) {
        if ($Record.PSObject.Properties.Name -notcontains $name) { throw "$Context is missing '$name'." }
    }
    if ([int]$Record.buildApi -eq 25) { throw "$Context illegally contains API25." }
    if ([int]$Record.buildApi -notin (@(13..24) + 26)) { throw "$Context has an unsupported buildApi." }
    if ([int]$Record.runtimeBaselineApi -ne 13) { throw "$Context runtimeBaselineApi must be 13." }
    if ($Record.abi -notin @('arm64-v8a', 'x86_64')) { throw "$Context has an unsupported ABI." }
    if ($null -ne $Record.deviceApi -and [int]$Record.buildApi -gt [int]$Record.deviceApi) {
        throw "$Context reverses the supported buildApi/deviceApi direction."
    }
    Assert-ReleaseHash -Value ([string]$Record.runtimeManifestSha256) -Name "$Context runtimeManifestSha256"
    foreach ($name in 'runtimeSourceCommit', 'bindingsCommit', 'publishAotCrossCommit', 'runtimePackageCommit', 'sampleCommit') {
        Assert-ReleaseCommit -Value ([string]$Record.$name) -Name "$Context $name"
    }

    switch ([string]$Record.testResult) {
        'PASS' { Assert-ReleaseHash -Value ([string]$Record.hapSha256) -Name "$Context hapSha256" }
        'READY_FOR_DEVICE' {
            Assert-ReleaseHash -Value ([string]$Record.hapSha256) -Name "$Context hapSha256"
            if ($null -ne $Record.deviceApi) { throw "$Context readiness row must not claim a device API." }
        }
        'SKIPPED' {
            if (-not [string]::IsNullOrWhiteSpace([string]$Record.hapSha256)) {
                throw "$Context SKIPPED row must not contain a fabricated hapSha256."
            }
            if ($Record.PSObject.Properties.Name -notcontains 'reason' -or
                [string]::IsNullOrWhiteSpace([string]$Record.reason)) {
                throw "$Context SKIPPED row must contain an explicit reason."
            }
        }
        default { throw "$Context has unsupported testResult '$($Record.testResult)'." }
    }
}

function Assert-ExactCount {
    param([int] $Actual, [int] $Expected, [string] $Name)
    if ($Actual -ne $Expected) { throw "$Name must be $Expected, found $Actual." }
}

if ($MyInvocation.InvocationName -eq '.') { return }
if ([string]::IsNullOrWhiteSpace($EvidencePath) -or -not (Test-Path -LiteralPath $EvidencePath -PathType Leaf)) {
    throw "Release evidence was not found: $EvidencePath"
}

$raw = Get-Content -LiteralPath $EvidencePath -Raw
if ($raw -match '(?i)[A-Z]:[\\/](?:Users|Engine)[\\/]|(?:^|[\\/])(?:runtime|releases)[\\/].*artifacts|"(?:unknown|dirty)"') {
    throw 'Release evidence contains a local artifact path or non-immutable value.'
}
$evidence = $raw | ConvertFrom-Json
if ([int]$evidence.schemaVersion -ne 1) { throw 'Release evidence schemaVersion must be 1.' }
if ($evidence.runtimeVersion -cne '10.0.10-ohos.2-preview.1') { throw 'Release evidence runtimeVersion is invalid.' }
if ($evidence.status -notin @('READY_WITH_DEVICE_DEFERRED', 'PASS')) { throw 'Release evidence status is invalid.' }

$commitNames = @('runtimeSource', 'bindings', 'publishAotCross', 'runtimePackage', 'sample')
foreach ($name in $commitNames) {
    if ($evidence.commits.PSObject.Properties.Name -notcontains $name) { throw "Release commits are missing '$name'." }
    Assert-ReleaseCommit -Value ([string]$evidence.commits.$name) -Name "commits.$name"
}
Assert-ReleaseHash -Value ([string]$evidence.runtimeManifestSha256) -Name 'runtimeManifestSha256'

if ($evidence.simulator.status -cne 'PASS') { throw 'Simulator aggregate must be PASS.' }
Assert-ExactCount -Actual @($evidence.simulator.records).Count -Expected 91 -Name 'simulator record count'
Assert-ExactCount -Actual @($evidence.simulator.records | Where-Object testResult -eq 'PASS').Count -Expected 54 -Name 'simulator PASS count'
Assert-ExactCount -Actual @($evidence.simulator.records | Where-Object testResult -eq 'SKIPPED').Count -Expected 37 -Name 'simulator SKIPPED count'
for ($index = 0; $index -lt @($evidence.simulator.records).Count; $index++) {
    Assert-ReleaseEvidenceRecord -Record $evidence.simulator.records[$index] -Context "simulator.records[$index]"
}

if ($evidence.arm64.status -cne 'READY_FOR_DEVICE') { throw 'arm64 aggregate must remain READY_FOR_DEVICE.' }
Assert-ExactCount -Actual @($evidence.arm64.records).Count -Expected 13 -Name 'arm64 record count'
Assert-ExactCount -Actual @($evidence.arm64.records | Where-Object testResult -eq 'READY_FOR_DEVICE').Count -Expected 7 -Name 'arm64 ready count'
Assert-ExactCount -Actual @($evidence.arm64.records | Where-Object testResult -eq 'SKIPPED').Count -Expected 6 -Name 'arm64 SKIPPED count'
for ($index = 0; $index -lt @($evidence.arm64.records).Count; $index++) {
    Assert-ReleaseEvidenceRecord -Record $evidence.arm64.records[$index] -Context "arm64.records[$index]"
}

if ($evidence.consumer.status -cne 'PASS') { throw 'Clean consumer aggregate must be PASS.' }
Assert-ExactCount -Actual @($evidence.consumer.cases).Count -Expected 4 -Name 'consumer case count'
Assert-ExactCount -Actual @($evidence.consumer.packages).Count -Expected 3 -Name 'consumer package count'
foreach ($case in @($evidence.consumer.cases)) {
    if ($case.status -cne 'PASS' -or [bool]$case.sourceLeak) { throw 'Every clean consumer case must pass without a source leak.' }
    Assert-ReleaseHash -Value ([string]$case.elfSha256) -Name 'consumer elfSha256'
}
foreach ($package in @($evidence.consumer.packages)) {
    Assert-ReleaseHash -Value ([string]$package.sha256) -Name "consumer package $($package.name)"
}
foreach ($name in 'simulatorEvidenceSha256', 'arm64ReadinessSha256', 'consumerEvidenceSha256', 'producerSha256') {
    Assert-ReleaseHash -Value ([string]$evidence.sourceEvidence.$name) -Name "sourceEvidence.$name"
}

if ($RequireDeviceEvidence) {
    if ($evidence.status -cne 'PASS' -or $evidence.arm64.deviceStatus -cne 'EXECUTED') {
        throw 'Release publication requires current API24 arm64 physical-device evidence.'
    }
    Assert-ExactCount -Actual @($evidence.arm64.deviceRecords).Count -Expected 12 -Name 'arm64 device record count'
    Assert-ExactCount -Actual @($evidence.arm64.deviceRecords | Where-Object testResult -eq 'PASS').Count -Expected 6 -Name 'arm64 device PASS count'
    Assert-ExactCount -Actual @($evidence.arm64.deviceRecords | Where-Object testResult -eq 'SKIPPED').Count -Expected 6 -Name 'arm64 device SKIPPED count'
    foreach ($hardGateApi in 13, 14) {
        $gate = @($evidence.arm64.deviceRecords | Where-Object {
            [int]$_.buildApi -eq $hardGateApi -and $_.testResult -ceq 'PASS' -and [int]$_.deviceApi -eq 24
        })
        if ($gate.Count -ne 1) { throw "API$hardGateApi-on-API24 arm64 hard gate is missing." }
    }
}
elseif ($evidence.status -eq 'PASS' -and $evidence.arm64.deviceStatus -ne 'EXECUTED') {
    throw 'Release evidence may be PASS only after API24 arm64 device execution.'
}

Write-Output "Verified OpenHarmony release evidence: $($evidence.status)."
