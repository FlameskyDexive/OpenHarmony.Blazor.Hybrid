Describe 'arm64 readiness contracts' {
    BeforeAll {
        $readinessScript = Join-Path $PSScriptRoot 'run-arm64-readiness.ps1'
        . $readinessScript
    }

    It 'recognizes the exact OpenHarmony static arm64 thunk layout' {
        $bytes = [byte[]]::new(0x10000)
        $branchInstruction = [Convert]::ToUInt32('d61f0220', 16)
        $breakInstruction = [Convert]::ToUInt32('d43e0000', 16)
        $nopInstruction = [Convert]::ToUInt32('d503201f', 16)
        for ($block = 0; $block -lt 8; $block++) {
            $page = $block * 0x1000
            for ($index = 0; $index -lt 0xff; $index++) {
                $offset = $page + ($index * 0x10)
                $ldrOffset = 0xff8 - ($index * 0x10)
                $ldr = [uint32](0xf9400000L -bor (([uint32]($ldrOffset / 8)) -shl 10) -bor (16 -shl 5) -bor 17)
                [BitConverter]::GetBytes([uint32]0x10040010).CopyTo($bytes, $offset)
                [BitConverter]::GetBytes($ldr).CopyTo($bytes, $offset + 4)
                [BitConverter]::GetBytes($branchInstruction).CopyTo($bytes, $offset + 8)
                [BitConverter]::GetBytes($breakInstruction).CopyTo($bytes, $offset + 12)
            }
            for ($padding = 0xff0; $padding -lt 0x1000; $padding += 4) {
                [BitConverter]::GetBytes($nopInstruction).CopyTo($bytes, $page + $padding)
            }
        }

        $layout = Test-Arm64StaticThunkLayout -Bytes $bytes

        $layout.codePages | Should -Be 8
        $layout.thunksPerPage | Should -Be 255
        $layout.codeSize | Should -Be 0x8000
        $layout.dataSize | Should -Be 0x8000

        $bytes[14] = 0
        { Test-Arm64StaticThunkLayout -Bytes $bytes } | Should -Throw '*static thunk layout*'
    }

    It 'orders API13 and API14 first and excludes API26 from an API24 device run' {
        $plan = @(Get-Arm64DeviceAcceptancePlan `
            -SupportedApis @(13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 26) `
            -AvailableApis @(13, 14, 15, 18, 20, 23) `
            -DeviceApiLevel 24)

        @($plan).Count | Should -Be 12
        @($plan | Select-Object -ExpandProperty buildApi) | Should -Be @(13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24)
        @($plan | Where-Object hardGate | Select-Object -ExpandProperty buildApi) | Should -Be @(13, 14)
        @($plan | Where-Object status -eq 'SKIPPED' | Select-Object -ExpandProperty buildApi) |
            Should -Be @(16, 17, 19, 21, 22, 24)
        @($plan | Where-Object buildApi -eq 26).Count | Should -Be 0
    }

    It 'keeps readiness distinct from physical-device PASS evidence' {
        $source = Get-Content -LiteralPath $readinessScript -Raw

        $source | Should -Match "status\s*=\s*'READY_FOR_DEVICE'"
        $source | Should -Match 'RunDeviceAcceptance'
        $source | Should -Match 'No connected arm64 USB HDC target is available'
        $source | Should -Match 'DeviceApiLevel\s+24'
    }

    It 'does not treat an empty HDC target list as a connected device' {
        $fakeHdc = Join-Path $TestDrive 'empty-hdc.ps1'
        @'
param([Parameter(ValueFromRemainingArguments = $true)][string[]] $Arguments)
if ($Arguments -contains 'list') { '[Empty]'; exit 0 }
throw 'No command may run against an empty target.'
'@ | Set-Content -LiteralPath $fakeHdc -Encoding UTF8

        { Get-ConnectedArm64Api24Target -Executable $fakeHdc -ExpectedApi 24 } |
            Should -Throw '*No connected arm64 USB HDC target is available*'
    }
}

Describe 'physical-device UI acceptance contract' {
    BeforeAll {
        $deviceScript = Join-Path $PSScriptRoot 'run-device-acceptance.ps1'
    }

    It 'requires the Hello and Counter 0-to-1 interaction when requested' {
        $source = Get-Content -LiteralPath $deviceScript -Raw

        $source | Should -Match 'RequireUiInteraction'
        $source | Should -Match "Hello, world!"
        $source | Should -Match 'Current count: 0'
        $source | Should -Match 'Current count: 1'
        $source | Should -Match 'uiAttestation'
    }
}
