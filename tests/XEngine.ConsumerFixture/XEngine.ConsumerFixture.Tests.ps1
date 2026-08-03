Describe 'XEngine clean consumer fixture' {
    BeforeAll {
        $script:runnerPath = Join-Path $PSScriptRoot 'run-clean-consumer.ps1'
        . $script:runnerPath
    }

    It 'references only immutable released packages and no runtime source project' {
        $projectPath = Join-Path $PSScriptRoot 'XEngine.ConsumerFixture.csproj'
        Test-Path $projectPath -PathType Leaf | Should -BeTrue

        [xml]$project = Get-Content -LiteralPath $projectPath -Raw
        $project.SelectNodes('//ProjectReference').Count | Should -Be 0
        $references = @($project.Project.ItemGroup.PackageReference)
        @($references.Include | Sort-Object) | Should -Be @(
            'OpenHarmony.NET.PublishAotCross',
            'OpenHarmony.NET.Runtime.NativeAot.arm64-v8a',
            'OpenHarmony.NET.Runtime.NativeAot.x86_64'
        )
        @($references | Where-Object Include -like 'OpenHarmony.NET.Runtime.NativeAot.*' | Select-Object -ExpandProperty Version -Unique) | Should -Be @('10.0.10-ohos.2-preview.1')
        @($references | Where-Object Include -eq 'OpenHarmony.NET.PublishAotCross' | Select-Object -ExpandProperty Version -Unique) | Should -Be @('42.42.42-dev')
        $project.Project.PropertyGroup.OpenHarmonyTarget | Should -Contain 'true'
    }

    It 'enforces the package-only contract before restore' {
        $projectPath = Join-Path $PSScriptRoot 'XEngine.ConsumerFixture.csproj'

        { Assert-CleanConsumerProjectContract -ProjectPath $projectPath } | Should -Not -Throw
    }

    It 'publishes API13 and API26 for both supported ABIs' {
        Test-Path $script:runnerPath -PathType Leaf | Should -BeTrue

        $cases = @(Get-CleanConsumerCases)
        $cases.Count | Should -Be 4
        @($cases | ForEach-Object { "$($_.Api)-$($_.Abi)-$($_.Rid)-$($_.ElfMachine)" }) | Should -Be @(
            '13-x86_64-linux-musl-x64-Advanced Micro Devices X86-64',
            '26-x86_64-linux-musl-x64-Advanced Micro Devices X86-64',
            '13-arm64-v8a-linux-musl-arm64-AArch64',
            '26-arm64-v8a-linux-musl-arm64-AArch64'
        )
    }

    It 'discovers exactly the immutable runtime packages from a produced package directory' {
        $packageRoot = Join-Path ([IO.Path]::GetTempPath()) ('xengine-consumer-packages-' + [guid]::NewGuid().ToString('N'))
        $crossPackage = Join-Path $packageRoot 'cross\OpenHarmony.NET.PublishAotCross.42.42.42-dev.nupkg'
        try {
            New-Item -ItemType Directory -Path $packageRoot,(Split-Path $crossPackage) -Force | Out-Null
            @(
                'OpenHarmony.NET.Runtime.NativeAot.x86_64.10.0.10-ohos.2-preview.1.nupkg',
                'OpenHarmony.NET.Runtime.NativeAot.arm64-v8a.10.0.10-ohos.2-preview.1.nupkg'
            ) | ForEach-Object { New-Item -ItemType File -Path (Join-Path $packageRoot $_) -Force | Out-Null }
            New-Item -ItemType File -Path $crossPackage -Force | Out-Null

            $inputs = Resolve-CleanConsumerPackageInputs -RuntimePackageDirectory $packageRoot -PublishAotCrossPackagePath $crossPackage

            @($inputs.RuntimePackages | ForEach-Object { [IO.Path]::GetFileName($_) } | Sort-Object) | Should -Be @(
                'OpenHarmony.NET.Runtime.NativeAot.arm64-v8a.10.0.10-ohos.2-preview.1.nupkg',
                'OpenHarmony.NET.Runtime.NativeAot.x86_64.10.0.10-ohos.2-preview.1.nupkg'
            )
            @($inputs.SourcePackages).Count | Should -Be 3
        }
        finally {
            Remove-Item -LiteralPath $packageRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'rejects a cross compiler package outside the immutable release contract' {
        $packageRoot = Join-Path ([IO.Path]::GetTempPath()) ('xengine-consumer-packages-' + [guid]::NewGuid().ToString('N'))
        $unexpectedCrossPackage = Join-Path $packageRoot 'cross\OpenHarmony.NET.PublishAotCross.42.42.43-dev.nupkg'
        try {
            New-Item -ItemType Directory -Path $packageRoot,(Split-Path $unexpectedCrossPackage) -Force | Out-Null
            @(
                'OpenHarmony.NET.Runtime.NativeAot.x86_64.10.0.10-ohos.2-preview.1.nupkg',
                'OpenHarmony.NET.Runtime.NativeAot.arm64-v8a.10.0.10-ohos.2-preview.1.nupkg'
            ) | ForEach-Object { New-Item -ItemType File -Path (Join-Path $packageRoot $_) -Force | Out-Null }
            New-Item -ItemType File -Path $unexpectedCrossPackage -Force | Out-Null

            {
                Resolve-CleanConsumerPackageInputs -RuntimePackageDirectory $packageRoot -PublishAotCrossPackagePath $unexpectedCrossPackage
            } | Should -Throw '*does not match the immutable release contract*'
        }
        finally {
            Remove-Item -LiteralPath $packageRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'rejects additional packages in the runtime release directory' {
        $packageRoot = Join-Path ([IO.Path]::GetTempPath()) ('xengine-consumer-packages-' + [guid]::NewGuid().ToString('N'))
        $crossPackage = Join-Path $packageRoot 'cross\OpenHarmony.NET.PublishAotCross.42.42.42-dev.nupkg'
        try {
            New-Item -ItemType Directory -Path $packageRoot,(Split-Path $crossPackage) -Force | Out-Null
            @(
                'OpenHarmony.NET.Runtime.NativeAot.x86_64.10.0.10-ohos.2-preview.1.nupkg',
                'OpenHarmony.NET.Runtime.NativeAot.arm64-v8a.10.0.10-ohos.2-preview.1.nupkg',
                'OpenHarmony.NET.Runtime.NativeAot.x86_64.10.0.10-ohos.2-preview.2.nupkg'
            ) | ForEach-Object { New-Item -ItemType File -Path (Join-Path $packageRoot $_) -Force | Out-Null }
            New-Item -ItemType File -Path $crossPackage -Force | Out-Null

            {
                Resolve-CleanConsumerPackageInputs -RuntimePackageDirectory $packageRoot -PublishAotCrossPackagePath $crossPackage
            } | Should -Throw '*exactly two runtime packages*'
        }
        finally {
            Remove-Item -LiteralPath $packageRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'maps OpenHarmony packages only to the staged release feed' {
        [xml]$config = New-CleanConsumerNuGetConfig -FeedRoot 'D:\released-feed'

        @($config.configuration.packageSources.add | ForEach-Object key) | Should -Be @('released-openharmony', 'nuget.org')
        @($config.configuration.packageSourceMapping.packageSource | Where-Object key -eq 'released-openharmony' | ForEach-Object package | ForEach-Object pattern) |
            Should -Be @('OpenHarmony.NET.*')
        @($config.configuration.packageSourceMapping.packageSource | Where-Object key -eq 'nuget.org' | ForEach-Object package | ForEach-Object pattern) |
            Should -Be @('*')
    }

    It 'rejects a package whose content does not match its published SHA-256' {
        $packagePath = Join-Path ([IO.Path]::GetTempPath()) ('xengine-consumer-package-' + [guid]::NewGuid().ToString('N') + '.nupkg')
        try {
            [IO.File]::WriteAllBytes($packagePath, [byte[]](1, 2, 3))

            { Assert-PublishedPackageHash -Path $packagePath -ExpectedSha256 ('0' * 64) } |
                Should -Throw '*published SHA-256*'
        }
        finally {
            Remove-Item -LiteralPath $packagePath -Force -ErrorAction SilentlyContinue
        }
    }

    It 'rejects runtime packages that do not match the release SHA256SUMS' {
        $packageRoot = Join-Path ([IO.Path]::GetTempPath()) ('xengine-consumer-runtime-hashes-' + [guid]::NewGuid().ToString('N'))
        $checksumsPath = Join-Path $packageRoot 'SHA256SUMS'
        $x64Package = Join-Path $packageRoot 'OpenHarmony.NET.Runtime.NativeAot.x86_64.10.0.10-ohos.2-preview.1.nupkg'
        $arm64Package = Join-Path $packageRoot 'OpenHarmony.NET.Runtime.NativeAot.arm64-v8a.10.0.10-ohos.2-preview.1.nupkg'
        try {
            New-Item -ItemType Directory -Path $packageRoot -Force | Out-Null
            [IO.File]::WriteAllBytes($x64Package, [byte[]](1))
            [IO.File]::WriteAllBytes($arm64Package, [byte[]](2))
            Write-Utf8File -Path $checksumsPath -Content @"
$('0' * 64)  $([IO.Path]::GetFileName($x64Package))
$('0' * 64)  $([IO.Path]::GetFileName($arm64Package))
"@

            { Get-PublishedRuntimePackageHashes -PackagePaths @($x64Package, $arm64Package) -ChecksumsPath $checksumsPath } |
                Should -Throw '*published SHA-256*'
        }
        finally {
            Remove-Item -LiteralPath $packageRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'uses the resolved MSBuild OpenHarmony target triple as build evidence' {
        $properties = ConvertFrom-MSBuildProperties -Output @(
            '{',
            '  "Properties": {',
            '    "MSBuildVersion": "18.0.0",',
            '    "OpenHarmonyTargetTriple": "aarch64-linux-ohos"',
            '  }',
            '}'
        )

        $properties.OpenHarmonyTargetTriple | Should -Be 'aarch64-linux-ohos'
    }

    It 'rejects runtime source and local release paths from generated consumer output' {
        $workspaceRoot = 'D:\Engine\OHOS'
        $forbiddenRoots = @(Get-CleanConsumerForbiddenRoots -WorkspaceRoot $workspaceRoot -RuntimePackageDirectory 'D:\released-inputs')
        $forbiddenRoots | Should -Contain 'D:\Engine\OHOS\runtime'
        $forbiddenRoots | Should -Contain 'D:\Engine\OHOS\OpenHarmony.NET.Runtime\releases'
        $forbiddenRoots | Should -Contain 'OpenHarmony.NET.Runtime\releases'

        $artifact = Join-Path ([IO.Path]::GetTempPath()) ('xengine-consumer-leak-' + [guid]::NewGuid().ToString('N') + '.txt')
        try {
            Write-Utf8File -Path $artifact -Content 'source=D:/Engine/OHOS/OpenHarmony.NET.Runtime/releases/10.0.10-ohos.2-preview.1'
            { Assert-NoSourceLeaks -Paths @($artifact) -ForbiddenRoots $forbiddenRoots } | Should -Throw '*forbidden local path*'
        }
        finally {
            Remove-Item -LiteralPath $artifact -Force -ErrorAction SilentlyContinue
        }
    }

    It 'writes normalized UTF-8 JSON evidence' {
        $evidencePath = Join-Path ([IO.Path]::GetTempPath()) ('xengine-consumer-evidence-' + [guid]::NewGuid().ToString('N') + '.json')
        try {
            Write-CleanConsumerEvidence -Path $evidencePath -Evidence ([ordered]@{ schemaVersion = 1; status = 'PASS'; cases = @() })

            $bytes = [IO.File]::ReadAllBytes($evidencePath)
            @($bytes[0..2]) | Should -Not -Be @(239, 187, 191)
            $json = [Text.Encoding]::UTF8.GetString($bytes)
            $json.EndsWith("`n") | Should -BeTrue
            $json | Should -Not -Match "`r`n"
            (Get-Content -LiteralPath $evidencePath -Raw | ConvertFrom-Json).status | Should -Be 'PASS'
        }
        finally {
            Remove-Item -LiteralPath $evidencePath -Force -ErrorAction SilentlyContinue
        }
    }

    It 'parses MSBuild binary logs when checking forbidden paths' {
        $testRoot = Join-Path ([IO.Path]::GetTempPath()) ('xengine-consumer-binlog-' + [guid]::NewGuid().ToString('N'))
        $projectPath = Join-Path $testRoot 'Leak.proj'
        $binlogPath = Join-Path $testRoot 'leak.binlog'
        $forbiddenPath = 'D:\Engine\OHOS\runtime'
        try {
            Write-Utf8File -Path $projectPath -Content @"
<Project>
  <Target Name="LogLeak">
    <Message Importance="High" Text="$forbiddenPath" />
  </Target>
</Project>
"@
            & dotnet msbuild $projectPath -nologo -t:LogLeak "-bl:$binlogPath" | Out-Null
            $LASTEXITCODE | Should -Be 0
            Test-Path $binlogPath -PathType Leaf | Should -BeTrue

            { Assert-NoBinlogSourceLeaks -Paths @($binlogPath) -ForbiddenRoots @($forbiddenPath) } |
                Should -Throw '*forbidden local path*'
        }
        finally {
            Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'requires the publish binary log to contain the resolved OpenHarmony target triple' {
        $testRoot = Join-Path ([IO.Path]::GetTempPath()) ('xengine-consumer-triple-' + [guid]::NewGuid().ToString('N'))
        $projectPath = Join-Path $testRoot 'Triple.proj'
        $binlogPath = Join-Path $testRoot 'triple.binlog'
        $targetTriple = 'aarch64-linux-ohos'
        try {
            Write-Utf8File -Path $projectPath -Content @"
<Project>
  <Target Name="LogTargetTriple">
    <Message Importance="High" Text="--target=$targetTriple" />
  </Target>
</Project>
"@
            & dotnet msbuild $projectPath -nologo -t:LogTargetTriple "-bl:$binlogPath" | Out-Null
            $LASTEXITCODE | Should -Be 0

            { Assert-BinlogContainsText -Paths @($binlogPath) -Text "--target=$targetTriple" } | Should -Not -Throw
            { Assert-BinlogContainsText -Paths @($binlogPath) -Text '--target=x86_64-linux-ohos' } |
                Should -Throw '*required text*'
        }
        finally {
            Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
