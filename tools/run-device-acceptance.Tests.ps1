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
    if ($env:FAKE_DEVICE_API_LEVEL) { $env:FAKE_DEVICE_API_LEVEL } else { '26' }
    exit 0
}
if ($Arguments -contains 'bm' -and $Arguments -contains 'dump' -and $Arguments -contains '-a') {
    if ($env:FAKE_BUNDLE_QUERY_INVALID -eq '1') { exit 0 }
    'ID: 100:'
    if ($env:FAKE_BUNDLE_ABSENT -ne '1') { "`tcom.example.blazorapp" }
    exit 0
}
if ($Arguments -contains 'uninstall') {
    Set-Content -LiteralPath (Join-Path $PSScriptRoot 'uninstall-called.txt') -Value called -Encoding ASCII
    Remove-Item -LiteralPath (Join-Path $PSScriptRoot 'installed-hap.txt') -Force -ErrorAction SilentlyContinue
    '[Info]App uninstall path: msg:uninstall bundle successfully.'
    'AppMod finish'
    exit 0
}
if ($Arguments -contains 'install') {
    if ($env:FAKE_HDC_INSTALL_ERROR -eq '1') {
        Set-Content -LiteralPath (Join-Path $PSScriptRoot 'installed-hap.txt') -Value 'mixed-error-snapshot.hap' -Encoding UTF8
        '[Info]App install path:snapshot.hap msg:error: failed to install bundle. code:9568332 error: install sign info inconsistent. msg:install bundle successfully.'
        'AppMod finish'
        exit 0
    }
    $installIndex = [Array]::IndexOf($Arguments, 'install')
    Set-Content -LiteralPath (Join-Path $PSScriptRoot 'installed-hap.txt') -Value $Arguments[$installIndex + 1] -Encoding UTF8
    '[Info]App install path:snapshot.hap msg:install bundle successfully.'
    'AppMod finish'
    exit 0
}
if ($Arguments -contains 'start') {
    Set-Content -LiteralPath (Join-Path $PSScriptRoot 'launch-called.txt') -Value called -Encoding ASCII
    'start ability successfully.'
    exit 0
}
if ($Arguments -contains 'pidof') {
    if (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'installed-hap.txt')) { '17971' }
    exit 0
}
if ($Arguments -contains '-r') {
    if ($env:FAKE_HILOG_RESET_ERROR -eq '1') {
        'msg:error: failed to clear hilog. Log type core,app,only_prerelease buffer clear successfully'
        exit 0
    }
    'Log type core,app,only_prerelease buffer clear successfully'
    exit 0
}
if ($Arguments -contains '-x') {
    if ($env:FAKE_HDC_HILOG_READ_ERROR -eq '1') {
        'msg:error: failed to read hilog'
    }
    'UnrelatedService user=private-device-data'
    '08-01 14:08:45.579 17971 17971 I A00000/Dotnet10Smoke: status=PASS;runtime=10.0.10;arch=X64;api=26;abi=x86_64;sample=0123456789abcdef0123456789abcdef01234567;run=stale-run;runtimeSource=ee78787154e1c1a76df4b76b1797d7a09c63937c;runtimePackage=44c8423;bindings=43413d4;publishAot=4210967;startup=True;gc=True;thread=True;file=True;network=True;icu=True;hilog=True;ipc=True;callback=True'
    '08-01 14:08:45.580 17000 17000 I B12345/OtherService: A00000/Dotnet10Smoke: status=PASS;runtime=10.0.10;arch=X64;api=26;abi=x86_64;sample=0123456789abcdef0123456789abcdef01234567;run=pester-api26-x86_64;runtimeSource=ee78787154e1c1a76df4b76b1797d7a09c63937c;runtimePackage=44c8423;bindings=43413d4;publishAot=4210967;startup=True;gc=True;thread=True;file=True;network=True;icu=True;hilog=True;ipc=True;callback=True'
    '08-01 14:08:45.581 17972 17972 I A00000/Dotnet10Smoke: status=PASS;runtime=10.0.10;arch=X64;api=26;abi=x86_64;sample=0123456789abcdef0123456789abcdef01234567;run=pester-api26-x86_64;runtimeSource=ee78787154e1c1a76df4b76b1797d7a09c63937c;runtimePackage=44c8423;bindings=43413d4;publishAot=4210967;startup=True;gc=True;thread=True;file=True;network=True;icu=True;hilog=True;ipc=True;callback=True'
    '08-01 14:08:45.582 17971 17971 I A00000/com.example.blazorapp/Dotnet10Smoke: status=PASS;runtime=10.0.10;arch=X64;api=26;abi=x86_64;sample=0123456789abcdef0123456789abcdef01234567;run=pester-api26-x86_64;runtimeSource=ee78787154e1c1a76df4b76b1797d7a09c63937c;runtimePackage=44c8423;bindings=43413d4;publishAot=4210967;startup=True;gc=True;thread=True;file=True;network=True;icu=True;hilog=True;ipc=True;callback=True'
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
    if ($env:FAKE_SIGNER_RESOLUTION_ERROR -eq '1') {
        'RAW_PRIVATE_SIGNER_OUTPUT'
        exit 1
    }
    $certificate = [Convert]::FromBase64String('MIICMzCCAbegAwIBAgIEaOC/zDAMBggqhkjOPQQDAwUAMGMxCzAJBgNVBAYTAkNOMRQwEgYDVQQKEwtPcGVuSGFybW9ueTEZMBcGA1UECxMQT3Blbkhhcm1vbnkgVGVhbTEjMCEGA1UEAxMaT3Blbkhhcm1vbnkgQXBwbGljYXRpb24gQ0EwHhcNMjEwMjAyMTIxOTMxWhcNNDkxMjMxMTIxOTMxWjBoMQswCQYDVQQGEwJDTjEUMBIGA1UEChMLT3Blbkhhcm1vbnkxGTAXBgNVBAsTEE9wZW5IYXJtb255IFRlYW0xKDAmBgNVBAMTH09wZW5IYXJtb255IEFwcGxpY2F0aW9uIFJlbGVhc2UwWTATBgcqhkjOPQIBBggqhkjOPQMBBwNCAATbYOCQQpW5fdkYHN45v0X3AHax12jPBdEDosFRIZ1eXmxOYzSGJwMfsHhUU90E8lI0TXYZnNmgM1sovubeQqATo1IwUDAfBgNVHSMEGDAWgBTbhrciFtULoUu33SV7ufEFfaItRzAOBgNVHQ8BAf8EBAMCB4AwHQYDVR0OBBYEFPtxruhlcRBQsJdwcZqLu9oNUVgaMAwGCCqGSM49BAMDBQADaAAwZQIxAJta0PQ2p4DIu/psLMdLCDgQ5UH1l0B4PGhBlMgdi2zf8nk9spazEQI/0XNwpft8QAIwHSuA2WelVi/ozAlF08DnbJrOOtOnQq5wHOPlDYB4OtUzOYJk9scotrEnJxJzGsh/')
    [IO.File]::WriteAllBytes($Arguments[-3], $certificate)
    [IO.File]::WriteAllBytes($Arguments[-2], [Text.Encoding]::ASCII.GetBytes('shared-spki'))
    [IO.File]::WriteAllBytes($Arguments[-1], [Text.Encoding]::ASCII.GetBytes('shared-spki'))
    'signer certificate resolved'
    exit 0
}
if ($Arguments -contains 'verify-app') {
    if ($env:FAKE_VERIFY_APP_ERROR -eq '1') {
        'RAW_PRIVATE_VERIFY_APP_OUTPUT'
        exit 1
    }
    if ($certificateIndex -lt 0 -or $profileIndex -lt 0) {
        throw 'verify-app output arguments were not provided.'
    }
    $inputIndex = [Array]::IndexOf($Arguments, '-inFile')
    Set-Content -LiteralPath (Join-Path $PSScriptRoot 'verified-hap.txt') -Value $Arguments[$inputIndex + 1] -Encoding UTF8
    $certificate = [Convert]::FromBase64String('MIICMzCCAbegAwIBAgIEaOC/zDAMBggqhkjOPQQDAwUAMGMxCzAJBgNVBAYTAkNOMRQwEgYDVQQKEwtPcGVuSGFybW9ueTEZMBcGA1UECxMQT3Blbkhhcm1vbnkgVGVhbTEjMCEGA1UEAxMaT3Blbkhhcm1vbnkgQXBwbGljYXRpb24gQ0EwHhcNMjEwMjAyMTIxOTMxWhcNNDkxMjMxMTIxOTMxWjBoMQswCQYDVQQGEwJDTjEUMBIGA1UEChMLT3Blbkhhcm1vbnkxGTAXBgNVBAsTEE9wZW5IYXJtb255IFRlYW0xKDAmBgNVBAMTH09wZW5IYXJtb255IEFwcGxpY2F0aW9uIFJlbGVhc2UwWTATBgcqhkjOPQIBBggqhkjOPQMBBwNCAATbYOCQQpW5fdkYHN45v0X3AHax12jPBdEDosFRIZ1eXmxOYzSGJwMfsHhUU90E8lI0TXYZnNmgM1sovubeQqATo1IwUDAfBgNVHSMEGDAWgBTbhrciFtULoUu33SV7ufEFfaItRzAOBgNVHQ8BAf8EBAMCB4AwHQYDVR0OBBYEFPtxruhlcRBQsJdwcZqLu9oNUVgaMAwGCCqGSM49BAMDBQADaAAwZQIxAJta0PQ2p4DIu/psLMdLCDgQ5UH1l0B4PGhBlMgdi2zf8nk9spazEQI/0XNwpft8QAIwHSuA2WelVi/ozAlF08DnbJrOOtOnQq5wHOPlDYB4OtUzOYJk9scotrEnJxJzGsh/')
    [IO.File]::WriteAllBytes($Arguments[$certificateIndex + 1], $certificate)
    Set-Content -LiteralPath $Arguments[$profileIndex + 1] -Value 'signed-profile' -Encoding ASCII
    'verify-app succeeded'
    exit 0
}
if ($Arguments -contains 'verify-profile') {
    if ($env:FAKE_VERIFY_PROFILE_ERROR -eq '1') {
        'RAW_PRIVATE_VERIFY_PROFILE_OUTPUT'
        exit 1
    }
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
        New-Item -ItemType Directory -Path $evidence | Out-Null
        Set-Content -LiteralPath (Join-Path $evidence 'api26-x86_64-evidence.json') -Value '{"result":"STALE_PASS"}' -Encoding ASCII
        Set-Content -LiteralPath (Join-Path $evidence 'api26-x86_64-hilog.txt') -Value 'stale smoke' -Encoding ASCII
        $script = Join-Path $PSScriptRoot 'run-device-acceptance.ps1'

        & $script -Abi x86_64 -HapPath $hap -HdcPath $fakeHdc -Target '127.0.0.1:5557' -ApiLevel 26 -EvidenceRoot $evidence -JavaPath $fakeJava -HapSignToolPath $signTool -SampleCommit '0123456789abcdef0123456789abcdef01234567' -EvidenceRunId 'pester-api26-x86_64' | Out-Null

        if ($LASTEXITCODE -ne 0) { throw "Acceptance script exited with code $LASTEXITCODE." }
        $evidencePath = Join-Path $evidence 'api26-x86_64-evidence.json'
        if (-not (Test-Path $evidencePath)) {
            throw 'Acceptance evidence was not written.'
        }
        if (-not (Test-Path -LiteralPath (Join-Path $TestDrive 'profile-verified.txt'))) {
            throw 'The extracted signing profile was not independently verified.'
        }
        $result = Get-Content -LiteralPath $evidencePath -Raw | ConvertFrom-Json
        if ($result.schemaVersion -ne 3) { throw "Expected acceptance evidence schema 3, found '$($result.schemaVersion)'." }
        if (-not $result.signatureVerified) { throw 'Acceptance evidence does not record signature verification.' }
        if (-not [string]::IsNullOrWhiteSpace([string]$result.target) -or
            -not [string]::IsNullOrWhiteSpace([string]$result.targetSha256)) {
            throw 'Acceptance evidence exposes a raw or correlatable HDC target identifier.'
        }
        if ($result.sampleCommit -cne '0123456789abcdef0123456789abcdef01234567') { throw 'Acceptance evidence is not bound to the sample source commit.' }
        if ($result.evidenceRunId -cne 'pester-api26-x86_64') { throw 'Acceptance evidence is not bound to the run identifier.' }
        foreach ($property in 'evidenceProducerSha256', 'signaturePolicySha256', 'signatureVerifierSha256', 'signerResolverSha256', 'hdcExecutableSha256', 'javaExecutableSha256', 'hapSnapshotSha256', 'certificateChainSha256', 'profileCertificateSha256', 'signerCertificateSha256', 'profilePublicKeySha256', 'signerPublicKeySha256', 'signerResolutionLogSha256', 'signingProfileSha256', 'signingProfileVerificationSha256', 'signingProfileVerificationLogSha256', 'signatureVerificationLogSha256') {
            if ([string]::IsNullOrWhiteSpace([string]$result.$property)) {
                throw "Acceptance evidence is missing '$property'."
            }
        }
        if ($result.profileCertificateSha256 -eq $result.signerCertificateSha256) {
            throw 'The fixture must prove public-key matching across distinct certificates.'
        }
        foreach ($attestation in @(
            'signatureAttestation',
            'uninstallAttestation',
            'installAttestation',
            'launchAttestation')) {
            if ($result.$attestation.status -cne 'PASS') {
                throw "Acceptance evidence is missing a PASS $attestation."
            }
            if ([string]::IsNullOrWhiteSpace([string]$result.$attestation.outputSha256)) {
                throw "Acceptance evidence is missing the raw-output hash for $attestation."
            }
        }
        if ($result.processAttestation.status -cne 'PASS' -or
            -not $result.processAttestation.pidBound -or
            $result.processAttestation.processCount -ne 1 -or
            -not [string]::IsNullOrWhiteSpace([string]$result.processAttestation.processId) -or
            -not [string]::IsNullOrWhiteSpace([string]$result.processAttestation.outputSha256)) {
            throw 'Process attestation must prove one PID binding without publishing PID data or an enumerable PID hash.'
        }
        if ([string]::IsNullOrWhiteSpace([string]$result.privateEvidenceManifestSha256)) {
            throw 'Acceptance evidence does not commit to the privately retained raw evidence manifest.'
        }
        $verifiedHap = (Get-Content -LiteralPath (Join-Path $TestDrive 'verified-hap.txt') -Raw).Trim()
        $installedHap = (Get-Content -LiteralPath (Join-Path $TestDrive 'installed-hap.txt') -Raw).Trim()
        if ($verifiedHap -cne $installedHap -or $verifiedHap -ceq (Resolve-Path -LiteralPath $hap).Path) {
            throw 'Verification and installation must use the same private HAP snapshot.'
        }
        if ((Get-FileHash -LiteralPath $verifiedHap -Algorithm SHA256).Hash.ToLowerInvariant() -cne $result.hapSnapshotSha256) {
            throw 'Acceptance evidence does not bind the verified and installed HAP snapshot.'
        }
        $hilogPath = Join-Path $evidence 'api26-x86_64-hilog.txt'
        $hilog = Get-Content -LiteralPath $hilogPath -Raw
        if ($hilog -notlike 'status=PASS;runtime=10.*' -or
            $hilog -match 'Dotnet10Smoke|UnrelatedService|private-|17971|A00000|08-01') {
            throw 'Acceptance evidence must contain only the application smoke log.'
        }

        $compatibilityEvidence = Join-Path $TestDrive 'higher-device-api-evidence'
        $env:FAKE_DEVICE_API_LEVEL = '27'
        try {
            & $script -Abi x86_64 -HapPath $hap -HdcPath $fakeHdc -Target '127.0.0.1:5557' `
                -ApiLevel 26 -DeviceApiLevel 27 -EvidenceRoot $compatibilityEvidence -JavaPath $fakeJava `
                -HapSignToolPath $signTool -SampleCommit '0123456789abcdef0123456789abcdef01234567' `
                -EvidenceRunId 'pester-api26-x86_64' -PrivateEvidenceRoot (Join-Path $TestDrive 'higher-device-api-private') | Out-Null
        }
        finally {
            Remove-Item Env:FAKE_DEVICE_API_LEVEL -ErrorAction SilentlyContinue
        }
        $compatibilityResult = Get-Content -LiteralPath (Join-Path $compatibilityEvidence 'api26-x86_64-evidence.json') -Raw | ConvertFrom-Json
        if ($compatibilityResult.deviceApi -ne 27 -or $compatibilityResult.buildApi -ne 26 -or
            $compatibilityResult.runtimeBaselineApi -ne 13 -or
            $compatibilityResult.apiLevel -ne 27 -or $compatibilityResult.buildApiLevel -ne 26) {
            throw 'Compatibility evidence must distinguish the build API from the higher device API.'
        }

        foreach ($case in @(
            @{ Environment = 'FAKE_VERIFY_APP_ERROR'; Stage = 'signature verification failed'; Sentinel = 'RAW_PRIVATE_VERIFY_APP_OUTPUT' },
            @{ Environment = 'FAKE_VERIFY_PROFILE_ERROR'; Stage = 'signing profile verification failed'; Sentinel = 'RAW_PRIVATE_VERIFY_PROFILE_OUTPUT' },
            @{ Environment = 'FAKE_SIGNER_RESOLUTION_ERROR'; Stage = 'signer certificate resolution failed'; Sentinel = 'RAW_PRIVATE_SIGNER_OUTPUT' })) {
            Set-Item -Path ("Env:{0}" -f $case.Environment) -Value '1'
            $failure = $null
            try {
                & $script -Abi x86_64 -HapPath $hap -HdcPath $fakeHdc -Target '127.0.0.1:5557' -ApiLevel 26 -EvidenceRoot (Join-Path $TestDrive "private-$($case.Environment)") -JavaPath $fakeJava -HapSignToolPath $signTool -SampleCommit '0123456789abcdef0123456789abcdef01234567' -EvidenceRunId "pester-$($case.Environment)" -PrivateEvidenceRoot (Join-Path $TestDrive "private-root-$($case.Environment)") | Out-Null
            }
            catch {
                $failure = $_.Exception.Message
            }
            finally {
                Remove-Item -Path ("Env:{0}" -f $case.Environment) -ErrorAction SilentlyContinue
            }
            if ($failure -notlike "*$($case.Stage)*" -or $failure.IndexOf($case.Sentinel, [StringComparison]::Ordinal) -ge 0) {
                throw "Verifier failure was not sanitized for $($case.Environment): $failure"
            }
        }

        $hilogErrorEvidence = Join-Path $TestDrive 'hilog-error-evidence'
        Remove-Item -LiteralPath (Join-Path $TestDrive 'launch-called.txt') -Force -ErrorAction SilentlyContinue
        $env:FAKE_HILOG_RESET_ERROR = '1'
        $hilogFailure = $null
        try {
            & $script -Abi x86_64 -HapPath $hap -HdcPath $fakeHdc -Target '127.0.0.1:5557' -ApiLevel 26 -EvidenceRoot $hilogErrorEvidence -JavaPath $fakeJava -HapSignToolPath $signTool -SampleCommit '0123456789abcdef0123456789abcdef01234567' -EvidenceRunId 'pester-hilog-error' -PrivateEvidenceRoot (Join-Path $TestDrive 'hilog-error-private') | Out-Null
        }
        catch {
            $hilogFailure = $_.Exception.Message
        }
        finally {
            Remove-Item Env:FAKE_HILOG_RESET_ERROR -ErrorAction SilentlyContinue
        }
        if ($hilogFailure -notlike '*HDC command*reported a semantic error*') {
            throw "Expected semantic HiLog reset failure, received: $hilogFailure"
        }
        if (Test-Path -LiteralPath (Join-Path $TestDrive 'launch-called.txt')) {
            throw 'The application was launched after HiLog reset reported a semantic error.'
        }

        $hilogReadErrorEvidence = Join-Path $TestDrive 'hilog-read-error-evidence'
        $env:FAKE_HDC_HILOG_READ_ERROR = '1'
        $hilogReadFailure = $null
        try {
            & $script -Abi x86_64 -HapPath $hap -HdcPath $fakeHdc -Target '127.0.0.1:5557' -ApiLevel 26 -EvidenceRoot $hilogReadErrorEvidence -JavaPath $fakeJava -HapSignToolPath $signTool -SampleCommit '0123456789abcdef0123456789abcdef01234567' -EvidenceRunId 'pester-api26-x86_64' -PrivateEvidenceRoot (Join-Path $TestDrive 'hilog-read-error-private') | Out-Null
        }
        catch {
            $hilogReadFailure = $_.Exception.Message
        }
        finally {
            Remove-Item Env:FAKE_HDC_HILOG_READ_ERROR -ErrorAction SilentlyContinue
        }
        if ($hilogReadFailure -notlike '*HDC command*reported a semantic error*') {
            throw "Expected global HDC semantic failure, received: $hilogReadFailure"
        }
        foreach ($name in 'api26-x86_64-evidence.json', 'api26-x86_64-hilog.txt') {
            if (Test-Path -LiteralPath (Join-Path $hilogReadErrorEvidence $name)) {
                throw "Public PASS evidence was written after an HDC semantic error: $name"
            }
        }

        $absentEvidence = Join-Path $TestDrive 'bundle-absent-evidence'
        Remove-Item -LiteralPath (Join-Path $TestDrive 'uninstall-called.txt'), (Join-Path $TestDrive 'installed-hap.txt') -Force -ErrorAction SilentlyContinue
        $env:FAKE_BUNDLE_ABSENT = '1'
        try {
            & $script -Abi x86_64 -HapPath $hap -HdcPath $fakeHdc -Target '127.0.0.1:5557' -ApiLevel 26 -EvidenceRoot $absentEvidence -JavaPath $fakeJava -HapSignToolPath $signTool -SampleCommit '0123456789abcdef0123456789abcdef01234567' -EvidenceRunId 'pester-api26-x86_64' -PrivateEvidenceRoot (Join-Path $TestDrive 'bundle-absent-private') | Out-Null
        }
        finally {
            Remove-Item Env:FAKE_BUNDLE_ABSENT -ErrorAction SilentlyContinue
        }
        if (Test-Path -LiteralPath (Join-Path $TestDrive 'uninstall-called.txt')) {
            throw 'Uninstall was called even though the bundle query proved the app was absent.'
        }
        $absentResult = Get-Content -LiteralPath (Join-Path $absentEvidence 'api26-x86_64-evidence.json') -Raw | ConvertFrom-Json
        if ($absentResult.uninstallAttestation.status -cne 'PASS' -or
            $absentResult.uninstallAttestation.semanticResult -cne 'already-absent' -or
            [string]::IsNullOrWhiteSpace([string]$absentResult.uninstallAttestation.outputSha256)) {
            throw 'Bundle-absent acceptance did not record an exact already-absent attestation with an output hash.'
        }
        $absentAttestationPath = Join-Path $TestDrive 'bundle-absent-private\hdc-uninstall-attestation.txt'
        if (-not (Test-Path -LiteralPath (Join-Path $TestDrive 'bundle-absent-private\hdc-bundle-query.txt')) -or
            -not (Test-Path -LiteralPath $absentAttestationPath)) {
            throw 'Bundle-absent acceptance did not retain its bundle query and normalized attestation privately.'
        }
        if ((Get-FileHash -LiteralPath $absentAttestationPath -Algorithm SHA256).Hash.ToLowerInvariant() -cne
            $absentResult.uninstallAttestation.outputSha256) {
            throw 'Bundle-absent acceptance did not bind the public attestation to its normalized private record.'
        }

        $invalidQueryEvidence = Join-Path $TestDrive 'bundle-query-invalid-evidence'
        Remove-Item -LiteralPath (Join-Path $TestDrive 'installed-hap.txt') -Force -ErrorAction SilentlyContinue
        $env:FAKE_BUNDLE_QUERY_INVALID = '1'
        $invalidQueryFailure = $null
        try {
            & $script -Abi x86_64 -HapPath $hap -HdcPath $fakeHdc -Target '127.0.0.1:5557' -ApiLevel 26 -EvidenceRoot $invalidQueryEvidence -JavaPath $fakeJava -HapSignToolPath $signTool -SampleCommit '0123456789abcdef0123456789abcdef01234567' -EvidenceRunId 'pester-bundle-query-invalid' -PrivateEvidenceRoot (Join-Path $TestDrive 'bundle-query-invalid-private') | Out-Null
        }
        catch {
            $invalidQueryFailure = $_.Exception.Message
        }
        finally {
            Remove-Item Env:FAKE_BUNDLE_QUERY_INVALID -ErrorAction SilentlyContinue
        }
        if ($invalidQueryFailure -notlike '*did not return a recognizable bundle list*') {
            throw "Expected malformed bundle query failure, received: $invalidQueryFailure"
        }
        if (Test-Path -LiteralPath (Join-Path $TestDrive 'installed-hap.txt')) {
            throw 'Installation was attempted after the bundle query returned an unrecognizable response.'
        }
        foreach ($name in 'api26-x86_64-evidence.json', 'api26-x86_64-hilog.txt') {
            if (Test-Path -LiteralPath (Join-Path $invalidQueryEvidence $name)) {
                throw "Public PASS evidence was written after a malformed bundle query: $name"
            }
        }

        $installErrorEvidence = Join-Path $TestDrive 'install-error-evidence'
        New-Item -ItemType Directory -Path $installErrorEvidence | Out-Null
        Set-Content -LiteralPath (Join-Path $installErrorEvidence 'api26-x86_64-evidence.json') -Value '{"result":"STALE_PASS"}' -Encoding ASCII
        Set-Content -LiteralPath (Join-Path $installErrorEvidence 'api26-x86_64-hilog.txt') -Value 'stale smoke' -Encoding ASCII
        Remove-Item -LiteralPath (Join-Path $TestDrive 'installed-hap.txt'), (Join-Path $TestDrive 'launch-called.txt') -Force -ErrorAction SilentlyContinue
        $env:FAKE_HDC_INSTALL_ERROR = '1'
        $installFailure = $null
        try {
            & $script -Abi x86_64 -HapPath $hap -HdcPath $fakeHdc -Target '127.0.0.1:5557' -ApiLevel 26 -EvidenceRoot $installErrorEvidence -JavaPath $fakeJava -HapSignToolPath $signTool -SampleCommit '0123456789abcdef0123456789abcdef01234567' -EvidenceRunId 'pester-install-error' -PrivateEvidenceRoot (Join-Path $TestDrive 'install-error-private') | Out-Null
        }
        catch {
            $installFailure = $_.Exception.Message
        }
        finally {
            Remove-Item Env:FAKE_HDC_INSTALL_ERROR -ErrorAction SilentlyContinue
        }
        if ($installFailure -notlike '*HDC command*reported a semantic error*') {
            throw "Expected semantic install failure, received: $installFailure"
        }
        if (Test-Path -LiteralPath (Join-Path $TestDrive 'launch-called.txt')) {
            throw 'The application was launched after HDC reported an install error with exit code zero.'
        }
        foreach ($name in 'api26-x86_64-evidence.json', 'api26-x86_64-hilog.txt') {
            if (Test-Path -LiteralPath (Join-Path $installErrorEvidence $name)) {
                throw "Stale public acceptance evidence survived a failed run: $name"
            }
        }
    }

    It 'clears stale public evidence before validating the HAP or tools' {
        $evidence = Join-Path $TestDrive 'early-failure-evidence'
        New-Item -ItemType Directory -Path $evidence | Out-Null
        foreach ($name in 'api26-x86_64-evidence.json', 'api26-x86_64-hilog.txt') {
            Set-Content -LiteralPath (Join-Path $evidence $name) -Value 'STALE_PASS' -Encoding ASCII
        }

        $message = $null
        try {
            & (Join-Path $PSScriptRoot 'run-device-acceptance.ps1') -Abi x86_64 -HapPath (Join-Path $TestDrive 'missing.hap') -HdcPath 'missing-hdc' -Target '127.0.0.1:5557' -ApiLevel 26 -EvidenceRoot $evidence -JavaPath 'missing-java' -HapSignToolPath (Join-Path $TestDrive 'missing.jar') -SampleCommit '0123456789abcdef0123456789abcdef01234567' -EvidenceRunId 'pester-early-failure' | Out-Null
        }
        catch {
            $message = $_.Exception.Message
        }

        if ($message -notlike '*Signed HAP was not found*') { throw "Expected missing HAP failure, received: $message" }
        foreach ($name in 'api26-x86_64-evidence.json', 'api26-x86_64-hilog.txt') {
            if (Test-Path -LiteralPath (Join-Path $evidence $name)) {
                throw "Stale public evidence survived early validation failure: $name"
            }
        }
    }

    It 'requires semantic uninstall install and launch success instead of trusting HDC exit codes' {
        $source = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'run-device-acceptance.ps1') -Raw

        foreach ($token in @(
            "'bm', 'dump', '-a'",
            'uninstall bundle successfully.',
            'install bundle successfully.',
            'start ability successfully.')) {
            if ($source.IndexOf($token, [StringComparison]::Ordinal) -lt 0) {
                throw "Acceptance script does not require HDC semantic result '$token'."
            }
        }
        if ($source.IndexOf('msg:error:', [StringComparison]::Ordinal) -lt 0) {
            throw 'Acceptance script does not reject HDC semantic errors returned with exit code zero.'
        }
        if ($source.IndexOf('uninstall missing installed bundle.', [StringComparison]::Ordinal) -ge 0) {
            throw 'Acceptance script still treats a missing-bundle uninstall error as success.'
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
            & $script -Abi x86_64 -HapPath $hap -HdcPath $fakeHdc -Target '127.0.0.1:5557' -ApiLevel 26 -EvidenceRoot (Join-Path $TestDrive 'evidence') -JavaPath $fakeJava -HapSignToolPath $signTool -SampleCommit '0123456789abcdef0123456789abcdef01234567' -EvidenceRunId 'pester-api26-x86_64' | Out-Null
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
            & $script -Abi x86_64 -HapPath $hap -HdcPath $fakeHdc -Target '127.0.0.1:5557' -ApiLevel 26 -EvidenceRoot (Join-Path $TestDrive 'incomplete-evidence') -JavaPath $fakeJava -HapSignToolPath $signTool -SampleCommit '0123456789abcdef0123456789abcdef01234567' -EvidenceRunId 'pester-api26-x86_64' | Out-Null
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
            & $script -Abi x86_64 -HapPath $hap -HdcPath $fakeHdc -Target '127.0.0.1:5557' -ApiLevel 26 -EvidenceRoot (Join-Path $TestDrive 'malformed-evidence') -JavaPath $fakeJava -HapSignToolPath $signTool -SampleCommit '0123456789abcdef0123456789abcdef01234567' -EvidenceRunId 'pester-api26-x86_64' | Out-Null
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
    '{"verifiedPassed":false,"message":"RAW_PRIVATE_PROFILE_MESSAGE"}' | Set-Content -LiteralPath `$Arguments[`$outputIndex + 1] -Encoding UTF8
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
            & $script -Abi x86_64 -HapPath $hap -HdcPath $fakeHdc -Target '127.0.0.1:5557' -ApiLevel 26 -EvidenceRoot (Join-Path $TestDrive 'profile-evidence') -JavaPath $fakeJava -HapSignToolPath $signTool -SampleCommit '0123456789abcdef0123456789abcdef01234567' -EvidenceRunId 'pester-api26-x86_64' | Out-Null
        }
        catch {
            $message = $_.Exception.Message
        }

        if ($message -notlike '*signing profile verification failed*' -or
            $message.IndexOf('RAW_PRIVATE_PROFILE_MESSAGE', [StringComparison]::Ordinal) -ge 0) {
            throw "Expected sanitized profile verification failure, received: $message"
        }
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
                & (Join-Path $PSScriptRoot 'run-device-acceptance.ps1') -Abi x86_64 -HapPath $hap -HdcPath $fakeHdc -Target '127.0.0.1:5557' -ApiLevel 26 -EvidenceRoot (Join-Path $caseRoot 'evidence') -JavaPath $fakeJava -HapSignToolPath $signTool -SampleCommit '0123456789abcdef0123456789abcdef01234567' -EvidenceRunId 'pester-api26-x86_64' | Out-Null
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
            & $script -Abi x86_64 -HapPath $hap -HdcPath $fakeHdc -Target '127.0.0.1:5557' -ApiLevel 26 -EvidenceRoot (Join-Path $TestDrive 'mismatch-evidence') -JavaPath $fakeJava -HapSignToolPath $signTool -SampleCommit '0123456789abcdef0123456789abcdef01234567' -EvidenceRunId 'pester-api26-x86_64' | Out-Null
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
            & $script -Abi x86_64 -HapPath $hap -HdcPath $fakeHdc -Target '127.0.0.1:5557' -ApiLevel 26 -EvidenceRoot (Join-Path $TestDrive 'signer-leaf-evidence') -JavaPath $fakeJava -HapSignToolPath $signTool -SampleCommit '0123456789abcdef0123456789abcdef01234567' -EvidenceRunId 'pester-api26-x86_64' | Out-Null
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
            'host-publish-status-api${{ matrix.api }}-${{ matrix.abi }}',
            '-p:OpenHarmonySampleCommit=${{ github.sha }}',
            '-p:OpenHarmonyEvidenceRunId=${{ github.run_id }}-${{ github.run_attempt }}-${{ matrix.abi }}',
            '-SampleCommit ''${{ github.sha }}''',
            '-EvidenceRunId ''${{ github.run_id }}-${{ github.run_attempt }}-${{ matrix.abi }}''',
            '-PrivateEvidenceRoot $privateEvidenceRoot',
            '(Join-Path $evidenceRoot ''api26-${{ matrix.abi }}-evidence.json'')',
            '(Join-Path $evidenceRoot ''api26-${{ matrix.abi }}-hilog.txt'')')) {
            if ($workflow.IndexOf($token, [StringComparison]::Ordinal) -lt 0) {
                throw "Device workflow is missing failure evidence contract '$token'."
            }
        }
        foreach ($forbiddenPattern in @(
            '\*-signature-verification\.txt',
            '\*-profile-verification\.txt',
            '\*-signer-resolution\.txt',
            'private-device-evidence',
            '(?m)^\s+path:\s+artifacts/device-evidence/\$\{\{ matrix\.abi \}\}\s*$')) {
            if ([regex]::IsMatch($workflow, $forbiddenPattern)) {
                throw "Device workflow uploads sensitive evidence matching '$forbiddenPattern'."
            }
        }
    }

    It 'roots the NativeAOT JSON converters required by WebView IPC' {
        $directives = Get-Content -Raw (Join-Path $PSScriptRoot '..\Src\Entry\rd.xml')

        foreach ($type in @(
            'System.Text.Json.Serialization.Converters.EnumConverter`1[[Microsoft.JSInterop.JSCallResultType,Microsoft.JSInterop]]',
            'System.Text.Json.Serialization.Converters.EnumConverter`1[[Microsoft.JSInterop.Infrastructure.JSCallType,Microsoft.JSInterop]]')) {
            $token = '<Type Name="' + $type + '" Dynamic="Required All" />'
            if ($directives.IndexOf($token, [StringComparison]::Ordinal) -lt 0) {
                throw "NativeAOT directives do not root required WebView IPC converter '$type'."
            }
        }
    }

    It 'routes WebView messages and navigation through their distinct callbacks' {
        $entrySource = Get-Content -Raw (Join-Path $PSScriptRoot '..\Src\Entry\Entry.cs')
        $webviewSource = Get-Content -Raw (Join-Path $PSScriptRoot '..\Src\Entry\BlazorWebview.cs')

        foreach ($token in @(
            'napi_create_reference(env, args[0], 1, &sendMessage);',
            'napi_create_reference(env, args[1], 1, &navigateCore);')) {
            if ($entrySource.IndexOf($token, [StringComparison]::Ordinal) -lt 0) {
                throw "The native bridge is missing callback binding '$token'."
            }
        }
        if ($entrySource.IndexOf(
            'napi_create_reference(env, args[0], 1, &navigateCore);',
            [StringComparison]::Ordinal) -ge 0) {
            throw 'The native bridge still binds navigation to the message callback argument.'
        }
        if (-not [regex]::IsMatch(
            $webviewSource,
            'napi_get_reference_value\(Env, sendMessage, &sendMessageFun\);')) {
            throw 'Blazor WebView messages are not dispatched through the message callback.'
        }
        if (-not [regex]::IsMatch(
            $webviewSource,
            'napi_get_reference_value\(Env, navigateCore, &navigateCoreFun\);')) {
            throw 'Blazor WebView navigation is not dispatched through the navigation callback.'
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
            'ee78787154e1c1a76df4b76b1797d7a09c63937c',
            '44c8423',
            'OpenHarmonySampleCommit',
            'OpenHarmonyEvidenceRunId')) {
            if (-not [regex]::IsMatch($project, $pattern)) { throw "Entry.csproj is missing '$pattern'." }
        }
        $smokeSource = Get-Content -Raw (Join-Path $PSScriptRoot '..\Src\Entry\RuntimeSmoke.cs')
        $smokeContract = Get-Content -Raw (Join-Path $PSScriptRoot '..\Src\Entry\RuntimeSmokeTests.cs')
        foreach ($source in $smokeSource, $smokeContract) {
            foreach ($token in 'sample=', 'run=') {
                if ($source.IndexOf($token, [StringComparison]::Ordinal) -lt 0) {
                    throw "Runtime smoke is missing provenance token '$token'."
                }
            }
        }
        if ([regex]::IsMatch($project, 'PatchOpenHarmonyNativeExports')) {
            throw 'Entry.csproj still patches NativeAOT exports.'
        }
        if (Test-Path (Join-Path $PSScriptRoot '..\Src\Entry\Entry.exports')) {
            throw 'The obsolete NativeAOT TLS exports file still exists.'
        }
    }
}
