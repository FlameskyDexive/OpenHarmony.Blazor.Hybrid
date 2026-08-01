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
if ($Arguments -contains '-d') {
    'Dotnet10Smoke status=PASS runtime=10.0 api=26 abi=x86_64 runtimeSource=a9c01b20cc8aa9ca03955c9f55626bfd517619c9 runtimePackage=e13ef07 bindings=2b68d3c publishAot=94e69fb startup=True gc=True thread=True file=True network=True icu=True hilog=True ipc=True callback=True'
}
exit 0
'@ | Set-Content -LiteralPath $fakeHdc -Encoding UTF8

        $hap = Join-Path $TestDrive 'entry-signed.hap'
        Set-Content -LiteralPath $hap -Value 'signed-hap' -Encoding ASCII
        $evidence = Join-Path $TestDrive 'evidence'
        $script = Join-Path $PSScriptRoot 'run-device-acceptance.ps1'

        & $script -Abi x86_64 -HapPath $hap -HdcPath $fakeHdc -Target '127.0.0.1:5557' -ApiLevel 26 -EvidenceRoot $evidence | Out-Null

        $LASTEXITCODE | Should -Be 0
        Test-Path (Join-Path $evidence 'api26-x86_64-evidence.json') | Should -BeTrue
    }
}
