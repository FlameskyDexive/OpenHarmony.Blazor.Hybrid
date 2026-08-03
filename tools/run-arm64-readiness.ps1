[CmdletBinding()]
param(
    [int[]] $Apis = @(13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 26),
    [string] $MatrixRoot = (Join-Path $PSScriptRoot '..\artifacts\hap-matrix'),
    [string] $MatrixCatalogPath = (Join-Path $PSScriptRoot 'openharmony-api-matrix.json'),
    [string] $RuntimeManifestPath = (Join-Path $PSScriptRoot '..\ThirdParty\OpenHarmony.NET.Runtime\release\10.0.10-ohos.2-preview.1\manifest.json'),
    [string] $SdkRoot = "$env:LOCALAPPDATA\OpenHarmony\Sdk",
    [string] $EvidenceRoot = (Join-Path $PSScriptRoot '..\artifacts\arm64-readiness'),
    [string] $PrivateEvidenceRoot,
    [string] $HapSignToolPath = (Join-Path $env:ProgramFiles 'Huawei\DevEco Studio\sdk\default\openharmony\toolchains\lib\hap-sign-tool.jar'),
    [string] $JavaPath = 'java',
    [string] $ReadElfPath,
    [string] $SignatureVerifierPath = (Join-Path $PSScriptRoot 'verify-hap-signature.ps1'),
    [switch] $RunDeviceAcceptance,
    [string] $HdcPath = 'hdc',
    [string] $Target,
    [int] $DeviceApiLevel = 24,
    [string] $DeviceAcceptanceScript = (Join-Path $PSScriptRoot 'run-device-acceptance.ps1'),
    [string] $DeviceEvidenceRoot = (Join-Path $PSScriptRoot '..\artifacts\device-evidence'),
    [ValidatePattern('^[A-Za-z0-9._-]{1,128}$')]
    [string] $EvidenceRunId = ("arm64-readiness-{0}" -f [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ'))
)

$ErrorActionPreference = 'Stop'
$abi = 'arm64-v8a'
$runtimeBaselineApi = 13

function Resolve-ExecutablePath {
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

function Write-Json {
    param(
        [Parameter(Mandatory = $true)][string] $Path,
        [Parameter(Mandatory = $true)] $Value
    )

    New-Item -ItemType Directory -Path (Split-Path -Parent $Path) -Force | Out-Null
    [IO.File]::WriteAllText(
        $Path,
        (($Value | ConvertTo-Json -Depth 15) + "`n"),
        [Text.UTF8Encoding]::new($false))
}

function Test-Arm64StaticThunkLayout {
    param([Parameter(Mandatory = $true)][byte[]] $Bytes)

    $pageSize = 0x1000
    $codePages = 8
    $codeSize = $pageSize * $codePages
    $dataSize = 0x8000
    $totalSize = $codeSize + $dataSize
    $thunksPerPage = 0xff
    $branchInstruction = [Convert]::ToUInt32('d61f0220', 16)
    $breakInstruction = [Convert]::ToUInt32('d43e0000', 16)
    $nopInstruction = [Convert]::ToUInt32('d503201f', 16)
    $candidate = -1

    for ($start = 0; $start -le ($Bytes.Length - $totalSize); $start += $pageSize) {
        if ([BitConverter]::ToUInt32($Bytes, $start) -ne [uint32]0x10040010) { continue }
        $valid = $true
        for ($block = 0; $block -lt $codePages -and $valid; $block++) {
            $page = $start + ($block * $pageSize)
            for ($index = 0; $index -lt $thunksPerPage; $index++) {
                $offset = $page + ($index * 0x10)
                $ldrOffset = 0xff8 - ($index * 0x10)
                $expectedLdr = [uint32](0xf9400000L -bor (([uint32]($ldrOffset / 8)) -shl 10) -bor (16 -shl 5) -bor 17)
                if ([BitConverter]::ToUInt32($Bytes, $offset) -ne [uint32]0x10040010 -or
                    [BitConverter]::ToUInt32($Bytes, $offset + 4) -ne $expectedLdr -or
                    [BitConverter]::ToUInt32($Bytes, $offset + 8) -ne $branchInstruction -or
                    [BitConverter]::ToUInt32($Bytes, $offset + 12) -ne $breakInstruction) {
                    $valid = $false
                    break
                }
            }
            for ($padding = 0xff0; $padding -lt $pageSize -and $valid; $padding += 4) {
                if ([BitConverter]::ToUInt32($Bytes, $page + $padding) -ne $nopInstruction) {
                    $valid = $false
                }
            }
        }
        if (-not $valid) { continue }
        for ($offset = $start + $codeSize; $offset -lt ($start + $totalSize); $offset++) {
            if ($Bytes[$offset] -ne 0) {
                $valid = $false
                break
            }
        }
        if ($valid) {
            $candidate = $start
            break
        }
    }

    if ($candidate -lt 0) {
        throw 'Entry.so does not contain the required OpenHarmony arm64 static thunk layout.'
    }
    return [pscustomobject][ordered]@{
        status = 'VERIFIED'
        fileOffset = $candidate
        pageSize = $pageSize
        codePages = $codePages
        thunksPerPage = $thunksPerPage
        codeSize = $codeSize
        dataSize = $dataSize
    }
}

function Get-Arm64DeviceAcceptancePlan {
    param(
        [Parameter(Mandatory = $true)][int[]] $SupportedApis,
        [Parameter(Mandatory = $true)][int[]] $AvailableApis,
        [Parameter(Mandatory = $true)][int] $DeviceApiLevel
    )

    foreach ($api in @($SupportedApis | Where-Object { $_ -le $DeviceApiLevel -and $_ -ne 25 } | Sort-Object -Unique)) {
        [pscustomobject][ordered]@{
            buildApi = [int]$api
            runtimeBaselineApi = 13
            deviceApi = $DeviceApiLevel
            abi = 'arm64-v8a'
            hardGate = ($api -in @(13, 14))
            status = if ($api -in $AvailableApis) { 'READY_FOR_DEVICE' } else { 'SKIPPED' }
        }
    }
}

function Invoke-ReadElf {
    param(
        [Parameter(Mandatory = $true)][string] $Executable,
        [Parameter(Mandatory = $true)][string[]] $Arguments
    )

    $previousPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $output = @(& $Executable @Arguments 2>&1)
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousPreference
    }
    if ($exitCode -ne 0) { throw "llvm-readelf failed with exit code $exitCode." }
    return (($output | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine)
}

function Get-PackedArm64Entry {
    param(
        [Parameter(Mandatory = $true)][string] $HapPath,
        [Parameter(Mandatory = $true)][string] $DestinationPath
    )

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [IO.Compression.ZipFile]::OpenRead($HapPath)
    try {
        $entries = @($archive.Entries | Where-Object {
            $_.FullName.Equals('libs/arm64-v8a/Entry.so', [StringComparison]::Ordinal)
        })
        if ($entries.Count -ne 1) { throw 'HAP must contain exactly one libs/arm64-v8a/Entry.so.' }
        [IO.Compression.ZipFileExtensions]::ExtractToFile($entries[0], $DestinationPath, $true)
    }
    finally {
        $archive.Dispose()
    }
}

function Get-ConnectedArm64Api24Target {
    param(
        [Parameter(Mandatory = $true)][string] $Executable,
        [string] $RequestedTarget,
        [Parameter(Mandatory = $true)][int] $ExpectedApi
    )

    $lines = @(& $Executable list targets 2>&1 | ForEach-Object { $_.ToString().Trim() } | Where-Object {
        $_ -and $_ -ne '[Empty]'
    })
    if ($LASTEXITCODE -ne 0) { throw 'Unable to list HDC targets.' }
    $records = @($lines | ForEach-Object {
        $parts = @($_ -split '\s+')
        [pscustomobject]@{
            id = $parts[0]
            usb = ($parts -contains 'USB')
            connected = (-not ($parts -contains 'Offline')) -and (($parts -contains 'Connected') -or $parts.Count -eq 1)
            typed = ($parts.Count -gt 1)
        }
    } | Where-Object connected)
    if ($RequestedTarget) {
        $records = @($records | Where-Object id -ceq $RequestedTarget)
    }
    elseif (@($records | Where-Object typed).Count -gt 0) {
        $usbRecords = @($records | Where-Object usb)
        $records = $usbRecords
    }
    if ($records.Count -ne 1) { throw 'No connected arm64 USB HDC target is available.' }
    $targetId = $records[0].id
    $arch = ((@(& $Executable -t $targetId shell uname -m 2>&1) | ForEach-Object { $_.ToString() }) -join '').Trim()
    if ($LASTEXITCODE -ne 0 -or $arch -notmatch '^(aarch64|arm64)$') {
        throw "HDC target architecture '$arch' is not arm64."
    }
    $apiText = ((@(& $Executable -t $targetId shell param get const.ohos.apiversion 2>&1) | ForEach-Object { $_.ToString() }) -join '').Trim()
    if ($LASTEXITCODE -ne 0 -or $apiText -notmatch '\d+' -or [int]$Matches[0] -ne $ExpectedApi) {
        throw "The connected arm64 target does not report API$ExpectedApi."
    }
    return $targetId
}

if ($MyInvocation.InvocationName -eq '.') { return }

New-Item -ItemType Directory -Path $EvidenceRoot -Force | Out-Null
$evidenceRootPath = (Resolve-Path -LiteralPath $EvidenceRoot).Path
$evidencePath = Join-Path $evidenceRootPath 'arm64-readiness.json'
Remove-Item -LiteralPath $evidencePath -Force -ErrorAction SilentlyContinue

if ($Apis.Count -ne 13 -or @($Apis | Sort-Object -Unique).Count -ne 13 -or $Apis -contains 25) {
    throw 'arm64 readiness requires exactly API13-24 and API26; API25 is unsupported.'
}
foreach ($path in $MatrixCatalogPath, $RuntimeManifestPath, $SignatureVerifierPath) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Required input was not found: $path" }
}
if (-not (Test-Path -LiteralPath $HapSignToolPath -PathType Leaf)) {
    throw "HAP signing tool was not found: $HapSignToolPath"
}

$matrixRootPath = (Resolve-Path -LiteralPath $MatrixRoot).Path
$matrix = Get-Content -LiteralPath $MatrixCatalogPath -Raw | ConvertFrom-Json
$runtimeManifestRaw = Get-Content -LiteralPath $RuntimeManifestPath -Raw
$runtimeManifest = $runtimeManifestRaw | ConvertFrom-Json
if ($runtimeManifestRaw -match '(?i)[A-Z]:[\\/](?:Users|Engine)[\\/]') {
    throw 'Runtime release manifest contains a developer-local absolute path.'
}
if ([int]$runtimeManifest.runtimeBaselineApi -ne $runtimeBaselineApi) {
    throw 'Runtime release manifest baseline must be API13.'
}

$catalogApis = @($matrix.entries | ForEach-Object { [int]$_.api } | Sort-Object -Unique)
$requestedApis = @($Apis | Sort-Object -Unique)
if (($catalogApis -join ',') -cne ($requestedApis -join ',')) {
    throw 'HAP matrix catalog does not exactly cover the requested APIs.'
}
$manifestApis = @($runtimeManifest.supportedApis | ForEach-Object { [int]$_ } | Sort-Object -Unique)
if (($manifestApis -join ',') -cne ($requestedApis -join ',')) {
    throw 'Runtime release manifest does not exactly cover the requested APIs.'
}

$arm64Package = @($runtimeManifest.packages | Where-Object {
    [int]$_.apiLevel -eq 13 -and $_.abi -ceq $abi
})
if ($arm64Package.Count -ne 1 -or $arm64Package[0].root -cne 'arm64-v8a/runtime-pack') {
    throw 'Runtime release manifest must contain exactly one API13 arm64 baseline package.'
}
$packageProvenance = @($arm64Package[0].files | Where-Object path -ceq 'provenance/runtime-build-provenance.json')
if ($packageProvenance.Count -ne 1 -or $packageProvenance[0].sha256 -notmatch '^[0-9a-f]{64}$') {
    throw 'The arm64 baseline package is missing hashed runtime provenance.'
}

if ([string]::IsNullOrWhiteSpace($ReadElfPath)) {
    $ReadElfPath = Join-Path $SdkRoot '13\native\llvm\bin\llvm-readelf.exe'
}
$resolvedReadElf = Resolve-ExecutablePath -Path $ReadElfPath
$resolvedJava = Resolve-ExecutablePath -Path $JavaPath

if ([string]::IsNullOrWhiteSpace($PrivateEvidenceRoot)) {
    $PrivateEvidenceRoot = Join-Path ([IO.Path]::GetTempPath()) ("openharmony-arm64-readiness-{0}" -f [Guid]::NewGuid().ToString('N'))
}
New-Item -ItemType Directory -Path $PrivateEvidenceRoot -Force | Out-Null
$privateRoot = (Resolve-Path -LiteralPath $PrivateEvidenceRoot).Path
$cases = [Collections.Generic.List[object]]::new()
$availableApis = [Collections.Generic.List[int]]::new()

foreach ($api in $requestedApis) {
    $catalogEntry = @($matrix.entries | Where-Object { [int]$_.api -eq $api })
    $compatibilityEntry = @($runtimeManifest.compatibilityEntries | Where-Object {
        [int]$_.buildApi -eq $api -and $_.abi -ceq $abi
    })
    if ($compatibilityEntry.Count -ne 1 -or [int]$compatibilityEntry[0].runtimeApi -ne 13 -or
        $compatibilityEntry[0].root -cne 'arm64-v8a/runtime-pack' -or
        $compatibilityEntry[0].compatibilityKind -cne 'alias' -or
        [bool]$compatibilityEntry[0].sourceDirty -or
        $compatibilityEntry[0].provenanceSha256 -cne $packageProvenance[0].sha256) {
        throw "Runtime manifest entry is not clean API13 provenance for API$api/$abi."
    }

    $caseRoot = Join-Path $matrixRootPath "api$api\$abi"
    $metadataPath = Join-Path $caseRoot 'build-metadata.json'
    if (-not (Test-Path -LiteralPath $metadataPath -PathType Leaf)) {
        throw "HAP matrix metadata was not found for API$api/$abi."
    }
    $metadata = Get-Content -LiteralPath $metadataPath -Raw | ConvertFrom-Json
    $hapPath = Join-Path $caseRoot 'entry-default-signed.hap'
    if (-not [bool]$catalogEntry[0].nativeSdkAvailable) {
        if ($metadata.status -cne 'SKIPPED' -or (Test-Path -LiteralPath $hapPath) -or
            [string]::IsNullOrWhiteSpace([string]$metadata.reason)) {
            throw "Unavailable API$api must have one explicit SKIPPED metadata record and no fabricated HAP."
        }
        $cases.Add([pscustomobject][ordered]@{
            status = 'SKIPPED'
            buildApi = $api
            runtimeBaselineApi = 13
            abi = $abi
            reason = [string]$metadata.reason
            runtimeManifestEntry = $compatibilityEntry[0]
        })
        continue
    }

    $sdkManifest = Join-Path (Join-Path $SdkRoot ([string]$catalogEntry[0].sdkFolder)) 'native\oh-uni-package.json'
    if (-not (Test-Path -LiteralPath $sdkManifest -PathType Leaf)) {
        throw "Installed Native SDK manifest was not found for API$api."
    }
    if ($metadata.status -cne 'PASS' -or [int]$metadata.buildApi -ne $api -or
        [int]$metadata.runtimeBaselineApi -ne 13 -or $metadata.abi -cne $abi -or
        -not (Test-Path -LiteralPath $hapPath -PathType Leaf)) {
        throw "Built arm64 HAP metadata is invalid for API$api."
    }
    $hapSha256 = Get-Sha256 -Path $hapPath
    if ($hapSha256 -cne [string]$metadata.hapSha256) {
        throw "HAP SHA-256 does not match build metadata for API$api."
    }
    if ([bool]$metadata.runtimeManifestEntry.sourceDirty -or
        $metadata.runtimeManifestEntry.provenanceSha256 -cne $compatibilityEntry[0].provenanceSha256) {
        throw "HAP metadata is not bound to clean runtime provenance for API$api."
    }

    $casePrivateRoot = Join-Path $privateRoot "api$api-$abi"
    New-Item -ItemType Directory -Path $casePrivateRoot -Force | Out-Null
    $signature = & $SignatureVerifierPath -HapPath $hapPath -HapSignToolPath $HapSignToolPath `
        -JavaPath $resolvedJava -OutputDirectory $casePrivateRoot -ArtifactPrefix "api$api-$abi"
    if (-not [bool]$signature.SignatureVerified -or (Get-Sha256 -Path $hapPath) -cne $hapSha256) {
        throw "HAP signature policy verification failed for API$api."
    }

    $entryPath = Join-Path $casePrivateRoot 'packed-Entry.so'
    Get-PackedArm64Entry -HapPath $hapPath -DestinationPath $entryPath
    $entrySha256 = Get-Sha256 -Path $entryPath
    if ($entrySha256 -cne [string]$metadata.packagedEntrySoSha256) {
        throw "Packaged Entry.so SHA-256 does not match build metadata for API$api."
    }
    $header = Invoke-ReadElf -Executable $resolvedReadElf -Arguments @('-h', $entryPath)
    $dynamic = Invoke-ReadElf -Executable $resolvedReadElf -Arguments @('-d', $entryPath)
    $symbols = Invoke-ReadElf -Executable $resolvedReadElf -Arguments @('--dyn-syms', '-W', $entryPath)
    if ($header -notmatch '(?m)^\s*Machine:\s+.*AArch64') {
        throw "Packaged Entry.so is not AArch64 for API$api."
    }
    if ($dynamic -notmatch 'Shared library: \[libc\.so\]' -or
        $dynamic -notmatch 'Shared library: \[libc\+\+_shared\.so\]') {
        throw "Packaged Entry.so does not import the required OpenHarmony libraries for API$api."
    }
    if (($dynamic + "`n" + $symbols) -match '(?i)\b(?:get_mempolicy|set_mempolicy|mbind|move_pages|numa_available)\b') {
        throw "Packaged Entry.so contains a forbidden NUMA import for API$api."
    }
    $thunkLayout = Test-Arm64StaticThunkLayout -Bytes ([IO.File]::ReadAllBytes($entryPath))
    Remove-Item -LiteralPath $entryPath -Force

    $availableApis.Add($api)
    $cases.Add([pscustomobject][ordered]@{
        status = 'READY_FOR_DEVICE'
        buildApi = $api
        runtimeBaselineApi = 13
        abi = $abi
        hapSha256 = $hapSha256
        entrySoSha256 = $entrySha256
        signatureVerified = $true
        signature = [ordered]@{
            policy = 'hap-sign-tool verify-app and verify-profile'
            verificationLogSha256 = $signature.VerificationLogSha256
            certificateChainSha256 = $signature.CertificateChainSha256
            signerCertificateSha256 = $signature.SignerCertificateSha256
            signingProfileSha256 = $signature.SigningProfileSha256
        }
        elf = [ordered]@{
            machine = 'AArch64'
            needed = @('libc.so', 'libc++_shared.so')
            forbiddenNumaImports = @()
        }
        staticThunkLayout = $thunkLayout
        runtimeManifestEntry = $compatibilityEntry[0]
    })
}

$device = [ordered]@{
    status = 'NOT_REQUESTED'
    deviceApi = $DeviceApiLevel
    abi = $abi
    cases = @()
}

if ($RunDeviceAcceptance) {
    if ($DeviceApiLevel -ne 24) { throw 'arm64 device acceptance is pinned to API24.' }
    if (-not (Test-Path -LiteralPath $DeviceAcceptanceScript -PathType Leaf)) {
        throw "Device acceptance script was not found: $DeviceAcceptanceScript"
    }
    $resolvedHdc = Resolve-ExecutablePath -Path $HdcPath
    $targetId = Get-ConnectedArm64Api24Target -Executable $resolvedHdc -RequestedTarget $Target -ExpectedApi 24
    $devicePlan = @(Get-Arm64DeviceAcceptancePlan -SupportedApis $requestedApis -AvailableApis $availableApis.ToArray() -DeviceApiLevel 24)
    $hardGate = @($devicePlan | Where-Object hardGate)
    if ($hardGate.Count -ne 2 -or @($hardGate | Where-Object status -ne 'READY_FOR_DEVICE').Count -ne 0) {
        throw 'API13 and API14 arm64 HAPs must both be ready before API24 device execution.'
    }
    $deviceCases = [Collections.Generic.List[object]]::new()
    foreach ($row in $devicePlan) {
        if ($row.status -eq 'SKIPPED') {
            $deviceCases.Add([pscustomobject][ordered]@{
                status = 'SKIPPED'
                buildApi = $row.buildApi
                runtimeBaselineApi = 13
                deviceApi = 24
                abi = $abi
                hardGate = $row.hardGate
                reason = 'No independent installable Native SDK/HAP exists for this build API; device compatibility was not fabricated.'
            })
            continue
        }
        $metadataPath = Join-Path $matrixRootPath "api$($row.buildApi)\$abi\build-metadata.json"
        $metadata = Get-Content -LiteralPath $metadataPath -Raw | ConvertFrom-Json
        $pairRoot = Join-Path $DeviceEvidenceRoot "api$($row.buildApi)-on-api24-arm64"
        $pairPrivate = Join-Path $privateRoot "device-api$($row.buildApi)-on-api24"
        $runId = "$EvidenceRunId-api$($row.buildApi)-on-api24"
        & $DeviceAcceptanceScript -Abi $abi `
            -HapPath (Join-Path $matrixRootPath "api$($row.buildApi)\$abi\entry-default-signed.hap") `
            -HdcPath $resolvedHdc -Target $targetId -ApiLevel $row.buildApi -DeviceApiLevel 24 `
            -ExpectedRuntimeBaselineApi 13 -EvidenceRoot $pairRoot -JavaPath $resolvedJava `
            -HapSignToolPath $HapSignToolPath -SampleCommit ([string]$metadata.commits.sample) `
            -EvidenceRunId $runId -ExpectedSmokeRunId "matrix-api$($row.buildApi)-$abi" `
            -PrivateEvidenceRoot $pairPrivate -RequireUiInteraction
        $pairEvidencePath = Join-Path $pairRoot "api$($row.buildApi)-$abi-evidence.json"
        $pairEvidence = Get-Content -LiteralPath $pairEvidencePath -Raw | ConvertFrom-Json
        if ($pairEvidence.result -cne 'PASS' -or $pairEvidence.uiAttestation.status -cne 'PASS' -or
            [int]$pairEvidence.buildApi -ne $row.buildApi -or [int]$pairEvidence.deviceApi -ne 24) {
            throw "API$($row.buildApi)-on-API24 arm64 device evidence is incomplete."
        }
        $deviceCases.Add([pscustomobject][ordered]@{
            status = 'PASS'
            buildApi = $row.buildApi
            runtimeBaselineApi = 13
            deviceApi = 24
            abi = $abi
            hardGate = $row.hardGate
            evidenceSha256 = Get-Sha256 -Path $pairEvidencePath
        })
    }
    $device.status = 'EXECUTED'
    $device.cases = $deviceCases.ToArray()
}

$readyCount = @($cases | Where-Object status -eq 'READY_FOR_DEVICE').Count
$skippedCount = @($cases | Where-Object status -eq 'SKIPPED').Count
$evidence = [ordered]@{
    schemaVersion = 1
    status = 'READY_FOR_DEVICE'
    completedAtUtc = [DateTime]::UtcNow.ToString('o')
    evidenceRunId = $EvidenceRunId
    abi = $abi
    runtimeBaselineApi = 13
    logicalApiCount = $requestedApis.Count
    verifiedHapCount = $readyCount
    skippedApiCount = $skippedCount
    runtimeManifestSha256 = Get-Sha256 -Path $RuntimeManifestPath
    matrixCatalogSha256 = Get-Sha256 -Path $MatrixCatalogPath
    signaturePolicySha256 = Get-Sha256 -Path $SignatureVerifierPath
    readElfSha256 = Get-Sha256 -Path $resolvedReadElf
    cases = $cases.ToArray()
    device = $device
}
Write-Json -Path $evidencePath -Value $evidence

Write-Output "READY_FOR_DEVICE: verified $readyCount arm64 HAPs; recorded $skippedCount unavailable SDK rows in '$evidencePath'."
