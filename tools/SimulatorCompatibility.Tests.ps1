BeforeAll {
    . (Join-Path $PSScriptRoot 'run-simulator-compatibility.ps1')
    $matrix = Get-Content (Join-Path $PSScriptRoot 'openharmony-api-matrix.json') -Raw | ConvertFrom-Json
}

Describe 'OpenHarmony simulator compatibility matrix' {
    It 'selects only lower-triangular API13-24 and API26 pairs' {
        $pairs = @(Get-CompatibilityPairs)

        $pairs.Count | Should -Be 91
        @($pairs | Where-Object { $_.BuildApi -eq 13 -and $_.DeviceApi -eq 26 }).Count | Should -Be 1
        @($pairs | Where-Object { $_.BuildApi -eq 26 -and $_.DeviceApi -eq 13 }).Count | Should -Be 0
        @($pairs | Where-Object { $_.BuildApi -eq 25 -or $_.DeviceApi -eq 25 }).Count | Should -Be 0
    }

    It 'keeps unavailable Native SDK rows explicit instead of fabricating HAPs' {
        $pairs = @(Get-CompatibilityPairs)
        $unavailable = @($matrix.entries | Where-Object { -not $_.nativeSdkAvailable } | ForEach-Object { [int]$_.api })
        $skipped = @($pairs | Where-Object { $unavailable -contains $_.BuildApi })

        $unavailable | Should -Be @(16, 17, 19, 21, 22, 24)
        $skipped.Count | Should -Be 37
        ($pairs.Count - $skipped.Count) | Should -Be 54
    }

    It 'includes installed emulator-only APIs as device targets' {
        $pairs = @(Get-CompatibilityPairs)
        @($pairs.DeviceApi | Sort-Object -Unique) | Should -Be @(13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 26)
        @($pairs | Where-Object { $_.BuildApi -eq 13 -and $_.DeviceApi -in @(16, 17, 19, 21, 22, 24) }).Count | Should -Be 6
    }

    It 'retains the instance identity inputs required by current emulators' {
        $root = Join-Path $TestDrive 'emulators'
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        @(
            [ordered]@{
                name = 'API26 Phone'
                apiVersion = '26.0.0'
                abi = 'x86'
                imageDir = 'system-image/HarmonyOS-7.0.0-B2/phone_all_x86/'
                uuid = '11111111-2222-3333-4444-555555555555'
                'harmonyos.config.path' = 'C:/Users/test/AppData/Roaming/Huawei/DevEcoStudio26.0'
            }
        ) | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $root 'lists.json')

        $definition = @(Get-EmulatorDefinitions -Root $root)
        $definition.Count | Should -Be 1
        $definition[0].Uuid | Should -Be '11111111-2222-3333-4444-555555555555'
        $definition[0].ConfigPath | Should -Be 'C:/Users/test/AppData/Roaming/Huawei/DevEcoStudio26.0'
        (Get-Command New-EmulatorInstanceIdentity -ErrorAction Stop).CommandType | Should -Be 'Function'
        (Test-Path (Join-Path $PSScriptRoot 'EmulatorInstanceIdentity.java') -PathType Leaf) | Should -BeTrue
    }
}
