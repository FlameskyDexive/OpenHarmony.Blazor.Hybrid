Describe 'run-device-acceptance target selection' {
    It 'selects the requested target when multiple HDC targets are connected' {
        $fakeHdc = Join-Path $TestDrive 'fake-hdc.ps1'
        @'
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]] $Arguments
)

if ($Arguments -contains 'list') {
    '127.0.0.1:5555'
    '127.0.0.1:5557'
    exit 0
}

$targetIndex = [Array]::IndexOf($Arguments, '-t')
if ($targetIndex -lt 0 -or $Arguments[$targetIndex + 1] -ne '127.0.0.1:5557') {
    throw 'The requested API26 target was not selected.'
}

if ($Arguments -contains 'uname') {
    'x86_64'
    exit 0
}
if ($Arguments -contains 'param') {
    '26'
    exit 0
}
if ($Arguments -contains '-x') {
    'Dotnet10Smoke status=PASS runtime=10.0 api=26 abi=x86_64 runtimeSource=76bde136efafd0e193234e38d169752b93e3bce6 runtimePackage=ee65d55 bindings=2b68d3c publishAot=94e69fb startup=True gc=True thread=True file=True network=True icu=True hilog=True ipc=True callback=True'
}
exit 0
'@ | Set-Content -LiteralPath $fakeHdc -Encoding UTF8

        $hap = Join-Path $TestDrive 'entry-signed.hap'
        Set-Content -LiteralPath $hap -Value 'signed-hap' -Encoding ASCII
        $evidence = Join-Path $TestDrive 'evidence'
        $script = Join-Path $PSScriptRoot 'run-device-acceptance.ps1'

        & $script -Abi x86_64 -HapPath $hap -HdcPath $fakeHdc -Target '127.0.0.1:5557' -ApiLevel 26 -EvidenceRoot $evidence | Out-Null

        if ($LASTEXITCODE -ne 0) { throw "Acceptance script exited with code $LASTEXITCODE." }
        if (-not (Test-Path (Join-Path $evidence 'api26-x86_64-evidence.json'))) {
            throw 'Acceptance evidence was not written.'
        }
    }

    It 'uses the loaded libentry path to resolve the NativeAOT library' {
        $source = Get-Content -Raw (Join-Path $PSScriptRoot '..\OHOS_Project\entry\src\main\cpp\napi_init.cpp')

        foreach ($pattern in @(
            'dladdr',
            'dladdr\(\(void\*\)\&LoadEntryLibrary',
            'dlopen\(path, RTLD_NOW\)')) {
            if (-not [regex]::IsMatch($source, $pattern)) { throw "Native loader is missing '$pattern'." }
        }
        foreach ($pattern in @('RTLD_GLOBAL', 'assert\(handle', 'OH_LOG_ERROR\(LOG_APP, "BlazorHybrid"')) {
            if ([regex]::IsMatch($source, $pattern)) { throw "Native loader still contains '$pattern'." }
        }

        $project = Get-Content -Raw (Join-Path $PSScriptRoot '..\Src\Entry\Entry.csproj')
        foreach ($pattern in @(
            '76bde136efafd0e193234e38d169752b93e3bce6',
            'ee65d55')) {
            if (-not [regex]::IsMatch($project, $pattern)) { throw "Entry.csproj is missing '$pattern'." }
        }
        if ([regex]::IsMatch($project, 'PatchOpenHarmonyNativeExports')) {
            throw 'Entry.csproj still patches NativeAOT exports.'
        }
        if (Test-Path (Join-Path $PSScriptRoot '..\Src\Entry\Entry.exports')) {
            throw 'The obsolete NativeAOT TLS exports file still exists.'
        }
    }
}
