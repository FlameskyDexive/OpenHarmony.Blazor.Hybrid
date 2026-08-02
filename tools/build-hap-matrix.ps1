[CmdletBinding()]
param(
    [int[]] $Apis = @(13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 26),
    [ValidateSet('arm64-v8a', 'x86_64')][string[]] $Abis = @('arm64-v8a', 'x86_64'),
    [string] $SdkRoot = "$env:LOCALAPPDATA\OpenHarmony\Sdk",
    [string] $RuntimeRoot = (Join-Path $PSScriptRoot '..\ThirdParty\OpenHarmony.NET.Runtime\releases\10.0.10-ohos.2-preview.1'),
    [string] $RuntimeVersion = '10.0.10-ohos.2-preview.1',
    [string] $OutputRoot = (Join-Path $PSScriptRoot '..\artifacts\hap-matrix'),
    [string] $HvigorPath = 'hvigorw',
    [string] $DevEcoSdkHome = 'C:\Program Files\Huawei\DevEco Studio\sdk'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$matrix = Get-Content (Join-Path $PSScriptRoot 'openharmony-api-matrix.json') -Raw | ConvertFrom-Json
$manifestPath = Join-Path $RuntimeRoot 'manifest.json'
if (-not (Test-Path $manifestPath -PathType Leaf)) { throw "Runtime manifest was not found: $manifestPath" }
$runtimeManifest = Get-Content $manifestPath -Raw | ConvertFrom-Json
if ($runtimeManifest.runtimeBaselineApi -ne 13) { throw 'Runtime manifest baseline must be API13.' }
if (-not (Test-Path (Join-Path $DevEcoSdkHome 'default\sdk-pkg.json') -PathType Leaf)) { throw "Invalid DevEco SDK home: $DevEcoSdkHome" }
$env:DEVECO_SDK_HOME = (Resolve-Path $DevEcoSdkHome).Path
$hvigor = if (Test-Path $HvigorPath -PathType Leaf) { (Resolve-Path $HvigorPath).Path } else { (Get-Command $HvigorPath -ErrorAction Stop).Source }

function Get-Commit([string] $Path) { (& git -C $Path rev-parse HEAD).Trim() }
function Get-Hash([string] $Path) { (Get-FileHash $Path -Algorithm SHA256).Hash.ToLowerInvariant() }
function Write-Json([string] $Path, $Value) {
    New-Item -ItemType Directory -Path (Split-Path $Path) -Force | Out-Null
    [IO.File]::WriteAllText($Path, (($Value | ConvertTo-Json -Depth 12) + "`n"), [Text.UTF8Encoding]::new($false))
}
function Assert-EntryElf([string] $Path, [string] $Abi, [string] $NativeSdkRoot) {
    $readElf = Join-Path $NativeSdkRoot 'llvm\bin\llvm-readelf.exe'
    if (-not (Test-Path $readElf -PathType Leaf)) { throw "llvm-readelf was not found: $readElf" }
    $header = (& $readElf -h $Path | Out-String)
    if ($LASTEXITCODE -ne 0 -or $header -notmatch 'ELF Header:') { throw "Entry.so is not a readable ELF: $Path" }
    $expectedMachine = if ($Abi -eq 'arm64-v8a') { 'AArch64' } else { 'X86-64' }
    $machinePattern = if ($expectedMachine -eq 'X86-64') { 'X86-64' } else { [regex]::Escape($expectedMachine) }
    if ($header -notmatch "(?m)^\s*Machine:\s+.*$machinePattern") {
        throw "Entry.so machine does not match ${Abi}: $Path"
    }
    $dynamic = (& $readElf -d $Path | Out-String)
    if ($LASTEXITCODE -ne 0 -or $dynamic -notmatch 'Shared library: \[libc\.so\]' -or
        $dynamic -notmatch 'Shared library: \[libc\+\+_shared\.so\]') {
        throw "Entry.so imports do not contain libc.so and libc++_shared.so: $Path"
    }
    [ordered]@{
        machine = $expectedMachine
        needed = @('libc.so', 'libc++_shared.so')
    }
}

$commits = [ordered]@{
    sample = Get-Commit $repoRoot
    runtime = Get-Commit (Join-Path $repoRoot 'ThirdParty\OpenHarmony.NET.Runtime')
    bindings = Get-Commit (Join-Path $repoRoot 'ThirdParty\OpenHarmony.NDK.Bindings')
    publishAotCross = Get-Commit (Join-Path $repoRoot 'ThirdParty\PublishAotCross')
}
$buildProfilePath = Join-Path $repoRoot 'OHOS_Project\build-profile.json5'

foreach ($api in $Apis) {
    $entry = @($matrix.entries | Where-Object api -eq $api)
    if ($entry.Count -ne 1) { throw "Matrix must contain exactly one API $api entry." }
    foreach ($abi in $Abis) {
        $caseRoot = Join-Path $OutputRoot "api$api\$abi"
        $metadataPath = Join-Path $caseRoot 'build-metadata.json'
        if (-not $entry[0].nativeSdkAvailable) {
            Write-Json $metadataPath ([ordered]@{
                status = 'SKIPPED'; buildApi = $api; runtimeBaselineApi = 13; abi = $abi
                reason = 'No independent installable Native SDK package exists; emulator compatibility remains a run-only target.'
            })
            continue
        }

        $runtimeEntry = @($runtimeManifest.compatibilityEntries | Where-Object { $_.buildApi -eq $api -and $_.abi -eq $abi })
        if ($runtimeEntry.Count -ne 1 -or $runtimeEntry[0].sourceDirty) { throw "Runtime manifest entry is invalid for API$api/$abi." }
        $profile = if ($abi -eq 'arm64-v8a') { 'PublishArm64' } else { 'Publishx86_64' }
        $rid = if ($abi -eq 'arm64-v8a') { 'linux-musl-arm64' } else { 'linux-musl-x64' }
        $nativeSdkRoot = Join-Path (Join-Path $SdkRoot $entry[0].sdkFolder) 'native'
        if (-not (Test-Path (Join-Path $nativeSdkRoot 'oh-uni-package.json') -PathType Leaf)) {
            throw "Native SDK manifest was not found for API${api}: $nativeSdkRoot"
        }
        & dotnet restore (Join-Path $repoRoot 'Src\Entry\Entry.csproj') `
            -p:RuntimeIdentifier=$rid -p:OpenHarmonyApiLevel=$api -p:OpenHarmonySdkRoot=$SdkRoot `
            -p:OpenHarmonyRuntimePackageRoot=$RuntimeRoot -p:OpenHarmonyRuntimeVersion=$RuntimeVersion `
            -p:OpenHarmonyRuntimeBaselineApi=13 --verbosity quiet
        if ($LASTEXITCODE -ne 0) { throw "NativeAOT restore failed for API$api/$abi." }
        & dotnet clean (Join-Path $repoRoot 'Src\Entry\Entry.csproj') `
            -p:PublishProfile=$profile -p:RuntimeIdentifier=$rid -p:OpenHarmonyAbi=$abi `
            -p:OpenHarmonyApiLevel=$api -p:OpenHarmonySdkRoot=$SdkRoot `
            -p:OpenHarmonyRuntimePackageRoot=$RuntimeRoot -p:OpenHarmonyRuntimeVersion=$RuntimeVersion `
            -p:OpenHarmonyRuntimeBaselineApi=13 --verbosity quiet
        if ($LASTEXITCODE -ne 0) { throw "NativeAOT clean failed for API$api/$abi." }
        & dotnet publish (Join-Path $repoRoot 'Src\Entry\Entry.csproj') `
            -p:PublishProfile=$profile -p:RuntimeIdentifier=$rid -p:OpenHarmonyAbi=$abi `
            -p:OpenHarmonyApiLevel=$api -p:OpenHarmonySdkRoot=$SdkRoot `
            -p:OpenHarmonyRuntimePackageRoot=$RuntimeRoot -p:OpenHarmonyRuntimeVersion=$RuntimeVersion `
            -p:OpenHarmonyRuntimeBaselineApi=13 -p:OpenHarmonySampleCommit=$($commits.sample) `
            -p:OpenHarmonyEvidenceRunId="matrix-api$api-$abi" --verbosity minimal
        if ($LASTEXITCODE -ne 0) { throw "NativeAOT publish failed for API$api/$abi." }

        $entrySo = Join-Path $repoRoot "OHOS_Project\entry\libs\$abi\Entry.so"
        if (-not (Test-Path $entrySo -PathType Leaf)) { throw "Published Entry.so was not staged for API$api/$abi." }
        $elf = Assert-EntryElf $entrySo $abi $nativeSdkRoot
        $originalProfile = Get-Content $buildProfilePath -Raw
        try {
            $temporaryProfile = [regex]::Replace($originalProfile, '"compatibleSdkVersion"\s*:\s*"[^"]+"', "`"compatibleSdkVersion`": `"$($entry[0].compatibleSdkVersion)`"", 1)
            [IO.File]::WriteAllText($buildProfilePath, $temporaryProfile, [Text.UTF8Encoding]::new($false))
            Push-Location (Join-Path $repoRoot 'OHOS_Project')
            try {
                & $hvigor --mode module -p product=default -p module=entry@default -p buildMode=debug assembleHap --no-daemon
                if ($LASTEXITCODE -ne 0) { throw "Hvigor failed for API$api/$abi." }
            }
            finally { Pop-Location }
        }
        finally { [IO.File]::WriteAllText($buildProfilePath, $originalProfile, [Text.UTF8Encoding]::new($false)) }

        $hap = Get-ChildItem (Join-Path $repoRoot 'OHOS_Project\entry\build') -Recurse -Filter '*-signed.hap' |
            Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
        if (-not $hap) { throw "Signed HAP was not produced for API$api/$abi." }
        New-Item -ItemType Directory -Path $caseRoot -Force | Out-Null
        $targetHap = Join-Path $caseRoot 'entry-default-signed.hap'
        Copy-Item $hap.FullName $targetHap -Force
        $strippedEntry = Join-Path $repoRoot "OHOS_Project\entry\build\default\intermediates\stripped_native_libs\default\$abi\Entry.so"
        if (-not (Test-Path $strippedEntry -PathType Leaf)) { throw "Hvigor stripped Entry.so was not found for $abi." }
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $archive = [IO.Compression.ZipFile]::OpenRead($targetHap)
        try {
            $packedEntry = @($archive.Entries | Where-Object { $_.FullName -match "(^|/)($([regex]::Escape($abi)))/Entry\.so$" })
            if ($packedEntry.Count -ne 1) { throw "HAP must contain exactly one $abi/Entry.so." }
            $tempEntry = Join-Path $caseRoot 'packed-Entry.so'
            [IO.Compression.ZipFileExtensions]::ExtractToFile($packedEntry[0], $tempEntry, $true)
            if ((Get-Hash $tempEntry) -ne (Get-Hash $strippedEntry)) { throw 'Packaged Entry.so differs from the Hvigor stripped library.' }
        }
        finally { $archive.Dispose() }
        Write-Json $metadataPath ([ordered]@{
            status = 'PASS'; buildApi = $api; runtimeBaselineApi = 13; abi = $abi
            sdkFolder = $entry[0].sdkFolder; product = $entry[0].product; hvigorProduct = 'default'
            elf = $elf
            hapSha256 = Get-Hash $targetHap; entrySoSha256 = Get-Hash $entrySo
            strippedEntrySoSha256 = Get-Hash $strippedEntry; packagedEntrySoSha256 = Get-Hash $tempEntry
            runtimeManifestEntry = $runtimeEntry[0]; commits = $commits
        })
    }
}
