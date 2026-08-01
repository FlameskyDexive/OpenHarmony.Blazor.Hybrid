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
    'UnrelatedService user=private-device-data'
    '08-01 14:08:45.580 17000 17000 I B12345/OtherService: A00000/Dotnet10Smoke: status=PASS;runtime=10.0.10;arch=X64;api=26;abi=x86_64;runtimeSource=76bde136efafd0e193234e38d169752b93e3bce6;runtimePackage=ee65d55;bindings=2b68d3c;publishAot=94e69fb;startup=True;gc=True;thread=True;file=True;network=True;icu=True;hilog=True;ipc=True;callback=True'
    '08-01 14:08:45.581 17971 17971 I A00000/Dotnet10Smoke: status=PASS;runtime=10.0.10;arch=X64;api=26;abi=x86_64;runtimeSource=76bde136efafd0e193234e38d169752b93e3bce6;runtimePackage=ee65d55;bindings=2b68d3c;publishAot=94e69fb;startup=True;gc=True;thread=True;file=True;network=True;icu=True;hilog=True;ipc=True;callback=True'
    'UnrelatedService token=private-system-data'
}
exit 0
'@ | Set-Content -LiteralPath $fakeHdc -Encoding UTF8

        $fakeJava = Join-Path $TestDrive 'fake-java.ps1'
        @'
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]] $Arguments
)

$certificateIndex = [Array]::IndexOf($Arguments, '-outCertChain')
$profileIndex = [Array]::IndexOf($Arguments, '-outProfile')
if ($Arguments | Where-Object { $_ -like '*ExtractHapSignerCertificate.java' }) {
    $certificate = [Convert]::FromBase64String('MIICMzCCAbegAwIBAgIEaOC/zDAMBggqhkjOPQQDAwUAMGMxCzAJBgNVBAYTAkNOMRQwEgYDVQQKEwtPcGVuSGFybW9ueTEZMBcGA1UECxMQT3Blbkhhcm1vbnkgVGVhbTEjMCEGA1UEAxMaT3Blbkhhcm1vbnkgQXBwbGljYXRpb24gQ0EwHhcNMjEwMjAyMTIxOTMxWhcNNDkxMjMxMTIxOTMxWjBoMQswCQYDVQQGEwJDTjEUMBIGA1UEChMLT3Blbkhhcm1vbnkxGTAXBgNVBAsTEE9wZW5IYXJtb255IFRlYW0xKDAmBgNVBAMTH09wZW5IYXJtb255IEFwcGxpY2F0aW9uIFJlbGVhc2UwWTATBgcqhkjOPQIBBggqhkjOPQMBBwNCAATbYOCQQpW5fdkYHN45v0X3AHax12jPBdEDosFRIZ1eXmxOYzSGJwMfsHhUU90E8lI0TXYZnNmgM1sovubeQqATo1IwUDAfBgNVHSMEGDAWgBTbhrciFtULoUu33SV7ufEFfaItRzAOBgNVHQ8BAf8EBAMCB4AwHQYDVR0OBBYEFPtxruhlcRBQsJdwcZqLu9oNUVgaMAwGCCqGSM49BAMDBQADaAAwZQIxAJta0PQ2p4DIu/psLMdLCDgQ5UH1l0B4PGhBlMgdi2zf8nk9spazEQI/0XNwpft8QAIwHSuA2WelVi/ozAlF08DnbJrOOtOnQq5wHOPlDYB4OtUzOYJk9scotrEnJxJzGsh/')
    [IO.File]::WriteAllBytes($Arguments[-3], $certificate)
    [IO.File]::WriteAllBytes($Arguments[-2], [Text.Encoding]::ASCII.GetBytes('shared-spki'))
    [IO.File]::WriteAllBytes($Arguments[-1], [Text.Encoding]::ASCII.GetBytes('shared-spki'))
    'signer certificate resolved'
    exit 0
}
if ($Arguments -contains 'verify-app') {
    if ($certificateIndex -lt 0 -or $profileIndex -lt 0) {
        throw 'verify-app output arguments were not provided.'
    }
    $certificate = [Convert]::FromBase64String('MIICMzCCAbegAwIBAgIEaOC/zDAMBggqhkjOPQQDAwUAMGMxCzAJBgNVBAYTAkNOMRQwEgYDVQQKEwtPcGVuSGFybW9ueTEZMBcGA1UECxMQT3Blbkhhcm1vbnkgVGVhbTEjMCEGA1UEAxMaT3Blbkhhcm1vbnkgQXBwbGljYXRpb24gQ0EwHhcNMjEwMjAyMTIxOTMxWhcNNDkxMjMxMTIxOTMxWjBoMQswCQYDVQQGEwJDTjEUMBIGA1UEChMLT3Blbkhhcm1vbnkxGTAXBgNVBAsTEE9wZW5IYXJtb255IFRlYW0xKDAmBgNVBAMTH09wZW5IYXJtb255IEFwcGxpY2F0aW9uIFJlbGVhc2UwWTATBgcqhkjOPQIBBggqhkjOPQMBBwNCAATbYOCQQpW5fdkYHN45v0X3AHax12jPBdEDosFRIZ1eXmxOYzSGJwMfsHhUU90E8lI0TXYZnNmgM1sovubeQqATo1IwUDAfBgNVHSMEGDAWgBTbhrciFtULoUu33SV7ufEFfaItRzAOBgNVHQ8BAf8EBAMCB4AwHQYDVR0OBBYEFPtxruhlcRBQsJdwcZqLu9oNUVgaMAwGCCqGSM49BAMDBQADaAAwZQIxAJta0PQ2p4DIu/psLMdLCDgQ5UH1l0B4PGhBlMgdi2zf8nk9spazEQI/0XNwpft8QAIwHSuA2WelVi/ozAlF08DnbJrOOtOnQq5wHOPlDYB4OtUzOYJk9scotrEnJxJzGsh/')
    [IO.File]::WriteAllBytes($Arguments[$certificateIndex + 1], $certificate)
    Set-Content -LiteralPath $Arguments[$profileIndex + 1] -Value 'signed-profile' -Encoding ASCII
    'verify-app succeeded'
    exit 0
}
if ($Arguments -contains 'verify-profile') {
    $outputIndex = [Array]::IndexOf($Arguments, '-outFile')
    if ($outputIndex -lt 0) { throw 'verify-profile output argument was not provided.' }
    $developmentCertificate = "-----BEGIN CERTIFICATE-----`nMIIB9zCCAZugAwIBAgIEK1hGhjAMBggqhkjOPQQDAgUAMGgxCzAJBgNVBAYTAkNOMRQwEgYDVQQKEwtPcGVuSGFybW9ueTEZMBcGA1UECxMQT3Blbkhhcm1vbnkgVGVhbTEoMCYGA1UEAxMfT3Blbkhhcm1vbnkgQXBwbGljYXRpb24gUmVsZWFzZTAeFw0yMTAyMDIxMjE5MTBaFw00OTEyMzExMjE5MTBaMGgxCzAJBgNVBAYTAkNOMRQwEgYDVQQKEwtPcGVuSGFybW9ueTEZMBcGA1UECxMQT3Blbkhhcm1vbnkgVGVhbTEoMCYGA1UEAxMfT3Blbkhhcm1vbnkgQXBwbGljYXRpb24gUmVsZWFzZTBZMBMGByqGSM49AgEGCCqGSM49AwEHA0IABNtg4JBClbl92Rgc3jm/RfcAdrHXaM8F0QOiwVEhnV5ebE5jNIYnAx+weFRT3QTyUjRNdhmc2aAzWyi+5t5CoBOjMTAvMA4GA1UdDwEB/wQEAwIHgDAdBgNVHQ4EFgQU+3Gu6GVxEFCwl3Bxmou72g1RWBowDAYIKoZIzj0EAwIFAANIADBFAiB43g1DrhD95TPpbkeaVPZLVJg0GbrJIVoBXM08eevBPAIhALeHrnW5XZp7sykrmn5utdV8Op1nY91R2f26+YVLn4oD`n-----END CERTIFICATE-----`n"
    $result = [ordered]@{
        verifiedPassed = $true
        message = 'OK'
        content = [ordered]@{
            type = 'debug'
            'bundle-info' = [ordered]@{
                'bundle-name' = 'com.example.blazorapp'
                'development-certificate' = $developmentCertificate
            }
        }
    }
    $result | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $Arguments[$outputIndex + 1] -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $PSScriptRoot 'profile-verified.txt') -Value 'called' -Encoding ASCII
    'verify-profile succeeded'
    exit 0
}
throw "Unexpected signer command: $($Arguments -join ' ')"
'@ | Set-Content -LiteralPath $fakeJava -Encoding UTF8

        $hap = Join-Path $TestDrive 'entry-signed.hap'
        Set-Content -LiteralPath $hap -Value 'signed-hap' -Encoding ASCII
        $signTool = Join-Path $TestDrive 'hap-sign-tool.jar'
        Set-Content -LiteralPath $signTool -Value 'sign-tool' -Encoding ASCII
        $evidence = Join-Path $TestDrive 'evidence'
        $script = Join-Path $PSScriptRoot 'run-device-acceptance.ps1'

        & $script -Abi x86_64 -HapPath $hap -HdcPath $fakeHdc -Target '127.0.0.1:5557' -ApiLevel 26 -EvidenceRoot $evidence -JavaPath $fakeJava -HapSignToolPath $signTool | Out-Null

        if ($LASTEXITCODE -ne 0) { throw "Acceptance script exited with code $LASTEXITCODE." }
        $evidencePath = Join-Path $evidence 'api26-x86_64-evidence.json'
        if (-not (Test-Path $evidencePath)) {
            throw 'Acceptance evidence was not written.'
        }
        if (-not (Test-Path -LiteralPath (Join-Path $TestDrive 'profile-verified.txt'))) {
            throw 'The extracted signing profile was not independently verified.'
        }
        $result = Get-Content -LiteralPath $evidencePath -Raw | ConvertFrom-Json
        if ($result.schemaVersion -ne 2) { throw "Expected signature evidence schema 2, found '$($result.schemaVersion)'." }
        if (-not $result.signatureVerified) { throw 'Acceptance evidence does not record signature verification.' }
        if (-not [string]::IsNullOrWhiteSpace([string]$result.target)) {
            throw 'Acceptance evidence exposes the raw HDC target identifier.'
        }
        if ([string]::IsNullOrWhiteSpace([string]$result.targetSha256)) {
            throw 'Acceptance evidence does not hash the HDC target identifier.'
        }
        foreach ($property in 'certificateChainSha256', 'profileCertificateSha256', 'signerCertificateSha256', 'profilePublicKeySha256', 'signerPublicKeySha256', 'signerResolutionLogSha256', 'signerResolverSha256', 'signingProfileSha256', 'signingProfileVerificationSha256', 'signingProfileVerificationLogSha256', 'signatureVerificationLogSha256', 'signatureVerifierSha256') {
            if ([string]::IsNullOrWhiteSpace([string]$result.$property)) {
                throw "Acceptance evidence is missing '$property'."
            }
        }
        if ($result.profileCertificateSha256 -eq $result.signerCertificateSha256) {
            throw 'The fixture must prove public-key matching across distinct certificates.'
        }
        $hilogPath = Join-Path $evidence 'api26-x86_64-hilog.txt'
        $hilog = Get-Content -LiteralPath $hilogPath -Raw
        if ($hilog -notlike 'status=PASS;runtime=10.*' -or
            $hilog -match 'Dotnet10Smoke|UnrelatedService|private-|17971|A00000|08-01') {
            throw 'Acceptance evidence must contain only the application smoke log.'
        }
    }

    It 'rejects an unsigned HAP before contacting HDC' {
        $hdcMarker = Join-Path $TestDrive 'hdc-called.txt'
        $fakeHdc = Join-Path $TestDrive 'unexpected-hdc.ps1'
        "Set-Content -LiteralPath '$hdcMarker' -Value called; exit 0" | Set-Content -LiteralPath $fakeHdc -Encoding UTF8

        $fakeJava = Join-Path $TestDrive 'failing-java.cmd'
        "@echo Verify Hap failed, signature not found. 1>&2`r`n@exit /b 1" | Set-Content -LiteralPath $fakeJava -Encoding ASCII

        $hap = Join-Path $TestDrive 'entry-unsigned.hap'
        Set-Content -LiteralPath $hap -Value 'unsigned-hap' -Encoding ASCII
        $signTool = Join-Path $TestDrive 'hap-sign-tool.jar'
        Set-Content -LiteralPath $signTool -Value 'sign-tool' -Encoding ASCII
        $script = Join-Path $PSScriptRoot 'run-device-acceptance.ps1'

        $message = $null
        try {
            & $script -Abi x86_64 -HapPath $hap -HdcPath $fakeHdc -Target '127.0.0.1:5557' -ApiLevel 26 -EvidenceRoot (Join-Path $TestDrive 'evidence') -JavaPath $fakeJava -HapSignToolPath $signTool | Out-Null
        }
        catch {
            $message = $_.Exception.Message
        }

        if ($message -notlike '*signature verification failed*') {
            throw "Expected signature verification failure, received: $message"
        }
        if (Test-Path -LiteralPath $hdcMarker) { throw 'HDC was contacted before HAP signature verification passed.' }
    }

    It 'rejects incomplete verifier output before contacting HDC' {
        $hdcMarker = Join-Path $TestDrive 'incomplete-hdc-called.txt'
        $fakeHdc = Join-Path $TestDrive 'incomplete-hdc.ps1'
        "Set-Content -LiteralPath '$hdcMarker' -Value called; exit 0" | Set-Content -LiteralPath $fakeHdc -Encoding UTF8

        $fakeJava = Join-Path $TestDrive 'incomplete-java.ps1'
        "'verify-app succeeded'; exit 0" | Set-Content -LiteralPath $fakeJava -Encoding UTF8
        $hap = Join-Path $TestDrive 'entry-incomplete.hap'
        Set-Content -LiteralPath $hap -Value 'hap' -Encoding ASCII
        $signTool = Join-Path $TestDrive 'hap-sign-tool.jar'
        Set-Content -LiteralPath $signTool -Value 'sign-tool' -Encoding ASCII
        $script = Join-Path $PSScriptRoot 'run-device-acceptance.ps1'

        $message = $null
        try {
            & $script -Abi x86_64 -HapPath $hap -HdcPath $fakeHdc -Target '127.0.0.1:5557' -ApiLevel 26 -EvidenceRoot (Join-Path $TestDrive 'incomplete-evidence') -JavaPath $fakeJava -HapSignToolPath $signTool | Out-Null
        }
        catch {
            $message = $_.Exception.Message
        }

        if ($message -notlike '*did not produce*') { throw "Expected incomplete verifier output failure, received: $message" }
        if (Test-Path -LiteralPath $hdcMarker) { throw 'HDC was contacted before verifier outputs were validated.' }
    }

    It 'rejects malformed certificate output before contacting HDC' {
        $hdcMarker = Join-Path $TestDrive 'malformed-hdc-called.txt'
        $fakeHdc = Join-Path $TestDrive 'malformed-hdc.ps1'
        "Set-Content -LiteralPath '$hdcMarker' -Value called; exit 0" | Set-Content -LiteralPath $fakeHdc -Encoding UTF8

        $fakeJava = Join-Path $TestDrive 'malformed-java.ps1'
        @'
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]] $Arguments
)
$certificateIndex = [Array]::IndexOf($Arguments, '-outCertChain')
$profileIndex = [Array]::IndexOf($Arguments, '-outProfile')
Set-Content -LiteralPath $Arguments[$certificateIndex + 1] -Value 'not-a-certificate' -Encoding ASCII
Set-Content -LiteralPath $Arguments[$profileIndex + 1] -Value 'signed-profile' -Encoding ASCII
'verify-app succeeded'
exit 0
'@ | Set-Content -LiteralPath $fakeJava -Encoding UTF8
        $hap = Join-Path $TestDrive 'entry-malformed.hap'
        Set-Content -LiteralPath $hap -Value 'hap' -Encoding ASCII
        $signTool = Join-Path $TestDrive 'hap-sign-tool.jar'
        Set-Content -LiteralPath $signTool -Value 'sign-tool' -Encoding ASCII
        $script = Join-Path $PSScriptRoot 'run-device-acceptance.ps1'

        $message = $null
        try {
            & $script -Abi x86_64 -HapPath $hap -HdcPath $fakeHdc -Target '127.0.0.1:5557' -ApiLevel 26 -EvidenceRoot (Join-Path $TestDrive 'malformed-evidence') -JavaPath $fakeJava -HapSignToolPath $signTool | Out-Null
        }
        catch {
            $message = $_.Exception.Message
        }

        if ($message -notlike '*certificate chain is invalid*') { throw "Expected malformed certificate failure, received: $message" }
        if (Test-Path -LiteralPath $hdcMarker) { throw 'HDC was contacted before the certificate chain was validated.' }
    }

    It 'rejects a signing profile that fails independent verification before contacting HDC' {
        $hdcMarker = Join-Path $TestDrive 'profile-hdc-called.txt'
        $fakeHdc = Join-Path $TestDrive 'profile-hdc.ps1'
        "Set-Content -LiteralPath '$hdcMarker' -Value called; exit 0" | Set-Content -LiteralPath $fakeHdc -Encoding UTF8

        $certificatePath = Join-Path $TestDrive 'profile-certificate.cer'
        $certificate = [Convert]::FromBase64String('MIIDITCCAgmgAwIBAgIUTQddSft+c9Z/su5p3chK5L/2aQowDQYJKoZIhvcNAQELBQAwIDEeMBwGA1UEAwwVSEFQIFZlcmlmaWNhdGlvbiBUZXN0MB4XDTI2MDgwMTA5MDczMFoXDTM2MDcyOTA5MDczMFowIDEeMBwGA1UEAwwVSEFQIFZlcmlmaWNhdGlvbiBUZXN0MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA4YyxyEdYhUHNj7HvafZPr5zEuvZmLennST9z6Mz4o20a2Fo3MrFLJbS9a1jPK+r19UIfoDwoN5FjvjONxx4oOSmCDtn0w+mhGgPKDit73fDSli1wPcVG1BlYyGU5nc6vsVkzU4t6xSa7vUU6j4OkkjSaAYTPh27OD0RQQF//w2L5Mnvq4yXGEuZMVuZzEklWNoxiAWzchStuFrRx08NWDo15AHkRTiSFyABMwm+JePxaigCX9Ja8azLzlgxAqq+vaPXwOxtGkeAn9K7boqrKOy1VFxN9pF92jHDySaO3ZPIgIlk7TNoxrb+J0gREBWTQjFHdkkxQGq75LgDo6TadiwIDAQABo1MwUTAdBgNVHQ4EFgQUXwE0AqaMxLkZ3OaZmmtgo3LqyIAwHwYDVR0jBBgwFoAUXwE0AqaMxLkZ3OaZmmtgo3LqyIAwDwYDVR0TAQH/BAUwAwEB/zANBgkqhkiG9w0BAQsFAAOCAQEAN2nK3Y1yDOMSgLZMRCBX3Ts1abT3Zax61dRuDnTFCtIcJeocH6GrqLjEgesgOgkFFzwntLXtvu3Q2Ed1d1s+xupirEw4sCkQIlpTndKlzdP73yApSZ3lX9uUolA49HOZ4MgTFORcjsqFZFQhGrYFfO8HZtT4G8bVW8axNSsawPSY+aQkMNGpci9DB7S7QqPuLChrOoxdvB58CaEhgC8rhPK622LOSYFTQobI6/eYditeQLIO62yAEQ9PT/gzdQ4NaZ+8l+RAf/Lk/4cLazd/NdkNiPf6z6ZvJatn2EIMoW0deAUk9jFyViLNP8JU5N1IWavctsLfZj7VkmtxaL8Wkg==')
        [IO.File]::WriteAllBytes($certificatePath, $certificate)
        $fakeJava = Join-Path $TestDrive 'profile-java.ps1'
        @"
param(
    [Parameter(ValueFromRemainingArguments = `$true)]
    [string[]] `$Arguments
)
if (`$Arguments -contains 'verify-app') {
    `$certificateIndex = [Array]::IndexOf(`$Arguments, '-outCertChain')
    `$profileIndex = [Array]::IndexOf(`$Arguments, '-outProfile')
    Copy-Item -LiteralPath '$certificatePath' -Destination `$Arguments[`$certificateIndex + 1]
    Set-Content -LiteralPath `$Arguments[`$profileIndex + 1] -Value 'signed-profile' -Encoding ASCII
    exit 0
}
if (`$Arguments -contains 'verify-profile') {
    `$outputIndex = [Array]::IndexOf(`$Arguments, '-outFile')
    '{"verifiedPassed":false,"message":"invalid profile"}' | Set-Content -LiteralPath `$Arguments[`$outputIndex + 1] -Encoding UTF8
    exit 0
}
exit 1
"@ | Set-Content -LiteralPath $fakeJava -Encoding UTF8
        $hap = Join-Path $TestDrive 'entry-profile.hap'
        Set-Content -LiteralPath $hap -Value 'hap' -Encoding ASCII
        $signTool = Join-Path $TestDrive 'hap-sign-tool.jar'
        Set-Content -LiteralPath $signTool -Value 'sign-tool' -Encoding ASCII
        $script = Join-Path $PSScriptRoot 'run-device-acceptance.ps1'

        $message = $null
        try {
            & $script -Abi x86_64 -HapPath $hap -HdcPath $fakeHdc -Target '127.0.0.1:5557' -ApiLevel 26 -EvidenceRoot (Join-Path $TestDrive 'profile-evidence') -JavaPath $fakeJava -HapSignToolPath $signTool | Out-Null
        }
        catch {
            $message = $_.Exception.Message
        }

        if ($message -notlike '*signing profile verification failed*') { throw "Expected profile verification failure, received: $message" }
        if (Test-Path -LiteralPath $hdcMarker) { throw 'HDC was contacted before the signing profile was validated.' }
    }

    It 'rejects profile verification results with coerced types or casing before contacting HDC' {
        $certificate = 'MIICMzCCAbegAwIBAgIEaOC/zDAMBggqhkjOPQQDAwUAMGMxCzAJBgNVBAYTAkNOMRQwEgYDVQQKEwtPcGVuSGFybW9ueTEZMBcGA1UECxMQT3Blbkhhcm1vbnkgVGVhbTEjMCEGA1UEAxMaT3Blbkhhcm1vbnkgQXBwbGljYXRpb24gQ0EwHhcNMjEwMjAyMTIxOTMxWhcNNDkxMjMxMTIxOTMxWjBoMQswCQYDVQQGEwJDTjEUMBIGA1UEChMLT3Blbkhhcm1vbnkxGTAXBgNVBAsTEE9wZW5IYXJtb255IFRlYW0xKDAmBgNVBAMTH09wZW5IYXJtb255IEFwcGxpY2F0aW9uIFJlbGVhc2UwWTATBgcqhkjOPQIBBggqhkjOPQMBBwNCAATbYOCQQpW5fdkYHN45v0X3AHax12jPBdEDosFRIZ1eXmxOYzSGJwMfsHhUU90E8lI0TXYZnNmgM1sovubeQqATo1IwUDAfBgNVHSMEGDAWgBTbhrciFtULoUu33SV7ufEFfaItRzAOBgNVHQ8BAf8EBAMCB4AwHQYDVR0OBBYEFPtxruhlcRBQsJdwcZqLu9oNUVgaMAwGCCqGSM49BAMDBQADaAAwZQIxAJta0PQ2p4DIu/psLMdLCDgQ5UH1l0B4PGhBlMgdi2zf8nk9spazEQI/0XNwpft8QAIwHSuA2WelVi/ozAlF08DnbJrOOtOnQq5wHOPlDYB4OtUzOYJk9scotrEnJxJzGsh/'
        $cases = @(
            @{ Name = 'numeric verifiedPassed'; VerifiedPassed = 1; Message = 'OK'; Type = 'debug'; Bundle = 'com.example.blazorapp' },
            @{ Name = 'lowercase message'; VerifiedPassed = $true; Message = 'ok'; Type = 'debug'; Bundle = 'com.example.blazorapp' },
            @{ Name = 'uppercase type'; VerifiedPassed = $true; Message = 'OK'; Type = 'DEBUG'; Bundle = 'com.example.blazorapp' },
            @{ Name = 'case-varied bundle'; VerifiedPassed = $true; Message = 'OK'; Type = 'debug'; Bundle = 'COM.EXAMPLE.BLAZORAPP' }
        )

        foreach ($case in $cases) {
            $caseRoot = Join-Path $TestDrive ($case.Name -replace ' ', '-')
            New-Item -ItemType Directory -Path $caseRoot | Out-Null
            $hdcMarker = Join-Path $caseRoot 'hdc-called.txt'
            $resolverMarker = Join-Path $caseRoot 'resolver-called.txt'
            $fakeHdc = Join-Path $caseRoot 'hdc.ps1'
            "Set-Content -LiteralPath '$hdcMarker' -Value called; exit 0" | Set-Content -LiteralPath $fakeHdc -Encoding UTF8
            $profileResult = Join-Path $caseRoot 'profile-result.json'
            [ordered]@{
                verifiedPassed = $case.VerifiedPassed
                message = $case.Message
                content = [ordered]@{
                    type = $case.Type
                    'bundle-info' = [ordered]@{
                        'bundle-name' = $case.Bundle
                        'development-certificate' = "-----BEGIN CERTIFICATE-----`n$certificate`n-----END CERTIFICATE-----`n"
                    }
                }
            } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $profileResult -Encoding UTF8
            $fakeJava = Join-Path $caseRoot 'java.ps1'
            @"
param([Parameter(ValueFromRemainingArguments = `$true)][string[]] `$Arguments)
if (`$Arguments | Where-Object { `$_ -like '*ExtractHapSignerCertificate.java' }) {
    Set-Content -LiteralPath '$resolverMarker' -Value called
    exit 1
}
if (`$Arguments -contains 'verify-app') {
    `$certificateIndex = [Array]::IndexOf(`$Arguments, '-outCertChain')
    `$profileIndex = [Array]::IndexOf(`$Arguments, '-outProfile')
    [IO.File]::WriteAllBytes(`$Arguments[`$certificateIndex + 1], [Convert]::FromBase64String('$certificate'))
    Set-Content -LiteralPath `$Arguments[`$profileIndex + 1] -Value 'signed-profile' -Encoding ASCII
    exit 0
}
if (`$Arguments -contains 'verify-profile') {
    `$outputIndex = [Array]::IndexOf(`$Arguments, '-outFile')
    Copy-Item -LiteralPath '$profileResult' -Destination `$Arguments[`$outputIndex + 1]
    exit 0
}
exit 1
"@ | Set-Content -LiteralPath $fakeJava -Encoding UTF8
            $hap = Join-Path $caseRoot 'entry.hap'
            Set-Content -LiteralPath $hap -Value 'hap' -Encoding ASCII
            $signTool = Join-Path $caseRoot 'hap-sign-tool.jar'
            Set-Content -LiteralPath $signTool -Value 'sign-tool' -Encoding ASCII

            $message = $null
            try {
                & (Join-Path $PSScriptRoot 'run-device-acceptance.ps1') -Abi x86_64 -HapPath $hap -HdcPath $fakeHdc -Target '127.0.0.1:5557' -ApiLevel 26 -EvidenceRoot (Join-Path $caseRoot 'evidence') -JavaPath $fakeJava -HapSignToolPath $signTool | Out-Null
            }
            catch {
                $message = $_.Exception.Message
            }

            if ($message -notlike '*signing profile verification failed*') {
                throw "Expected strict profile failure for '$($case.Name)', received: $message"
            }
            if (Test-Path -LiteralPath $resolverMarker) { throw "Signer resolver was called for invalid profile result '$($case.Name)'." }
            if (Test-Path -LiteralPath $hdcMarker) { throw "HDC was called for invalid profile result '$($case.Name)'." }
        }
    }

    It 'rejects a signing profile certificate that does not match the HAP signer before contacting HDC' {
        $hdcMarker = Join-Path $TestDrive 'mismatch-hdc-called.txt'
        $fakeHdc = Join-Path $TestDrive 'mismatch-hdc.ps1'
        "Set-Content -LiteralPath '$hdcMarker' -Value called; exit 0" | Set-Content -LiteralPath $fakeHdc -Encoding UTF8

        $fakeJava = Join-Path $TestDrive 'mismatch-java.ps1'
        $signerCertificate = 'MIIDITCCAgmgAwIBAgIUTQddSft+c9Z/su5p3chK5L/2aQowDQYJKoZIhvcNAQELBQAwIDEeMBwGA1UEAwwVSEFQIFZlcmlmaWNhdGlvbiBUZXN0MB4XDTI2MDgwMTA5MDczMFoXDTM2MDcyOTA5MDczMFowIDEeMBwGA1UEAwwVSEFQIFZlcmlmaWNhdGlvbiBUZXN0MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA4YyxyEdYhUHNj7HvafZPr5zEuvZmLennST9z6Mz4o20a2Fo3MrFLJbS9a1jPK+r19UIfoDwoN5FjvjONxx4oOSmCDtn0w+mhGgPKDit73fDSli1wPcVG1BlYyGU5nc6vsVkzU4t6xSa7vUU6j4OkkjSaAYTPh27OD0RQQF//w2L5Mnvq4yXGEuZMVuZzEklWNoxiAWzchStuFrRx08NWDo15AHkRTiSFyABMwm+JePxaigCX9Ja8azLzlgxAqq+vaPXwOxtGkeAn9K7boqrKOy1VFxN9pF92jHDySaO3ZPIgIlk7TNoxrb+J0gREBWTQjFHdkkxQGq75LgDo6TadiwIDAQABo1MwUTAdBgNVHQ4EFgQUXwE0AqaMxLkZ3OaZmmtgo3LqyIAwHwYDVR0jBBgwFoAUXwE0AqaMxLkZ3OaZmmtgo3LqyIAwDwYDVR0TAQH/BAUwAwEB/zANBgkqhkiG9w0BAQsFAAOCAQEAN2nK3Y1yDOMSgLZMRCBX3Ts1abT3Zax61dRuDnTFCtIcJeocH6GrqLjEgesgOgkFFzwntLXtvu3Q2Ed1d1s+xupirEw4sCkQIlpTndKlzdP73yApSZ3lX9uUolA49HOZ4MgTFORcjsqFZFQhGrYFfO8HZtT4G8bVW8axNSsawPSY+aQkMNGpci9DB7S7QqPuLChrOoxdvB58CaEhgC8rhPK622LOSYFTQobI6/eYditeQLIO62yAEQ9PT/gzdQ4NaZ+8l+RAf/Lk/4cLazd/NdkNiPf6z6ZvJatn2EIMoW0deAUk9jFyViLNP8JU5N1IWavctsLfZj7VkmtxaL8Wkg=='
        $profileCertificate = 'MIIB9zCCAZugAwIBAgIEK1hGhjAMBggqhkjOPQQDAgUAMGgxCzAJBgNVBAYTAkNOMRQwEgYDVQQKEwtPcGVuSGFybW9ueTEZMBcGA1UECxMQT3Blbkhhcm1vbnkgVGVhbTEoMCYGA1UEAxMfT3Blbkhhcm1vbnkgQXBwbGljYXRpb24gUmVsZWFzZTAeFw0yMTAyMDIxMjE5MTBaFw00OTEyMzExMjE5MTBaMGgxCzAJBgNVBAYTAkNOMRQwEgYDVQQKEwtPcGVuSGFybW9ueTEZMBcGA1UECxMQT3Blbkhhcm1vbnkgVGVhbTEoMCYGA1UEAxMfT3Blbkhhcm1vbnkgQXBwbGljYXRpb24gUmVsZWFzZTBZMBMGByqGSM49AgEGCCqGSM49AwEHA0IABNtg4JBClbl92Rgc3jm/RfcAdrHXaM8F0QOiwVEhnV5ebE5jNIYnAx+weFRT3QTyUjRNdhmc2aAzWyi+5t5CoBOjMTAvMA4GA1UdDwEB/wQEAwIHgDAdBgNVHQ4EFgQU+3Gu6GVxEFCwl3Bxmou72g1RWBowDAYIKoZIzj0EAwIFAANIADBFAiB43g1DrhD95TPpbkeaVPZLVJg0GbrJIVoBXM08eevBPAIhALeHrnW5XZp7sykrmn5utdV8Op1nY91R2f26+YVLn4oD'
        @"
param(
    [Parameter(ValueFromRemainingArguments = `$true)]
    [string[]] `$Arguments
)
if (`$Arguments | Where-Object { `$_ -like '*ExtractHapSignerCertificate.java' }) {
    [IO.File]::WriteAllBytes(`$Arguments[-3], [Convert]::FromBase64String('$signerCertificate'))
    [IO.File]::WriteAllBytes(`$Arguments[-2], [Text.Encoding]::ASCII.GetBytes('profile-spki'))
    [IO.File]::WriteAllBytes(`$Arguments[-1], [Text.Encoding]::ASCII.GetBytes('signer-spki'))
    exit 0
}
if (`$Arguments -contains 'verify-app') {
    `$certificateIndex = [Array]::IndexOf(`$Arguments, '-outCertChain')
    `$profileIndex = [Array]::IndexOf(`$Arguments, '-outProfile')
    [IO.File]::WriteAllBytes(`$Arguments[`$certificateIndex + 1], [Convert]::FromBase64String('$signerCertificate'))
    Set-Content -LiteralPath `$Arguments[`$profileIndex + 1] -Value 'signed-profile' -Encoding ASCII
    exit 0
}
if (`$Arguments -contains 'verify-profile') {
    `$outputIndex = [Array]::IndexOf(`$Arguments, '-outFile')
    `$certificate = "-----BEGIN CERTIFICATE-----``n$profileCertificate``n-----END CERTIFICATE-----``n"
    `$result = [ordered]@{ verifiedPassed = `$true; message = 'OK'; content = [ordered]@{ type = 'debug'; 'bundle-info' = [ordered]@{ 'bundle-name' = 'com.example.blazorapp'; 'development-certificate' = `$certificate } } }
    `$result | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath `$Arguments[`$outputIndex + 1] -Encoding UTF8
    exit 0
}
exit 1
"@ | Set-Content -LiteralPath $fakeJava -Encoding UTF8
        $hap = Join-Path $TestDrive 'entry-mismatch.hap'
        Set-Content -LiteralPath $hap -Value 'hap' -Encoding ASCII
        $signTool = Join-Path $TestDrive 'hap-sign-tool.jar'
        Set-Content -LiteralPath $signTool -Value 'sign-tool' -Encoding ASCII
        $script = Join-Path $PSScriptRoot 'run-device-acceptance.ps1'

        $message = $null
        try {
            & $script -Abi x86_64 -HapPath $hap -HdcPath $fakeHdc -Target '127.0.0.1:5557' -ApiLevel 26 -EvidenceRoot (Join-Path $TestDrive 'mismatch-evidence') -JavaPath $fakeJava -HapSignToolPath $signTool | Out-Null
        }
        catch {
            $message = $_.Exception.Message
        }

        if ($message -notlike '*does not match*') { throw "Expected signer/profile mismatch failure, received: $message" }
        if (Test-Path -LiteralPath $hdcMarker) { throw 'HDC was contacted before signer/profile certificate consistency was validated.' }
    }

    It 'rejects a matching certificate in the exported set when the actual HAP signer has a different public key' {
        $hdcMarker = Join-Path $TestDrive 'signer-leaf-hdc-called.txt'
        $fakeHdc = Join-Path $TestDrive 'signer-leaf-hdc.ps1'
        "Set-Content -LiteralPath '$hdcMarker' -Value called; exit 0" | Set-Content -LiteralPath $fakeHdc -Encoding UTF8

        $fakeJava = Join-Path $TestDrive 'signer-leaf-java.ps1'
        $matchingCertificate = 'MIICMzCCAbegAwIBAgIEaOC/zDAMBggqhkjOPQQDAwUAMGMxCzAJBgNVBAYTAkNOMRQwEgYDVQQKEwtPcGVuSGFybW9ueTEZMBcGA1UECxMQT3Blbkhhcm1vbnkgVGVhbTEjMCEGA1UEAxMaT3Blbkhhcm1vbnkgQXBwbGljYXRpb24gQ0EwHhcNMjEwMjAyMTIxOTMxWhcNNDkxMjMxMTIxOTMxWjBoMQswCQYDVQQGEwJDTjEUMBIGA1UEChMLT3Blbkhhcm1vbnkxGTAXBgNVBAsTEE9wZW5IYXJtb255IFRlYW0xKDAmBgNVBAMTH09wZW5IYXJtb255IEFwcGxpY2F0aW9uIFJlbGVhc2UwWTATBgcqhkjOPQIBBggqhkjOPQMBBwNCAATbYOCQQpW5fdkYHN45v0X3AHax12jPBdEDosFRIZ1eXmxOYzSGJwMfsHhUU90E8lI0TXYZnNmgM1sovubeQqATo1IwUDAfBgNVHSMEGDAWgBTbhrciFtULoUu33SV7ufEFfaItRzAOBgNVHQ8BAf8EBAMCB4AwHQYDVR0OBBYEFPtxruhlcRBQsJdwcZqLu9oNUVgaMAwGCCqGSM49BAMDBQADaAAwZQIxAJta0PQ2p4DIu/psLMdLCDgQ5UH1l0B4PGhBlMgdi2zf8nk9spazEQI/0XNwpft8QAIwHSuA2WelVi/ozAlF08DnbJrOOtOnQq5wHOPlDYB4OtUzOYJk9scotrEnJxJzGsh/'
        $actualSignerCertificate = 'MIIDITCCAgmgAwIBAgIUTQddSft+c9Z/su5p3chK5L/2aQowDQYJKoZIhvcNAQELBQAwIDEeMBwGA1UEAwwVSEFQIFZlcmlmaWNhdGlvbiBUZXN0MB4XDTI2MDgwMTA5MDczMFoXDTM2MDcyOTA5MDczMFowIDEeMBwGA1UEAwwVSEFQIFZlcmlmaWNhdGlvbiBUZXN0MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA4YyxyEdYhUHNj7HvafZPr5zEuvZmLennST9z6Mz4o20a2Fo3MrFLJbS9a1jPK+r19UIfoDwoN5FjvjONxx4oOSmCDtn0w+mhGgPKDit73fDSli1wPcVG1BlYyGU5nc6vsVkzU4t6xSa7vUU6j4OkkjSaAYTPh27OD0RQQF//w2L5Mnvq4yXGEuZMVuZzEklWNoxiAWzchStuFrRx08NWDo15AHkRTiSFyABMwm+JePxaigCX9Ja8azLzlgxAqq+vaPXwOxtGkeAn9K7boqrKOy1VFxN9pF92jHDySaO3ZPIgIlk7TNoxrb+J0gREBWTQjFHdkkxQGq75LgDo6TadiwIDAQABo1MwUTAdBgNVHQ4EFgQUXwE0AqaMxLkZ3OaZmmtgo3LqyIAwHwYDVR0jBBgwFoAUXwE0AqaMxLkZ3OaZmmtgo3LqyIAwDwYDVR0TAQH/BAUwAwEB/zANBgkqhkiG9w0BAQsFAAOCAQEAN2nK3Y1yDOMSgLZMRCBX3Ts1abT3Zax61dRuDnTFCtIcJeocH6GrqLjEgesgOgkFFzwntLXtvu3Q2Ed1d1s+xupirEw4sCkQIlpTndKlzdP73yApSZ3lX9uUolA49HOZ4MgTFORcjsqFZFQhGrYFfO8HZtT4G8bVW8axNSsawPSY+aQkMNGpci9DB7S7QqPuLChrOoxdvB58CaEhgC8rhPK622LOSYFTQobI6/eYditeQLIO62yAEQ9PT/gzdQ4NaZ+8l+RAf/Lk/4cLazd/NdkNiPf6z6ZvJatn2EIMoW0deAUk9jFyViLNP8JU5N1IWavctsLfZj7VkmtxaL8Wkg=='
        @"
param(
    [Parameter(ValueFromRemainingArguments = `$true)]
    [string[]] `$Arguments
)
if (`$Arguments | Where-Object { `$_ -like '*ExtractHapSignerCertificate.java' }) {
    [IO.File]::WriteAllBytes(`$Arguments[-3], [Convert]::FromBase64String('$actualSignerCertificate'))
    [IO.File]::WriteAllBytes(`$Arguments[-2], [Text.Encoding]::ASCII.GetBytes('profile-spki'))
    [IO.File]::WriteAllBytes(`$Arguments[-1], [Text.Encoding]::ASCII.GetBytes('actual-signer-spki'))
    exit 0
}
if (`$Arguments -contains 'verify-app') {
    `$certificateIndex = [Array]::IndexOf(`$Arguments, '-outCertChain')
    `$profileIndex = [Array]::IndexOf(`$Arguments, '-outProfile')
    `$matchingPem = "-----BEGIN CERTIFICATE-----``n$matchingCertificate``n-----END CERTIFICATE-----``n"
    `$signerPem = "-----BEGIN CERTIFICATE-----``n$actualSignerCertificate``n-----END CERTIFICATE-----``n"
    Set-Content -LiteralPath `$Arguments[`$certificateIndex + 1] -Value (`$matchingPem + `$signerPem) -Encoding ASCII
    Set-Content -LiteralPath `$Arguments[`$profileIndex + 1] -Value 'signed-profile' -Encoding ASCII
    exit 0
}
if (`$Arguments -contains 'verify-profile') {
    `$outputIndex = [Array]::IndexOf(`$Arguments, '-outFile')
    `$certificate = "-----BEGIN CERTIFICATE-----``n$matchingCertificate``n-----END CERTIFICATE-----``n"
    `$result = [ordered]@{ verifiedPassed = `$true; message = 'OK'; content = [ordered]@{ type = 'debug'; 'bundle-info' = [ordered]@{ 'bundle-name' = 'com.example.blazorapp'; 'development-certificate' = `$certificate } } }
    `$result | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath `$Arguments[`$outputIndex + 1] -Encoding UTF8
    exit 0
}
exit 1
"@ | Set-Content -LiteralPath $fakeJava -Encoding UTF8
        $hap = Join-Path $TestDrive 'entry-signer-leaf.hap'
        Set-Content -LiteralPath $hap -Value 'hap' -Encoding ASCII
        $signTool = Join-Path $TestDrive 'hap-sign-tool.jar'
        Set-Content -LiteralPath $signTool -Value 'sign-tool' -Encoding ASCII
        $script = Join-Path $PSScriptRoot 'run-device-acceptance.ps1'

        $message = $null
        try {
            & $script -Abi x86_64 -HapPath $hap -HdcPath $fakeHdc -Target '127.0.0.1:5557' -ApiLevel 26 -EvidenceRoot (Join-Path $TestDrive 'signer-leaf-evidence') -JavaPath $fakeJava -HapSignToolPath $signTool | Out-Null
        }
        catch {
            $message = $_.Exception.Message
        }

        if ($message -notlike '*does not match the actual HAP signer certificate public key*') {
            throw "Expected actual signer/profile mismatch failure, received: $message"
        }
        if (Test-Path -LiteralPath $hdcMarker) { throw 'HDC was contacted before the actual HAP signer was validated.' }
    }

    It 'preserves workflow evidence when device setup fails' {
        $workflow = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\.github\workflows\dotnet10-hap.yml') -Raw

        if ([regex]::Matches($workflow, 'New-Item -ItemType Directory -Path \$evidenceRoot -Force').Count -lt 2) {
            throw 'Device workflow does not initialize evidence roots for both setup phases.'
        }
        foreach ($token in @(
            'workflow-initialized.txt',
            'workflow-build-failure.txt',
            'workflow-device-acceptance-failure.txt',
            'workflow-host-publish-failure.txt',
            'if: always()',
            'if-no-files-found: error',
            '*-evidence.json',
            '*-hilog.txt',
            'workflow-*.txt',
            'host-publish-status-api${{ matrix.api }}-${{ matrix.abi }}')) {
            if ($workflow.IndexOf($token, [StringComparison]::Ordinal) -lt 0) {
                throw "Device workflow is missing failure evidence contract '$token'."
            }
        }
        foreach ($forbiddenPattern in @(
            '\*-signature-verification\.txt',
            '\*-profile-verification\.txt',
            '\*-signer-resolution\.txt',
            '(?m)^\s+path:\s+artifacts/device-evidence/\$\{\{ matrix\.abi \}\}\s*$')) {
            if ([regex]::IsMatch($workflow, $forbiddenPattern)) {
                throw "Device workflow uploads sensitive evidence matching '$forbiddenPattern'."
            }
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
