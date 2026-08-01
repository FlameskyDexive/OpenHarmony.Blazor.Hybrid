[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string] $SigningConfigJson,

    [string] $BuildProfilePath = 'OHOS_Project/build-profile.json5'
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($SigningConfigJson)) {
    throw 'HARMONYOS_SIGNING_CONFIG_JSON must contain one HarmonyOS signing configuration.'
}
if (-not (Test-Path -LiteralPath $BuildProfilePath -PathType Leaf)) {
    throw "HarmonyOS build profile was not found: $BuildProfilePath"
}

try {
    $signing = $SigningConfigJson | ConvertFrom-Json
}
catch {
    throw 'HARMONYOS_SIGNING_CONFIG_JSON is not valid JSON.'
}

foreach ($property in 'name', 'type', 'material') {
    if ($null -eq $signing.$property -or [string]::IsNullOrWhiteSpace([string]$signing.$property)) {
        throw "Signing configuration is missing '$property'."
    }
}
if ($signing.name -ne 'default') {
    throw "Signing configuration name must be 'default'."
}
foreach ($property in 'certpath', 'storePassword', 'keyAlias', 'keyPassword', 'profile', 'signAlg', 'storeFile') {
    if ($null -eq $signing.material.$property -or [string]::IsNullOrWhiteSpace([string]$signing.material.$property)) {
        throw "Signing material is missing '$property'."
    }
}
foreach ($property in 'certpath', 'profile', 'storeFile') {
    if (-not (Test-Path -LiteralPath $signing.material.$property -PathType Leaf)) {
        throw "Signing material file '$property' was not found."
    }
}

$profile = Get-Content -LiteralPath $BuildProfilePath -Raw | ConvertFrom-Json
$profile.app.signingConfigs = @($signing)
foreach ($product in $profile.app.products) {
    $product.signingConfig = 'default'
}
[IO.File]::WriteAllText(
    (Resolve-Path -LiteralPath $BuildProfilePath).Path,
    (($profile | ConvertTo-Json -Depth 20) + "`n"),
    [Text.UTF8Encoding]::new($false))

Write-Output "Configured HarmonyOS signing profile 'default'."
