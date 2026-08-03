Describe 'OpenHarmony release evidence contract' {
    BeforeAll {
        $verifier = Join-Path $PSScriptRoot 'verify-release-evidence.ps1'
        $writer = Join-Path $PSScriptRoot 'write-release-evidence.ps1'
        . $verifier
    }

    It 'rejects unknown dirty and abbreviated commit identities' {
        foreach ($value in 'unknown', 'dirty', '44c8423', '0123456789ABCDEF0123456789ABCDEF01234567') {
            { Assert-ReleaseCommit -Value $value -Name 'fixture' } | Should -Throw
        }
        { Assert-ReleaseCommit -Value '0123456789abcdef0123456789abcdef01234567' -Name 'fixture' } |
            Should -Not -Throw
    }

    It 'requires a fully linked successful compatibility record' {
        $record = [pscustomobject][ordered]@{
            testResult = 'PASS'
            buildApi = 13
            runtimeBaselineApi = 13
            deviceApi = 26
            abi = 'x86_64'
            hapSha256 = ('a' * 64)
            runtimeManifestSha256 = ('b' * 64)
            runtimeSourceCommit = '0123456789abcdef0123456789abcdef01234567'
            bindingsCommit = '1123456789abcdef0123456789abcdef01234567'
            publishAotCrossCommit = '2123456789abcdef0123456789abcdef01234567'
            runtimePackageCommit = '3123456789abcdef0123456789abcdef01234567'
            sampleCommit = '4123456789abcdef0123456789abcdef01234567'
        }

        { Assert-ReleaseEvidenceRecord -Record $record -Context 'fixture' } | Should -Not -Throw
        $record.hapSha256 = $null
        { Assert-ReleaseEvidenceRecord -Record $record -Context 'fixture' } | Should -Throw '*hapSha256*'
    }

    It 'allows unavailable build rows only as explicit non-fabricated skips' {
        $record = [pscustomobject][ordered]@{
            testResult = 'SKIPPED'
            buildApi = 16
            runtimeBaselineApi = 13
            deviceApi = 18
            abi = 'x86_64'
            hapSha256 = $null
            runtimeManifestSha256 = ('b' * 64)
            runtimeSourceCommit = '0123456789abcdef0123456789abcdef01234567'
            bindingsCommit = '1123456789abcdef0123456789abcdef01234567'
            publishAotCrossCommit = '2123456789abcdef0123456789abcdef01234567'
            runtimePackageCommit = '3123456789abcdef0123456789abcdef01234567'
            sampleCommit = '4123456789abcdef0123456789abcdef01234567'
            reason = 'No independent installable Native SDK/HAP exists.'
        }

        { Assert-ReleaseEvidenceRecord -Record $record -Context 'fixture' } | Should -Not -Throw
        $record.reason = ''
        { Assert-ReleaseEvidenceRecord -Record $record -Context 'fixture' } | Should -Throw '*reason*'
    }

    It 'defines one canonical aggregate writer with all required inputs' {
        $source = Get-Content -LiteralPath $writer -Raw

        foreach ($token in @(
            'compatibility-summary.json',
            'arm64-readiness.json',
            'clean-consumer-evidence.json',
            'runtimeSource',
            'bindings',
            'publishAotCross',
            'runtimePackage',
            'sample',
            'runtimeManifestSha256',
            'READY_WITH_DEVICE_DEFERRED')) {
            $source | Should -Match ([regex]::Escape($token))
        }
    }
}
