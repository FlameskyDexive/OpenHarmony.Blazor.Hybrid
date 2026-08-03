[CmdletBinding()]
param(
    [string] $RuntimePackageDirectory,
    [string] $RuntimePackageChecksumsPath,
    [string] $PublishAotCrossPackagePath,
    [string] $PublishAotCrossPackageSha256,
    [string] $SdkRoot = (Join-Path $env:LOCALAPPDATA 'OpenHarmony\Sdk'),
    [string] $OutputRoot = (Join-Path $PSScriptRoot '..\..\artifacts\xengine-consumer'),
    [switch] $KeepWorkDirectory
)

$ErrorActionPreference = 'Stop'

$script:RuntimeVersion = '10.0.10-ohos.2-preview.1'
$script:PublishAotCrossVersion = '42.42.42-dev'
$script:RuntimePackageNames = @(
    "OpenHarmony.NET.Runtime.NativeAot.x86_64.$script:RuntimeVersion.nupkg",
    "OpenHarmony.NET.Runtime.NativeAot.arm64-v8a.$script:RuntimeVersion.nupkg"
)
$script:PublishAotCrossPackageName = "OpenHarmony.NET.PublishAotCross.$script:PublishAotCrossVersion.nupkg"

function Get-CleanConsumerCases {
    @(
        [pscustomobject]@{ Api = 13; Abi = 'x86_64'; Rid = 'linux-musl-x64'; TargetTriple = 'x86_64-linux-ohos'; ElfMachine = 'Advanced Micro Devices X86-64' }
        [pscustomobject]@{ Api = 26; Abi = 'x86_64'; Rid = 'linux-musl-x64'; TargetTriple = 'x86_64-linux-ohos'; ElfMachine = 'Advanced Micro Devices X86-64' }
        [pscustomobject]@{ Api = 13; Abi = 'arm64-v8a'; Rid = 'linux-musl-arm64'; TargetTriple = 'aarch64-linux-ohos'; ElfMachine = 'AArch64' }
        [pscustomobject]@{ Api = 26; Abi = 'arm64-v8a'; Rid = 'linux-musl-arm64'; TargetTriple = 'aarch64-linux-ohos'; ElfMachine = 'AArch64' }
    )
}

function Resolve-LeafPath {
    param([Parameter(Mandatory = $true)][string] $Path, [Parameter(Mandatory = $true)][string] $Description)

    if (-not (Test-Path $Path -PathType Leaf)) { throw "$Description was not found: $Path" }
    return (Resolve-Path $Path).Path
}

function Resolve-CleanConsumerPackageInputs {
    param(
        [Parameter(Mandatory = $true)][string] $RuntimePackageDirectory,
        [Parameter(Mandatory = $true)][string] $PublishAotCrossPackagePath
    )

    if (-not (Test-Path $RuntimePackageDirectory -PathType Container)) {
        throw "Runtime package directory was not found: $RuntimePackageDirectory"
    }

    $runtimePackageDirectoryResolved = (Resolve-Path $RuntimePackageDirectory).Path
    $allRuntimePackages = @(Get-ChildItem -LiteralPath $runtimePackageDirectoryResolved -File -Filter '*.nupkg')
    if ($allRuntimePackages.Count -ne 2) {
        throw "Runtime package directory must contain exactly two runtime packages, found $($allRuntimePackages.Count)."
    }
    $runtimePackages = @($script:RuntimePackageNames | ForEach-Object {
        Resolve-LeafPath -Path (Join-Path $runtimePackageDirectoryResolved $_) -Description 'released runtime package'
    })
    $publishAotCrossPackage = Resolve-LeafPath -Path $PublishAotCrossPackagePath -Description 'PublishAotCross package'
    if ([IO.Path]::GetFileName($publishAotCrossPackage) -cne $script:PublishAotCrossPackageName) {
        throw "PublishAotCross package does not match the immutable release contract: $publishAotCrossPackage"
    }

    return [pscustomobject]@{
        RuntimePackageDirectory = $runtimePackageDirectoryResolved
        RuntimePackages = $runtimePackages
        PublishAotCrossPackage = $publishAotCrossPackage
        SourcePackages = @($runtimePackages + $publishAotCrossPackage)
    }
}

function Assert-CleanConsumerProjectContract {
    param([Parameter(Mandatory = $true)][string] $ProjectPath)

    [xml]$projectXml = Get-Content -LiteralPath (Resolve-LeafPath -Path $ProjectPath -Description 'Consumer project') -Raw
    if ($projectXml.SelectNodes('//ProjectReference').Count -ne 0) {
        throw 'Clean consumer project must not contain ProjectReference.'
    }
    if ($projectXml.SelectNodes('//Import').Count -ne 0 -or $projectXml.SelectNodes('//Reference').Count -ne 0) {
        throw 'Clean consumer project must not import or reference local runtime files.'
    }

    $references = @($projectXml.Project.ItemGroup.PackageReference)
    $expectedReferences = [ordered]@{
        'OpenHarmony.NET.PublishAotCross' = $script:PublishAotCrossVersion
        'OpenHarmony.NET.Runtime.NativeAot.arm64-v8a' = $script:RuntimeVersion
        'OpenHarmony.NET.Runtime.NativeAot.x86_64' = $script:RuntimeVersion
    }
    $actualReferences = @($references | ForEach-Object { "$($_.Include)/$($_.Version)" } | Sort-Object)
    $expectedReferenceValues = @($expectedReferences.GetEnumerator() | ForEach-Object { "$($_.Key)/$($_.Value)" } | Sort-Object)
    if (@(Compare-Object -ReferenceObject $expectedReferenceValues -DifferenceObject $actualReferences).Count -ne 0) {
        throw "Clean consumer project must reference only the immutable released packages: $($expectedReferenceValues -join ', ')"
    }
}

function Get-CleanConsumerForbiddenRoots {
    param(
        [Parameter(Mandatory = $true)][string] $WorkspaceRoot,
        [Parameter(Mandatory = $true)][string] $RuntimePackageDirectory
    )

    $workspaceRootResolved = [IO.Path]::GetFullPath($WorkspaceRoot)
    return @(
        Join-Path $workspaceRootResolved 'runtime'
        Join-Path $workspaceRootResolved 'OpenHarmony.NET.Runtime\releases'
        'OpenHarmony.NET.Runtime\releases'
        [IO.Path]::GetFullPath($RuntimePackageDirectory)
    ) | Sort-Object -Unique
}

function Write-Utf8File {
    param([Parameter(Mandatory = $true)][string] $Path, [Parameter(Mandatory = $true)][string] $Content)

    New-Item -ItemType Directory -Path (Split-Path $Path) -Force | Out-Null
    [IO.File]::WriteAllText($Path, $Content, [Text.UTF8Encoding]::new($false))
}

function New-CleanConsumerNuGetConfig {
    param([Parameter(Mandatory = $true)][string] $FeedRoot)

    $feedXml = [Security.SecurityElement]::Escape([IO.Path]::GetFullPath($FeedRoot))
    return @"
<?xml version="1.0" encoding="utf-8"?>
<configuration>
  <packageSources>
    <clear />
    <add key="released-openharmony" value="$feedXml" />
    <add key="nuget.org" value="https://api.nuget.org/v3/index.json" protocolVersion="3" />
  </packageSources>
  <packageSourceMapping>
    <packageSource key="released-openharmony">
      <package pattern="OpenHarmony.NET.*" />
    </packageSource>
    <packageSource key="nuget.org">
      <package pattern="*" />
    </packageSource>
  </packageSourceMapping>
</configuration>
"@
}

function Write-CleanConsumerEvidence {
    param(
        [Parameter(Mandatory = $true)][string] $Path,
        [Parameter(Mandatory = $true)]$Evidence
    )

    $json = $Evidence | ConvertTo-Json -Depth 10
    $json = $json.TrimEnd("`r", "`n") + "`n"
    $json = $json -replace "`r`n", "`n"
    Write-Utf8File -Path $Path -Content $json
}

function Assert-PublishedPackageHash {
    param(
        [Parameter(Mandatory = $true)][string] $Path,
        [Parameter(Mandatory = $true)][string] $ExpectedSha256
    )

    if ($ExpectedSha256 -notmatch '^[a-fA-F0-9]{64}$') {
        throw "Published SHA-256 must be a 64-character hexadecimal value: $Path"
    }

    $actualSha256 = (Get-FileHash (Resolve-LeafPath -Path $Path -Description 'released package') -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actualSha256 -cne $ExpectedSha256.ToLowerInvariant()) {
        throw "Released package does not match its published SHA-256: $Path"
    }
    return $actualSha256
}

function Get-PublishedRuntimePackageHashes {
    param(
        [Parameter(Mandatory = $true)][string[]] $PackagePaths,
        [Parameter(Mandatory = $true)][string] $ChecksumsPath
    )

    $checksumEntries = @{}
    foreach ($line in Get-Content -LiteralPath (Resolve-LeafPath -Path $ChecksumsPath -Description 'runtime release SHA256SUMS')) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        if ($line -notmatch '^([a-fA-F0-9]{64})  (.+)$') {
            throw "Invalid runtime release SHA256SUMS entry: $line"
        }
        $checksumEntries[$Matches[2]] = $Matches[1].ToLowerInvariant()
    }

    $publishedHashes = @{}
    foreach ($packagePath in $PackagePaths) {
        $packageName = [IO.Path]::GetFileName($packagePath)
        if (-not $checksumEntries.ContainsKey($packageName)) {
            throw "Runtime release SHA256SUMS does not contain $packageName."
        }
        $actualSha256 = (Get-FileHash (Resolve-LeafPath -Path $packagePath -Description 'released runtime package') -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($actualSha256 -cne $checksumEntries[$packageName]) {
            throw "Runtime package does not match its published SHA-256: $packageName"
        }
        $publishedHashes[$packageName] = $actualSha256
    }
    return $publishedHashes
}

function Invoke-CheckedDotNet {
    param([Parameter(Mandatory = $true)][string[]] $Arguments)

    $output = @(& dotnet @Arguments 2>&1)
    if ($LASTEXITCODE -ne 0) { throw "dotnet $($Arguments -join ' ') failed: $($output -join [Environment]::NewLine)" }
    return $output
}

function ConvertFrom-MSBuildProperties {
    param([Parameter(Mandatory = $true)][string[]] $Output)

    $json = ($Output | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join [Environment]::NewLine
    try { $result = $json | ConvertFrom-Json -ErrorAction Stop }
    catch { throw "Could not parse MSBuild property output as JSON: $json" }
    if ($null -eq $result.Properties) { throw 'MSBuild property output did not contain a Properties object.' }
    return $result.Properties
}

function Get-MSBuildProperties {
    param(
        [Parameter(Mandatory = $true)][string] $ProjectPath,
        [Parameter(Mandatory = $true)][string[]] $PropertyNames,
        [string[]] $Properties = @()
    )

    $propertyArguments = @($PropertyNames | ForEach-Object { "-getProperty:$_" })
    $output = @(Invoke-CheckedDotNet -Arguments (@('msbuild', $ProjectPath, '-nologo') + $propertyArguments + $Properties))
    return ConvertFrom-MSBuildProperties -Output $output
}

function Test-FileContainsText {
    param([Parameter(Mandatory = $true)][string] $Path, [Parameter(Mandatory = $true)][string] $Text)

    $bytes = [IO.File]::ReadAllBytes($Path)
    return [Text.Encoding]::UTF8.GetString($bytes).Contains($Text, [StringComparison]::OrdinalIgnoreCase) -or
        [Text.Encoding]::Unicode.GetString($bytes).Contains($Text, [StringComparison]::OrdinalIgnoreCase)
}

function Test-StructuredValueContainsText {
    param(
        $Value,
        [Parameter(Mandatory = $true)][string] $Text,
        [int] $Depth = 0
    )

    if ($null -eq $Value -or $Depth -gt 8) { return $false }
    if ($Value -is [string]) { return $Value.Contains($Text, [StringComparison]::OrdinalIgnoreCase) }
    if ($Value -is [System.Collections.IDictionary]) {
        foreach ($key in $Value.Keys) {
            if ((Test-StructuredValueContainsText -Value $key -Text $Text -Depth ($Depth + 1)) -or
                (Test-StructuredValueContainsText -Value $Value[$key] -Text $Text -Depth ($Depth + 1))) {
                return $true
            }
        }
        return $false
    }
    if ($Value -is [System.Collections.IEnumerable]) {
        foreach ($item in $Value) {
            if (Test-StructuredValueContainsText -Value $item -Text $Text -Depth ($Depth + 1)) { return $true }
        }
        return $false
    }

    foreach ($property in $Value.GetType().GetProperties([Reflection.BindingFlags]'Public,Instance')) {
        if (-not $property.CanRead -or $property.GetIndexParameters().Count -ne 0) { continue }
        try { $propertyValue = $property.GetValue($Value) } catch { continue }
        if ($propertyValue -is [string] -and $propertyValue.Contains($Text, [StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
        if ($property.Name -in @('GlobalProperties', 'Properties', 'Items', 'Key', 'Value') -and
            (Test-StructuredValueContainsText -Value $propertyValue -Text $Text -Depth ($Depth + 1))) {
            return $true
        }
    }
    return $false
}

function Get-MSBuildToolsPath {
    $projectPath = Resolve-LeafPath -Path (Join-Path $PSScriptRoot 'XEngine.ConsumerFixture.csproj') -Description 'Consumer project'
    $properties = Get-MSBuildProperties -ProjectPath $projectPath -PropertyNames @('MSBuildToolsPath', 'MSBuildVersion')
    $toolsPath = [string]$properties.MSBuildToolsPath
    if ([string]::IsNullOrWhiteSpace($toolsPath) -or -not (Test-Path $toolsPath -PathType Container)) {
        throw "Could not resolve the active MSBuild tools path: $toolsPath"
    }
    return (Resolve-Path $toolsPath).Path
}

function Assert-NoBinlogSourceLeaks {
    param(
        [Parameter(Mandatory = $true)][string[]] $Paths,
        [Parameter(Mandatory = $true)][string[]] $ForbiddenRoots,
        [string] $MSBuildToolsPath = (Get-MSBuildToolsPath)
    )

    [Reflection.Assembly]::LoadFrom((Join-Path $MSBuildToolsPath 'Microsoft.Build.Framework.dll')) | Out-Null
    [Reflection.Assembly]::LoadFrom((Join-Path $MSBuildToolsPath 'Microsoft.Build.dll')) | Out-Null

    foreach ($path in $Paths) {
        if (-not (Test-Path $path -PathType Leaf)) { throw "MSBuild binary log was not found: $path" }
        $state = [pscustomobject]@{ Leak = $null }
        $eventSource = [Microsoft.Build.Logging.BinaryLogReplayEventSource]::new()
        $handler = [Microsoft.Build.Framework.AnyEventHandler]{
            param($sender, $eventArgs)
            if ($null -ne $state.Leak) { return }
            foreach ($root in $ForbiddenRoots) {
                foreach ($candidate in @($root, ($root -replace '\\', '/'))) {
                    if (-not [string]::IsNullOrWhiteSpace($candidate) -and
                        (Test-StructuredValueContainsText -Value $eventArgs -Text $candidate)) {
                        $state.Leak = $candidate
                        return
                    }
                }
            }
        }
        $eventSource.add_AnyEventRaised($handler)
        try { $eventSource.Replay((Resolve-Path $path).Path) }
        finally { $eventSource.remove_AnyEventRaised($handler) }
        if ($null -ne $state.Leak) { throw "Clean consumer output contains forbidden local path '$($state.Leak)': $path" }
    }
}

function Assert-BinlogContainsText {
    param(
        [Parameter(Mandatory = $true)][string[]] $Paths,
        [Parameter(Mandatory = $true)][string] $Text,
        [string] $MSBuildToolsPath = (Get-MSBuildToolsPath)
    )

    [Reflection.Assembly]::LoadFrom((Join-Path $MSBuildToolsPath 'Microsoft.Build.Framework.dll')) | Out-Null
    [Reflection.Assembly]::LoadFrom((Join-Path $MSBuildToolsPath 'Microsoft.Build.dll')) | Out-Null

    foreach ($path in $Paths) {
        if (-not (Test-Path $path -PathType Leaf)) { throw "MSBuild binary log was not found: $path" }
        $state = [pscustomobject]@{ Found = $false }
        $eventSource = [Microsoft.Build.Logging.BinaryLogReplayEventSource]::new()
        $handler = [Microsoft.Build.Framework.AnyEventHandler]{
            param($sender, $eventArgs)
            if (-not $state.Found -and (Test-StructuredValueContainsText -Value $eventArgs -Text $Text)) {
                $state.Found = $true
            }
        }
        $eventSource.add_AnyEventRaised($handler)
        try { $eventSource.Replay((Resolve-Path $path).Path) }
        finally { $eventSource.remove_AnyEventRaised($handler) }
        if (-not $state.Found) { throw "MSBuild binary log did not contain required text '$Text': $path" }
    }
}

function Assert-NoSourceLeaks {
    param(
        [Parameter(Mandatory = $true)][string[]] $Paths,
        [Parameter(Mandatory = $true)][string[]] $ForbiddenRoots
    )

    foreach ($path in $Paths) {
        foreach ($root in $ForbiddenRoots) {
            foreach ($candidate in @($root, ($root -replace '\\', '/'))) {
                if (-not [string]::IsNullOrWhiteSpace($candidate) -and (Test-FileContainsText -Path $path -Text $candidate)) {
                    throw "Clean consumer output contains forbidden local path '$candidate': $path"
                }
            }
        }
    }
}

function Assert-RestoredPackageHash {
    param(
        [Parameter(Mandatory = $true)][string] $PackageCache,
        [Parameter(Mandatory = $true)][string] $PackageId,
        [Parameter(Mandatory = $true)][string] $Version,
        [Parameter(Mandatory = $true)][string] $ExpectedSha256
    )

    $packageName = "$($PackageId.ToLowerInvariant()).$Version.nupkg"
    $cachedPackage = Join-Path $PackageCache "$($PackageId.ToLowerInvariant())\$Version\$packageName"
    if (-not (Test-Path $cachedPackage -PathType Leaf)) { throw "Restored package was not found in the isolated cache: $PackageId/$Version" }
    $actualSha256 = (Get-FileHash $cachedPackage -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actualSha256 -cne $ExpectedSha256) { throw "Restored package hash does not match the staged release feed: $PackageId/$Version" }
}

function Restore-EnvironmentValue {
    param([Parameter(Mandatory = $true)][string] $Name, $Value)

    if ($null -eq $Value) { Remove-Item "Env:$Name" -ErrorAction SilentlyContinue }
    else { Set-Item "Env:$Name" ([string]$Value) }
}

if ($MyInvocation.InvocationName -eq '.') { return }

if ([string]::IsNullOrWhiteSpace($RuntimePackageDirectory)) { throw 'RuntimePackageDirectory is required.' }
if ([string]::IsNullOrWhiteSpace($RuntimePackageChecksumsPath)) { throw 'RuntimePackageChecksumsPath is required.' }
if ([string]::IsNullOrWhiteSpace($PublishAotCrossPackagePath)) { throw 'PublishAotCrossPackagePath is required.' }
if ([string]::IsNullOrWhiteSpace($PublishAotCrossPackageSha256)) { throw 'PublishAotCrossPackageSha256 is required.' }
$packageInputs = Resolve-CleanConsumerPackageInputs -RuntimePackageDirectory $RuntimePackageDirectory -PublishAotCrossPackagePath $PublishAotCrossPackagePath
$runtimePackageDirectoryResolved = $packageInputs.RuntimePackageDirectory
$publishAotPackage = $packageInputs.PublishAotCrossPackage
$sdkRootResolved = (Resolve-Path $SdkRoot -ErrorAction Stop).Path
$readElf = Resolve-LeafPath -Path (Join-Path $sdkRootResolved '13\native\llvm\bin\llvm-readelf.exe') -Description 'OpenHarmony llvm-readelf'
$projectPath = Resolve-LeafPath -Path (Join-Path $PSScriptRoot 'XEngine.ConsumerFixture.csproj') -Description 'Consumer project'
$programPath = Resolve-LeafPath -Path (Join-Path $PSScriptRoot 'Program.cs') -Description 'Consumer source'

Assert-CleanConsumerProjectContract -ProjectPath $projectPath

$runtimePackages = @($packageInputs.RuntimePackages)
$sourcePackages = @($packageInputs.SourcePackages)
$publishedRuntimePackageHashes = Get-PublishedRuntimePackageHashes -PackagePaths $runtimePackages -ChecksumsPath $RuntimePackageChecksumsPath
$sourcePackageHashes = @{}
foreach ($package in $runtimePackages) { $sourcePackageHashes[[IO.Path]::GetFileName($package)] = $publishedRuntimePackageHashes[[IO.Path]::GetFileName($package)] }
$sourcePackageHashes[[IO.Path]::GetFileName($publishAotPackage)] = Assert-PublishedPackageHash -Path $publishAotPackage -ExpectedSha256 $PublishAotCrossPackageSha256

$workRoot = Join-Path ([IO.Path]::GetTempPath()) ('openharmony-xengine-consumer-' + [guid]::NewGuid().ToString('N'))
$feedRoot = Join-Path $workRoot 'released-feed'
$consumerRoot = Join-Path $workRoot 'consumer'
$packageCache = Join-Path $workRoot 'packages'
$cliHome = Join-Path $workRoot 'dotnet-home'
$outputRootResolved = [IO.Path]::GetFullPath($OutputRoot)
$succeeded = $false
$oldPackages = $env:NUGET_PACKAGES
$oldCliHome = $env:DOTNET_CLI_HOME
$oldHttpCache = $env:NUGET_HTTP_CACHE_PATH

New-Item -ItemType Directory -Path $feedRoot,$consumerRoot,$packageCache,$cliHome,$outputRootResolved -Force | Out-Null
try {
    foreach ($package in $sourcePackages) { Copy-Item -LiteralPath $package -Destination $feedRoot }
    $feedPackages = @(Get-ChildItem $feedRoot -File -Filter '*.nupkg')
    if ($feedPackages.Count -ne 3) { throw "Released feed must contain exactly three packages, found $($feedPackages.Count)." }
    foreach ($package in $feedPackages) {
        $hash = (Get-FileHash $package.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($sourcePackageHashes[$package.Name] -ne $hash) { throw "Package changed while staging the released feed: $($package.Name)" }
        $package.IsReadOnly = $true
    }

    Copy-Item -LiteralPath $projectPath,$programPath -Destination $consumerRoot
    $nugetConfig = Join-Path $consumerRoot 'NuGet.Config'
    Write-Utf8File -Path $nugetConfig -Content (New-CleanConsumerNuGetConfig -FeedRoot $feedRoot)

    $env:NUGET_PACKAGES = $packageCache
    $env:DOTNET_CLI_HOME = $cliHome
    $env:NUGET_HTTP_CACHE_PATH = Join-Path $workRoot 'http-cache'
    $consumerProject = Join-Path $consumerRoot 'XEngine.ConsumerFixture.csproj'
    $workspaceRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
    $forbiddenRoots = @(Get-CleanConsumerForbiddenRoots -WorkspaceRoot $workspaceRoot -RuntimePackageDirectory $runtimePackageDirectoryResolved)
    $records = @()

    foreach ($case in Get-CleanConsumerCases) {
        $caseName = "api$($case.Api)-$($case.Abi)"
        $caseRoot = Join-Path $workRoot $caseName
        $objRoot = Join-Path $caseRoot 'obj'
        $binRoot = Join-Path $caseRoot 'bin'
        $publishRoot = Join-Path $caseRoot 'publish'
        $restoreBinlog = Join-Path $caseRoot 'restore.binlog'
        $publishBinlog = Join-Path $caseRoot 'publish.binlog'
        New-Item -ItemType Directory -Path $objRoot,$binRoot,$publishRoot -Force | Out-Null
        $properties = @(
            "-p:OpenHarmonyApiLevel=$($case.Api)",
            "-p:OpenHarmonyAbi=$($case.Abi)",
            "-p:RuntimeIdentifier=$($case.Rid)",
            "-p:OpenHarmonySdkRoot=$sdkRootResolved",
            "-p:BaseIntermediateOutputPath=$objRoot\",
            "-p:BaseOutputPath=$binRoot\",
            "-p:PublishDir=$publishRoot\",
            '-p:NuGetAudit=false'
        )
        Invoke-CheckedDotNet -Arguments (@('restore', $consumerProject, '--configfile', $nugetConfig, '--nologo', "-bl:$restoreBinlog") + $properties) | Out-Null
        Invoke-CheckedDotNet -Arguments (@('publish', $consumerProject, '-c', 'Release', '--no-restore', '--nologo', "-bl:$publishBinlog") + $properties) | Out-Null
        $resolvedTargetTriple = [string](Get-MSBuildProperties -ProjectPath $consumerProject -PropertyNames @('OpenHarmonyTargetTriple', 'MSBuildVersion') -Properties $properties).OpenHarmonyTargetTriple
        if ($resolvedTargetTriple -cne $case.TargetTriple) {
            throw "Case $caseName resolved '$resolvedTargetTriple' instead of expected OpenHarmony target triple '$($case.TargetTriple)'."
        }
        Assert-BinlogContainsText -Paths @($publishBinlog) -Text "--target=$resolvedTargetTriple"

        $assetsPath = Join-Path $objRoot 'project.assets.json'
        $generatedFiles = @($assetsPath) +
            @(Get-ChildItem $objRoot -Recurse -File | Where-Object { $_.Extension -in '.props','.targets' } | Select-Object -ExpandProperty FullName)
        foreach ($generatedFile in $generatedFiles) {
            if (-not (Test-Path $generatedFile -PathType Leaf)) { throw "Expected generated consumer evidence was not found: $generatedFile" }
        }
        Assert-NoSourceLeaks -Paths $generatedFiles -ForbiddenRoots $forbiddenRoots
        Assert-NoBinlogSourceLeaks -Paths @($restoreBinlog, $publishBinlog) -ForbiddenRoots $forbiddenRoots

        $assets = Get-Content -LiteralPath $assetsPath -Raw | ConvertFrom-Json
        $customLibraries = @($assets.libraries.psobject.Properties.Name | Where-Object { $_ -like 'OpenHarmony.NET.*' } | Sort-Object)
        $expectedRuntimeId = if ($case.Abi -eq 'x86_64') { "OpenHarmony.NET.Runtime.NativeAot.x86_64/$script:RuntimeVersion" } else { "OpenHarmony.NET.Runtime.NativeAot.arm64-v8a/$script:RuntimeVersion" }
        if ($customLibraries -notcontains $expectedRuntimeId -or $customLibraries -notcontains "OpenHarmony.NET.PublishAotCross/$script:PublishAotCrossVersion") {
            throw "Case $caseName did not restore the expected released package IDs."
        }
        if (@($customLibraries | Where-Object { $_ -like 'OpenHarmony.NET.Runtime.NativeAot.*' }).Count -ne 1) {
            throw "Case $caseName restored more than one ABI runtime package."
        }
        $expectedRuntimePackage = if ($case.Abi -eq 'x86_64') { $runtimePackages[0] } else { $runtimePackages[1] }
        Assert-RestoredPackageHash -PackageCache $packageCache -PackageId ($expectedRuntimeId -split '/')[0] -Version $script:RuntimeVersion -ExpectedSha256 $sourcePackageHashes[[IO.Path]::GetFileName($expectedRuntimePackage)]
        Assert-RestoredPackageHash -PackageCache $packageCache -PackageId 'OpenHarmony.NET.PublishAotCross' -Version $script:PublishAotCrossVersion -ExpectedSha256 $sourcePackageHashes[[IO.Path]::GetFileName($publishAotPackage)]

        $elf = $null
        $header = $null
        foreach ($candidate in @(Get-ChildItem $publishRoot -File | Sort-Object Length -Descending)) {
            $candidateHeader = @(& $readElf -h $candidate.FullName 2>&1)
            if ($LASTEXITCODE -eq 0 -and ($candidateHeader -join "`n") -match 'ELF Header') {
                $elf = $candidate
                $header = $candidateHeader -join "`n"
                break
            }
        }
        if ($null -eq $elf) { throw "Case $caseName did not produce an ELF file." }
        if ($header -notmatch ('Machine:\s+' + [regex]::Escape($case.ElfMachine))) {
            throw "Case $caseName emitted the wrong ELF machine: $header"
        }

        $records += [ordered]@{
            status = 'PASS'
            buildApi = $case.Api
            abi = $case.Abi
            rid = $case.Rid
            targetTriple = $resolvedTargetTriple
            elfMachine = $case.ElfMachine
            elfSha256 = (Get-FileHash $elf.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
            restoredPackages = $customLibraries
            sourceLeak = $false
        }
    }

    $evidence = [ordered]@{
        schemaVersion = 1
        status = 'PASS'
        runtimeVersion = $script:RuntimeVersion
        publishAotCrossVersion = $script:PublishAotCrossVersion
        packages = @($feedPackages | Sort-Object Name | ForEach-Object { [ordered]@{ name = $_.Name; sha256 = $sourcePackageHashes[$_.Name] } })
        cases = $records
    }
    Write-CleanConsumerEvidence -Path (Join-Path $outputRootResolved 'clean-consumer-evidence.json') -Evidence $evidence
    $succeeded = $true
    Write-Output "XEngine clean consumer complete: $($records.Count) NativeAOT publishes passed."
}
finally {
    Restore-EnvironmentValue -Name 'NUGET_PACKAGES' -Value $oldPackages
    Restore-EnvironmentValue -Name 'DOTNET_CLI_HOME' -Value $oldCliHome
    Restore-EnvironmentValue -Name 'NUGET_HTTP_CACHE_PATH' -Value $oldHttpCache
    if ($succeeded -and -not $KeepWorkDirectory) {
        $resolvedWorkRoot = [IO.Path]::GetFullPath($workRoot)
        $resolvedTempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
        if ($resolvedWorkRoot.StartsWith($resolvedTempRoot, [StringComparison]::OrdinalIgnoreCase)) {
            Get-ChildItem $feedRoot -File -ErrorAction SilentlyContinue | ForEach-Object { $_.IsReadOnly = $false }
            Remove-Item -LiteralPath $resolvedWorkRoot -Recurse -Force
        }
    }
    elseif (-not $succeeded) {
        Write-Warning "Clean consumer work directory retained after failure: $workRoot"
    }
}
