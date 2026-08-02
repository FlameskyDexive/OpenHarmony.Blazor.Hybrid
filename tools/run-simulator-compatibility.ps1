[CmdletBinding()]
param(
    [int[]] $Apis = @(13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 26),
    [ValidateSet('x86_64')][string] $Abi = 'x86_64',
    [string] $HdcPath = (Join-Path $env:ProgramFiles 'Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe'),
    [string] $EmulatorPath = (Join-Path $env:ProgramFiles 'Huawei\DevEco Studio\tools\emulator\Emulator.exe'),
    [string] $EmulatorRoot = (Join-Path $env:LOCALAPPDATA 'Huawei\Emulator\deployed'),
    [string] $ImageRoot = ((Join-Path $env:LOCALAPPDATA 'Huawei\Sdk') -replace '\\', '/'),
    [string] $OutputRoot = (Join-Path $PSScriptRoot '..\artifacts\simulator-evidence'),
    [string] $PrivateOutputRoot = (Join-Path $PSScriptRoot '..\artifacts\simulator-private'),
    [string] $EvidenceRunId = ('simulator-' + (Get-Date -Format 'yyyyMMddTHHmmssZ')),
    [int] $BootTimeoutSeconds = 240,
    [switch] $Resume,
    [switch] $KeepEmulators
)

$ErrorActionPreference = 'Stop'

function ConvertTo-ApiNumber {
    param([Parameter(Mandatory = $true)] $Value)

    $match = [regex]::Match([string]$Value, '^\d+')
    if (-not $match.Success) { throw "Unable to normalize API value '$Value'." }
    return [int]$match.Value
}

function Read-ApiMatrix {
    $path = Join-Path $PSScriptRoot 'openharmony-api-matrix.json'
    return Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
}

function Get-CompatibilityPairs {
    param([int[]] $Apis = @(13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 26))

    $matrix = Read-ApiMatrix
    $deviceApis = @($Apis | ForEach-Object { ConvertTo-ApiNumber $_ } | Sort-Object -Unique)
    if ($deviceApis -contains 25) { throw 'API25 is not a supported simulator target.' }
    foreach ($deviceApi in $deviceApis) {
        if (@($matrix.supportedApis | ForEach-Object { [int]$_ }) -notcontains $deviceApi) {
            throw "Device API$deviceApi is not in the checked-in compatibility matrix."
        }
        foreach ($buildApi in @($matrix.supportedApis | ForEach-Object { [int]$_ } | Sort-Object)) {
            if ($buildApi -le $deviceApi -and $buildApi -ne 25) {
                [pscustomobject]@{
                    BuildApi = $buildApi
                    DeviceApi = $deviceApi
                    Abi = 'x86_64'
                }
            }
        }
    }
}

function Resolve-ToolPath {
    param([Parameter(Mandatory = $true)][string] $Path)

    if (Test-Path -LiteralPath $Path -PathType Leaf) { return (Resolve-Path -LiteralPath $Path).Path }
    return (Get-Command -Name $Path -ErrorAction Stop).Source
}

function Invoke-Hdc {
    param(
        [Parameter(Mandatory = $true)][string] $Hdc,
        [Parameter(Mandatory = $true)][string] $Target,
        [Parameter(Mandatory = $true)][string[]] $Arguments
    )

    $output = @(& $Hdc -t $Target @Arguments 2>&1)
    if ($LASTEXITCODE -ne 0) { throw "HDC failed for ${Target}: $($Arguments -join ' '): $($output -join ' ')" }
    [pscustomobject]@{ Output = $output; Text = ($output -join "`n") }
}

function Get-TargetInventory {
    param([Parameter(Mandatory = $true)][string] $Hdc)

    $lines = @(& $Hdc list targets -v 2>&1)
    if ($LASTEXITCODE -ne 0) { throw "Unable to list HDC targets: $($lines -join ' ')" }
    $inventory = @()
    foreach ($line in $lines) {
        $parts = ($line.ToString().Trim() -split '\s+')
        if ($parts.Count -lt 4 -or $parts[0] -notmatch ':') { continue }
        $target = $parts[0]
        $transport = $parts[1]
        $state = $parts[2]
        if ($transport -eq 'USB') { continue }
        if ($state -ne 'Connected') { continue }
        if ($transport -ne 'TCP') { throw "Unexpected non-TCP connected target: $target" }
        try {
            $apiText = (Invoke-Hdc -Hdc $Hdc -Target $target -Arguments @('shell', 'param', 'get', 'const.ohos.apiversion')).Text.Trim()
            if ([string]::IsNullOrWhiteSpace($apiText)) { continue }
            $api = ConvertTo-ApiNumber $apiText
            $arch = (Invoke-Hdc -Hdc $Hdc -Target $target -Arguments @('shell', 'uname', '-m')).Text.Trim()
        }
        catch { continue }
        if ($arch -ne 'x86_64') { throw "Simulator target $target reported unsupported ABI '$arch'." }
        $inventory += [pscustomobject]@{ Target = $target; Api = $api; Abi = $arch }
    }
    $duplicates = @($inventory | Group-Object Api | Where-Object Count -gt 1)
    if ($duplicates.Count -gt 0) { throw "Duplicate connected simulator API targets: $($duplicates.Name -join ', ')" }
    return $inventory
}

function Get-EmulatorDefinitions {
    param([Parameter(Mandatory = $true)][string] $Root)

    $listPath = Join-Path $Root 'lists.json'
    if (-not (Test-Path $listPath -PathType Leaf)) { throw "Emulator deployment list was not found: $listPath" }
    $definitions = Get-Content $listPath -Raw | ConvertFrom-Json
    foreach ($definition in $definitions) {
        $api = ConvertTo-ApiNumber $definition.apiVersion
        if ($definition.abi -eq 'x86' -and $definition.imageDir -match '_x86') {
            [pscustomobject]@{
                Name = $definition.name
                Api = $api
                Abi = 'x86_64'
                Uuid = $definition.uuid
                ConfigPath = $definition.'harmonyos.config.path'
            }
        }
    }
}

function New-EmulatorInstanceIdentity {
    param(
        [Parameter(Mandatory = $true)] $Definition,
        [Parameter(Mandatory = $true)][string] $Emulator
    )

    if ([string]::IsNullOrWhiteSpace([string]$Definition.Uuid)) {
        throw "Emulator '$($Definition.Name)' does not declare an instance UUID."
    }
    if ([string]::IsNullOrWhiteSpace([string]$Definition.ConfigPath)) {
        throw "Emulator '$($Definition.Name)' does not declare a DevEco configuration path."
    }

    $studioRoot = Split-Path (Split-Path (Split-Path $Emulator -Parent) -Parent) -Parent
    $java = Join-Path $studioRoot 'jbr\bin\java.exe'
    $javac = Join-Path $studioRoot 'jbr\bin\javac.exe'
    $hwlib = Join-Path $studioRoot 'lib\hwlib.jar'
    $deviceManager = @(Get-ChildItem (Join-Path $studioRoot 'plugins\harmony\lib') -Filter 'device-mgmt-*.jar' -File | Select-Object -First 1)
    $helper = Join-Path $PSScriptRoot 'EmulatorInstanceIdentity.java'
    foreach ($required in @($java, $javac, $hwlib, $helper)) {
        if (-not (Test-Path $required -PathType Leaf)) { throw "Emulator identity dependency was not found: $required" }
    }
    if ($deviceManager.Count -ne 1) { throw "DevEco device-mgmt plugin was not found under $studioRoot." }

    $materialRoot = Join-Path ([string]$Definition.ConfigPath) 'emulator\data2'
    if (-not (Test-Path $materialRoot -PathType Container)) {
        throw "DevEco emulator security material was not found: $materialRoot"
    }
    $classpath = (Join-Path $studioRoot 'lib\*') + [IO.Path]::PathSeparator + $deviceManager[0].FullName
    $compileRoot = Join-Path ([IO.Path]::GetTempPath()) ('openharmony-emulator-identity-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $compileRoot -Force | Out-Null
    try {
        $compileOutput = @(& $javac -proc:none -cp $classpath -d $compileRoot $helper 2>&1)
        if ($LASTEXITCODE -ne 0) { throw "Unable to compile emulator identity helper: $($compileOutput -join ' ')" }
        $runtimeClasspath = $compileRoot + [IO.Path]::PathSeparator + $classpath
        $output = @(& $java -cp $runtimeClasspath EmulatorInstanceIdentity $materialRoot ([string]$Definition.Uuid) 2>&1)
        if ($LASTEXITCODE -ne 0) { throw "Unable to create emulator instance identity: $($output -join ' ')" }
    }
    finally {
        $resolvedCompileRoot = [IO.Path]::GetFullPath($compileRoot)
        $resolvedTempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
        if ($resolvedCompileRoot.StartsWith($resolvedTempRoot, [StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $resolvedCompileRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    $identityPath = Join-Path ([IO.Path]::GetTempPath()) ([string]$Definition.Uuid)
    if (-not (Test-Path $identityPath -PathType Leaf) -or (Get-Item $identityPath).Length -lt 32) {
        throw "Emulator instance identity was not created correctly: $identityPath"
    }
    return $identityPath
}

function Start-ApiEmulator {
    param(
        [Parameter(Mandatory = $true)][int] $Api,
        [Parameter(Mandatory = $true)][string] $Emulator,
        [Parameter(Mandatory = $true)][string] $Root,
        [Parameter(Mandatory = $true)][string] $Image,
        [Parameter(Mandatory = $true)][int] $TimeoutSeconds
    )

    $definition = @(Get-EmulatorDefinitions -Root $Root | Where-Object Api -eq $Api | Select-Object -First 1)
    if ($definition.Count -ne 1) { throw "No x86_64 emulator definition exists for API$Api." }
    $identityPath = New-EmulatorInstanceIdentity -Definition $definition[0] -Emulator $Emulator
    $process = $null
    try {
        $trace = "trace_codex_$([guid]::NewGuid().ToString('N'))_commandPipe"
        $hvdName = '"' + $definition[0].Name.Replace('"', '\"') + '"'
        $process = Start-Process -FilePath $Emulator -ArgumentList @('-hvd', $hvdName, '-path', $Root, '-t', $trace, '-imageRoot', $Image) -WindowStyle Hidden -PassThru
        $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
        do {
            Start-Sleep -Seconds 5
            try {
                $inventory = Get-TargetInventory -Hdc $script:Hdc
                $target = @($inventory | Where-Object Api -eq $Api | Select-Object -First 1)
                if ($target.Count -eq 1) {
                    return [pscustomobject]@{
                        Target = $target[0].Target
                        ProcessId = $process.Id
                        Definition = $definition[0].Name
                        IdentityPath = $identityPath
                    }
                }
            }
            catch { }
        } while ([DateTime]::UtcNow -lt $deadline)
        throw "API$Api emulator did not become a connected x86_64 HDC target."
    }
    catch {
        if ($process) { Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue }
        Remove-Item -LiteralPath $identityPath -Force -ErrorAction SilentlyContinue
        throw
    }
}

function Write-Json {
    param([Parameter(Mandatory = $true)][string] $Path, [Parameter(Mandatory = $true)] $Value)

    New-Item -ItemType Directory -Path (Split-Path $Path) -Force | Out-Null
    [IO.File]::WriteAllText($Path, (($Value | ConvertTo-Json -Depth 15) + "`n"), [Text.UTF8Encoding]::new($false))
}

function Get-Layout {
    param(
        [Parameter(Mandatory = $true)][string] $Target,
        [Parameter(Mandatory = $true)][string] $Label,
        [Parameter(Mandatory = $true)][string] $PrivateRoot
    )

    $remote = "/data/local/tmp/codex-layout-$([guid]::NewGuid().ToString('N')).json"
    Invoke-Hdc -Hdc $script:Hdc -Target $Target -Arguments @('shell', 'uitest', 'dumpLayout', '-p', $remote) | Out-Null
    $local = Join-Path $PrivateRoot "$Label-layout.json"
    New-Item -ItemType Directory -Path $PrivateRoot -Force | Out-Null
    $received = @(& $script:Hdc -t $Target file recv $remote $local 2>&1)
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path $local -PathType Leaf)) { throw "Unable to retrieve UI layout for ${Target}: $($received -join ' ')" }
    return Get-Content $local -Raw | ConvertFrom-Json
}

function Get-LayoutNodes {
    param([Parameter(Mandatory = $true)] $Node)

    if ($Node.attributes) { $Node }
    foreach ($child in @($Node.children)) { Get-LayoutNodes -Node $child }
}

function Get-NodeCenter {
    param([Parameter(Mandatory = $true)][string] $Bounds)

    $match = [regex]::Match($Bounds, '^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$')
    if (-not $match.Success) { throw "Invalid UI bounds '$Bounds'." }
    $x1 = [int]$match.Groups[1].Value
    $y1 = [int]$match.Groups[2].Value
    $x2 = [int]$match.Groups[3].Value
    $y2 = [int]$match.Groups[4].Value
    return @(
        [int](($x1 + $x2) / 2),
        [int](($y1 + $y2) / 2)
    )
}

function Invoke-UiCompatibilityCheck {
    param(
        [Parameter(Mandatory = $true)][string] $Target,
        [Parameter(Mandatory = $true)][string] $PrivateRoot,
        [Parameter(Mandatory = $true)][string] $Label
    )

    $homeNodes = @()
    $homeDeadline = [DateTime]::UtcNow.AddSeconds(20)
    do {
        $homeLayout = Get-Layout -Target $Target -Label "$Label-home" -PrivateRoot $PrivateRoot
        $homeNodes = @(Get-LayoutNodes -Node $homeLayout)
        if (@($homeNodes | Where-Object { $_.attributes.text -eq 'Hello, world!' }).Count -gt 0) { break }
        Start-Sleep -Seconds 1
    } while ([DateTime]::UtcNow -lt $homeDeadline)
    if (@($homeNodes | Where-Object { $_.attributes.text -eq 'Hello, world!' }).Count -eq 0) {
        throw "Home UI did not contain 'Hello, world!' on $Target."
    }
    $counter = @($homeNodes | Where-Object { $_.attributes.text -eq 'Counter' -and $_.attributes.clickable -eq 'true' } | Select-Object -First 1)
    if ($counter.Count -eq 0) {
        $menu = @($homeNodes | Where-Object { $_.attributes.text -eq 'Navigation menu' -and $_.attributes.clickable -eq 'true' } | Select-Object -First 1)
        if ($menu.Count -ne 1) { throw "Navigation menu was not found on $Target." }
        $center = Get-NodeCenter $menu[0].attributes.bounds
        Invoke-Hdc -Hdc $script:Hdc -Target $Target -Arguments @('shell', 'uitest', 'uiInput', 'click', $center[0], $center[1]) | Out-Null
        Start-Sleep -Milliseconds 500
        $homeLayout = Get-Layout -Target $Target -Label "$Label-menu" -PrivateRoot $PrivateRoot
        $homeNodes = @(Get-LayoutNodes -Node $homeLayout)
        $counter = @($homeNodes | Where-Object { $_.attributes.text -eq 'Counter' -and $_.attributes.clickable -eq 'true' } | Select-Object -First 1)
    }
    if ($counter.Count -ne 1) { throw "Counter navigation link was not found on $Target." }
    $center = Get-NodeCenter $counter[0].attributes.bounds
    Invoke-Hdc -Hdc $script:Hdc -Target $Target -Arguments @('shell', 'uitest', 'uiInput', 'click', $center[0], $center[1]) | Out-Null
    $counterNodes = @()
    $counterDeadline = [DateTime]::UtcNow.AddSeconds(10)
    do {
        $counterPage = Get-Layout -Target $Target -Label "$Label-counter0" -PrivateRoot $PrivateRoot
        $counterNodes = @(Get-LayoutNodes -Node $counterPage)
        if (@($counterNodes | Where-Object { $_.attributes.text -eq 'Current count: 0' }).Count -gt 0) { break }
        Start-Sleep -Milliseconds 500
    } while ([DateTime]::UtcNow -lt $counterDeadline)
    if (@($counterNodes | Where-Object { $_.attributes.text -eq 'Counter' }).Count -eq 0 -or
        @($counterNodes | Where-Object { $_.attributes.text -eq 'Current count: 0' }).Count -eq 0) {
        throw "Counter page did not show count 0 on $Target."
    }
    $button = @($counterNodes | Where-Object { $_.attributes.text -eq 'Click me' -and $_.attributes.clickable -eq 'true' } | Select-Object -First 1)
    if ($button.Count -ne 1) { throw "Counter button was not found on $Target." }
    $center = Get-NodeCenter $button[0].attributes.bounds
    Invoke-Hdc -Hdc $script:Hdc -Target $Target -Arguments @('shell', 'uitest', 'uiInput', 'click', $center[0], $center[1]) | Out-Null
    $incrementDeadline = [DateTime]::UtcNow.AddSeconds(10)
    do {
        $counterPage = Get-Layout -Target $Target -Label "$Label-counter1" -PrivateRoot $PrivateRoot
        $counterNodes = @(Get-LayoutNodes -Node $counterPage)
        if (@($counterNodes | Where-Object { $_.attributes.text -eq 'Current count: 1' }).Count -gt 0) { break }
        Start-Sleep -Milliseconds 500
    } while ([DateTime]::UtcNow -lt $incrementDeadline)
    if (@($counterNodes | Where-Object { $_.attributes.text -eq 'Current count: 1' }).Count -eq 0) {
        throw "Counter page did not increment to 1 on $Target."
    }
    return [ordered]@{ status = 'PASS'; homeText = 'Hello, world!'; counterInitial = 0; counterAfterClick = 1 }
}

if ($MyInvocation.InvocationName -eq '.') { return }

$script:Hdc = Resolve-ToolPath -Path $HdcPath
$resolvedEmulator = Resolve-ToolPath -Path $EmulatorPath
$matrix = Read-ApiMatrix
$pairs = @(Get-CompatibilityPairs -Apis $Apis)
$publicRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$outputRootResolved = if ([IO.Path]::IsPathRooted($OutputRoot)) { $OutputRoot } else { Join-Path $publicRoot $OutputRoot }
$privateRootResolved = if ([IO.Path]::IsPathRooted($PrivateOutputRoot)) { $PrivateOutputRoot } else { Join-Path $publicRoot $PrivateOutputRoot }
New-Item -ItemType Directory -Path $outputRootResolved,$privateRootResolved -Force | Out-Null

$acceptanceScript = Join-Path $PSScriptRoot 'run-device-acceptance.ps1'
$java = Resolve-ToolPath -Path 'java'
$signTool = Join-Path (Split-Path (Split-Path $resolvedEmulator -Parent) -Parent) 'sdk\default\openharmony\toolchains\lib\hap-sign-tool.jar'
if (-not (Test-Path $signTool -PathType Leaf)) {
    $signTool = Join-Path $env:ProgramFiles 'Huawei\DevEco Studio\sdk\default\openharmony\toolchains\lib\hap-sign-tool.jar'
}
if (-not (Test-Path $signTool -PathType Leaf)) { throw "HAP signing tool was not found: $signTool" }

$summary = [ordered]@{
    schemaVersion = 1
    result = 'PASS'
    evidenceRunId = $EvidenceRunId
    abi = $Abi
    supportedApis = @($matrix.supportedApis | ForEach-Object { [int]$_ })
    api25 = 'absent'
    records = @()
}

foreach ($deviceApi in @($Apis | ForEach-Object { ConvertTo-ApiNumber $_ } | Sort-Object -Unique)) {
    $devicePairs = @($pairs | Where-Object DeviceApi -eq $deviceApi)
    if ($Resume) {
        $existingRecords = @()
        foreach ($pair in $devicePairs) {
            $existingPath = Join-Path $outputRootResolved "api$($pair.BuildApi)-on-api$deviceApi-$Abi\compatibility-evidence.json"
            if (Test-Path $existingPath -PathType Leaf) { $existingRecords += Get-Content $existingPath -Raw | ConvertFrom-Json }
        }
        if ($existingRecords.Count -eq $devicePairs.Count -and
            @($existingRecords | Where-Object { $_.status -notin @('PASS', 'SKIPPED') }).Count -eq 0) {
            $summary.records += $existingRecords
            continue
        }
    }
    $inventory = @(Get-TargetInventory -Hdc $script:Hdc)
    $started = $null
    $target = @($inventory | Where-Object Api -eq $deviceApi | Select-Object -First 1)
    if ($target.Count -eq 0) {
        $started = Start-ApiEmulator -Api $deviceApi -Emulator $resolvedEmulator -Root $EmulatorRoot -Image $ImageRoot -TimeoutSeconds $BootTimeoutSeconds
        $targetName = $started.Target
    }
    else { $targetName = $target[0].Target }
    try {
        foreach ($pair in $devicePairs) {
            $metadataPath = Join-Path $publicRoot "artifacts\hap-matrix\api$($pair.BuildApi)\$Abi\build-metadata.json"
            $metadata = if (Test-Path $metadataPath -PathType Leaf) { Get-Content $metadataPath -Raw | ConvertFrom-Json } else { $null }
            $pairRoot = Join-Path $outputRootResolved "api$($pair.BuildApi)-on-api$deviceApi-$Abi"
            $pairPrivate = Join-Path $privateRootResolved "api$($pair.BuildApi)-on-api$deviceApi-$Abi"
            if ($null -eq $metadata -or $metadata.status -ne 'PASS') {
                $record = [ordered]@{ status = 'SKIPPED'; buildApi = $pair.BuildApi; runtimeBaselineApi = 13; deviceApi = $deviceApi; abi = $Abi; reason = 'No independent installable Native SDK/HAP exists for this build API; emulator compatibility was not fabricated.' }
                Write-Json (Join-Path $pairRoot 'compatibility-evidence.json') $record
                $summary.records += $record
                continue
            }
            $hap = Join-Path $publicRoot "artifacts\hap-matrix\api$($pair.BuildApi)\$Abi\entry-default-signed.hap"
            if (-not (Test-Path $hap -PathType Leaf)) { throw "HAP artifact was not found: $hap" }
            $sampleCommit = [string]$metadata.commits.sample
            $runSmoke = "matrix-api$($pair.BuildApi)-$Abi"
            & $acceptanceScript -Abi $Abi -HapPath $hap -ApiLevel $pair.BuildApi -DeviceApiLevel $deviceApi `
                -ExpectedRuntimeBaselineApi 13 -Target $targetName -HdcPath $script:Hdc -JavaPath $java `
                -HapSignToolPath $signTool -SampleCommit $sampleCommit -EvidenceRunId "$EvidenceRunId-api$($pair.BuildApi)-on-api$deviceApi" `
                -ExpectedSmokeRunId $runSmoke -EvidenceRoot $pairRoot -PrivateEvidenceRoot $pairPrivate | Out-Null
            $ui = Invoke-UiCompatibilityCheck -Target $targetName -PrivateRoot $pairPrivate -Label "api$($pair.BuildApi)-on-api$deviceApi"
            $acceptanceEvidence = Get-Content (Join-Path $pairRoot "api$($pair.BuildApi)-$Abi-evidence.json") -Raw | ConvertFrom-Json
            $record = [ordered]@{
                status = 'PASS'; buildApi = $pair.BuildApi; runtimeBaselineApi = 13; deviceApi = $deviceApi; abi = $Abi
                hapSha256 = $metadata.hapSha256; sampleCommit = $sampleCommit; runtimeCommit = $metadata.commits.runtime
                bindingsCommit = $metadata.commits.bindings; publishAotCrossCommit = $metadata.commits.publishAotCross
                runtimeManifestEntry = $metadata.runtimeManifestEntry; acceptanceEvidenceSha256 = (Get-FileHash (Join-Path $pairRoot "api$($pair.BuildApi)-$Abi-evidence.json") -Algorithm SHA256).Hash.ToLowerInvariant()
                ui = $ui
            }
            Write-Json (Join-Path $pairRoot 'compatibility-evidence.json') $record
            $summary.records += $record
        }
    }
    finally {
        if ($started -and -not $KeepEmulators) {
            Stop-Process -Id $started.ProcessId -Force -ErrorAction SilentlyContinue
            $offlineDeadline = [DateTime]::UtcNow.AddSeconds(30)
            do {
                Start-Sleep -Seconds 1
                $stillConnected = @(Get-TargetInventory -Hdc $script:Hdc | Where-Object { $_.Target -eq $targetName })
            } while ($stillConnected.Count -gt 0 -and [DateTime]::UtcNow -lt $offlineDeadline)
            Remove-Item -LiteralPath $started.IdentityPath -Force -ErrorAction SilentlyContinue
        }
    }
}

$summary.passCount = @($summary.records | Where-Object { $_.status -eq 'PASS' }).Count
$summary.skippedCount = @($summary.records | Where-Object { $_.status -eq 'SKIPPED' }).Count
$summary.totalCount = @($summary.records).Count
if ($summary.totalCount -ne $pairs.Count) { throw "Expected $($pairs.Count) logical compatibility records, got $($summary.totalCount)." }
Write-Json (Join-Path $outputRootResolved 'compatibility-summary.json') $summary
Write-Output "Simulator compatibility complete: $($summary.passCount) PASS, $($summary.skippedCount) SKIPPED, $($summary.totalCount) logical records."
