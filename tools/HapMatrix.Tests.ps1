BeforeAll {
    $matrixPath = Join-Path $PSScriptRoot 'openharmony-api-matrix.json'
    $matrix = Get-Content -LiteralPath $matrixPath -Raw | ConvertFrom-Json
}

Describe 'OpenHarmony HAP API matrix' {
    It 'contains API13 through API24 and API26, but never API25' {
        @($matrix.supportedApis) | Should -Be @(13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 26)
        @($matrix.supportedApis) | Should -Not -Contain 25
    }

    It 'records complete, unique API product metadata' {
        @($matrix.entries).Count | Should -Be 13
        @($matrix.entries.api | Sort-Object -Unique) | Should -Be @($matrix.supportedApis)
        foreach ($entry in $matrix.entries) {
            $entry.sdkFolder | Should -Not -BeNullOrEmpty
            $entry.compatibleSdkVersion | Should -Not -BeNullOrEmpty
            $entry.product | Should -Be "api$($entry.api)"
        }
        ($matrix.entries | Where-Object api -eq 26).compatibleSdkVersion | Should -Be '26.0.0'
    }

    It 'marks only installed Native SDK APIs as buildable' {
        @($matrix.entries | Where-Object nativeSdkAvailable | ForEach-Object api) |
            Should -Be @(13, 14, 15, 18, 20, 23, 26)
        @($matrix.entries | Where-Object { -not $_.nativeSdkAvailable } | ForEach-Object api) |
            Should -Be @(16, 17, 19, 21, 22, 24)
    }
}
