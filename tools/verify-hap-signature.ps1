[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string] $HapPath,

    [Parameter(Mandatory = $true)]
    [string] $HapSignToolPath,

    [string] $JavaPath = 'java',

    [Parameter(Mandatory = $true)]
    [string] $OutputDirectory,

    [string] $ArtifactPrefix = 'hap'
)

$ErrorActionPreference = 'Stop'

function Get-Sha256Hex {
    param([Parameter(Mandatory = $true)][byte[]] $Bytes)

    $sha256 = [Security.Cryptography.SHA256]::Create()
    try {
        return (($sha256.ComputeHash($Bytes) | ForEach-Object { $_.ToString('x2') }) -join '')
    }
    finally {
        $sha256.Dispose()
    }
}

function Get-Certificates {
    param([Parameter(Mandatory = $true)][string] $Path)

    $bytes = [IO.File]::ReadAllBytes($Path)
    $text = [Text.Encoding]::ASCII.GetString($bytes)
    $pemMatches = [regex]::Matches(
        $text,
        '-----BEGIN CERTIFICATE-----\s*(?<body>[A-Za-z0-9+/=\s]+?)\s*-----END CERTIFICATE-----',
        [Text.RegularExpressions.RegexOptions]::Singleline)
    $certificates = [Collections.Generic.List[Security.Cryptography.X509Certificates.X509Certificate2]]::new()
    try {
        if ($pemMatches.Count -gt 0) {
            foreach ($match in $pemMatches) {
                $der = [Convert]::FromBase64String(($match.Groups['body'].Value -replace '\s', ''))
                $certificates.Add([Security.Cryptography.X509Certificates.X509Certificate2]::new($der))
            }
        }
        else {
            $collection = [Security.Cryptography.X509Certificates.X509Certificate2Collection]::new()
            $collection.Import($bytes)
            foreach ($certificate in $collection) { $certificates.Add($certificate) }
        }
    }
    catch {
        throw "HAP signature certificate chain is invalid: $($_.Exception.Message)"
    }
    if ($certificates.Count -eq 0) { throw 'HAP signature certificate chain is invalid: no certificates were found.' }
    return @($certificates)
}

if (-not (Test-Path -LiteralPath $HapPath -PathType Leaf)) { throw "HAP was not found: $HapPath" }
if (-not (Test-Path -LiteralPath $HapSignToolPath -PathType Leaf)) { throw "HAP signing tool was not found: $HapSignToolPath" }
if ([string]::IsNullOrWhiteSpace($ArtifactPrefix) -or $ArtifactPrefix.IndexOfAny([IO.Path]::GetInvalidFileNameChars()) -ge 0) {
    throw "Invalid signature evidence prefix: $ArtifactPrefix"
}

New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$outputRoot = (Resolve-Path -LiteralPath $OutputDirectory).Path
$certificatePath = Join-Path $outputRoot "$ArtifactPrefix-certificate-chain.cer"
$profilePath = Join-Path $outputRoot "$ArtifactPrefix-signing-profile.p7b"
$profileVerificationPath = Join-Path $outputRoot "$ArtifactPrefix-profile-verification.json"
$profileVerificationLogPath = Join-Path $outputRoot "$ArtifactPrefix-profile-verification.txt"
$profileCertificatePath = Join-Path $outputRoot "$ArtifactPrefix-profile-certificate.cer"
$signerCertificatePath = Join-Path $outputRoot "$ArtifactPrefix-signer-certificate.cer"
$profilePublicKeyPath = Join-Path $outputRoot "$ArtifactPrefix-profile-public-key.spki"
$signerPublicKeyPath = Join-Path $outputRoot "$ArtifactPrefix-signer-public-key.spki"
$signerResolutionLogPath = Join-Path $outputRoot "$ArtifactPrefix-signer-resolution.txt"
$logPath = Join-Path $outputRoot "$ArtifactPrefix-signature-verification.txt"
Remove-Item -LiteralPath $certificatePath, $profilePath, $profileVerificationPath, $profileVerificationLogPath, $profileCertificatePath, $signerCertificatePath, $profilePublicKeyPath, $signerPublicKeyPath, $signerResolutionLogPath, $logPath -Force -ErrorAction SilentlyContinue

$arguments = @(
    '-jar',
    (Resolve-Path -LiteralPath $HapSignToolPath).Path,
    'verify-app',
    '-inFile',
    (Resolve-Path -LiteralPath $HapPath).Path,
    '-outCertChain',
    $certificatePath,
    '-outProfile',
    $profilePath
)
$previousErrorActionPreference = $ErrorActionPreference
try {
    $ErrorActionPreference = 'Continue'
    $output = @(& $JavaPath @arguments 2>&1)
    $exitCode = $LASTEXITCODE
}
finally {
    $ErrorActionPreference = $previousErrorActionPreference
}
$log = ($output | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine
[IO.File]::WriteAllText($logPath, $log, [Text.UTF8Encoding]::new($false))

if ($exitCode -ne 0) {
    throw "HAP signature verification failed with exit code $exitCode; raw output was retained in '$ArtifactPrefix-signature-verification.txt'."
}
foreach ($path in $certificatePath, $profilePath) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or (Get-Item -LiteralPath $path).Length -eq 0) {
        throw "HAP signature verification did not produce '$path'."
    }
}

$certificates = @(Get-Certificates -Path $certificatePath)

$profileArguments = @(
    '-jar',
    (Resolve-Path -LiteralPath $HapSignToolPath).Path,
    'verify-profile',
    '-inFile',
    $profilePath,
    '-outFile',
    $profileVerificationPath
)
try {
    $ErrorActionPreference = 'Continue'
    $profileOutput = @(& $JavaPath @profileArguments 2>&1)
    $profileExitCode = $LASTEXITCODE
}
finally {
    $ErrorActionPreference = $previousErrorActionPreference
}
$profileLog = ($profileOutput | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine
[IO.File]::WriteAllText($profileVerificationLogPath, $profileLog, [Text.UTF8Encoding]::new($false))
if ($profileExitCode -ne 0) {
    throw "HAP signing profile verification failed with exit code $profileExitCode; raw output was retained in '$ArtifactPrefix-profile-verification.txt'."
}
if (-not (Test-Path -LiteralPath $profileVerificationPath -PathType Leaf)) {
    throw 'HAP signing profile verification failed: no verification result was produced.'
}
try {
    $profile = Get-Content -LiteralPath $profileVerificationPath -Raw | ConvertFrom-Json
}
catch {
    throw 'HAP signing profile verification failed: the verification result is not valid JSON.'
}
if ($profile.verifiedPassed -isnot [bool] -or -not $profile.verifiedPassed -or
    -not [string]::Equals([string]$profile.message, 'OK', [StringComparison]::Ordinal)) {
    throw 'HAP signing profile verification failed: the verification result was not an exact PASS.'
}
if (-not [string]::Equals([string]$profile.content.type, 'debug', [StringComparison]::Ordinal) -or
    -not [string]::Equals([string]$profile.content.'bundle-info'.'bundle-name', 'com.example.blazorapp', [StringComparison]::Ordinal)) {
    throw 'HAP signing profile verification failed: the profile does not authorize the expected debug bundle.'
}
$developmentCertificateObject = $null
try {
    $developmentCertificate = $profile.content.'bundle-info'.'development-certificate'
    $developmentDer = [Convert]::FromBase64String(
        ($developmentCertificate -replace '-----BEGIN CERTIFICATE-----', '' -replace '-----END CERTIFICATE-----', '' -replace '\s', ''))
    $developmentCertificateObject = [Security.Cryptography.X509Certificates.X509Certificate2]::new($developmentDer)
    [IO.File]::WriteAllBytes($profileCertificatePath, $developmentCertificateObject.RawData)
    $profileCertificateSha256 = Get-Sha256Hex -Bytes $developmentCertificateObject.RawData
}
catch {
    throw "HAP signing profile verification failed: the development certificate is invalid: $($_.Exception.Message)"
}
finally {
    if ($developmentCertificateObject) { $developmentCertificateObject.Dispose() }
}

$signerResolverPath = Join-Path $PSScriptRoot 'ExtractHapSignerCertificate.java'
$signerArguments = @(
    '-cp',
    (Resolve-Path -LiteralPath $HapSignToolPath).Path,
    $signerResolverPath,
    (Resolve-Path -LiteralPath $HapPath).Path,
    $profileCertificatePath,
    $signerCertificatePath,
    $profilePublicKeyPath,
    $signerPublicKeyPath
)
try {
    $ErrorActionPreference = 'Continue'
    $signerOutput = @(& $JavaPath @signerArguments 2>&1)
    $signerExitCode = $LASTEXITCODE
}
finally {
    $ErrorActionPreference = $previousErrorActionPreference
}
$signerLog = ($signerOutput | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine
[IO.File]::WriteAllText($signerResolutionLogPath, $signerLog, [Text.UTF8Encoding]::new($false))
if ($signerExitCode -ne 0) {
    throw "HAP signer certificate resolution failed with exit code $signerExitCode; raw output was retained in '$ArtifactPrefix-signer-resolution.txt'."
}
foreach ($path in $signerCertificatePath, $profilePublicKeyPath, $signerPublicKeyPath) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or (Get-Item -LiteralPath $path).Length -eq 0) {
        throw "HAP signer certificate resolution did not produce '$path'."
    }
}

$signerCertificateObject = $null
try {
    $signerCertificateObject = [Security.Cryptography.X509Certificates.X509Certificate2]::new(
        [IO.File]::ReadAllBytes($signerCertificatePath))
    $signerCertificateSha256 = Get-Sha256Hex -Bytes $signerCertificateObject.RawData
}
catch {
    throw "HAP signer certificate is invalid: $($_.Exception.Message)"
}
finally {
    if ($signerCertificateObject) { $signerCertificateObject.Dispose() }
}
if (-not ($certificates | Where-Object { (Get-Sha256Hex -Bytes $_.RawData) -eq $signerCertificateSha256 })) {
    throw 'HAP signer certificate was not found in the verified certificate chain.'
}
$profilePublicKeySha256 = (Get-FileHash -LiteralPath $profilePublicKeyPath -Algorithm SHA256).Hash.ToLowerInvariant()
$signerPublicKeySha256 = (Get-FileHash -LiteralPath $signerPublicKeyPath -Algorithm SHA256).Hash.ToLowerInvariant()
if ($profilePublicKeySha256 -cne $signerPublicKeySha256) {
    throw 'HAP signing profile development certificate public key does not match the actual HAP signer certificate public key.'
}

[pscustomobject]@{
    SignatureVerified = $true
    CertificateChainPath = $certificatePath
    CertificateChainSha256 = (Get-FileHash -LiteralPath $certificatePath -Algorithm SHA256).Hash.ToLowerInvariant()
    ProfileCertificatePath = $profileCertificatePath
    ProfileCertificateSha256 = $profileCertificateSha256
    SignerCertificatePath = $signerCertificatePath
    SignerCertificateSha256 = $signerCertificateSha256
    ProfilePublicKeyPath = $profilePublicKeyPath
    ProfilePublicKeySha256 = $profilePublicKeySha256
    SignerPublicKeyPath = $signerPublicKeyPath
    SignerPublicKeySha256 = $signerPublicKeySha256
    SignerResolutionLogPath = $signerResolutionLogPath
    SignerResolutionLogSha256 = (Get-FileHash -LiteralPath $signerResolutionLogPath -Algorithm SHA256).Hash.ToLowerInvariant()
    SignerResolverSha256 = (Get-FileHash -LiteralPath $signerResolverPath -Algorithm SHA256).Hash.ToLowerInvariant()
    SigningProfilePath = $profilePath
    SigningProfileSha256 = (Get-FileHash -LiteralPath $profilePath -Algorithm SHA256).Hash.ToLowerInvariant()
    ProfileVerificationPath = $profileVerificationPath
    ProfileVerificationSha256 = (Get-FileHash -LiteralPath $profileVerificationPath -Algorithm SHA256).Hash.ToLowerInvariant()
    ProfileVerificationLogPath = $profileVerificationLogPath
    ProfileVerificationLogSha256 = (Get-FileHash -LiteralPath $profileVerificationLogPath -Algorithm SHA256).Hash.ToLowerInvariant()
    VerificationLogPath = $logPath
    VerificationLogSha256 = (Get-FileHash -LiteralPath $logPath -Algorithm SHA256).Hash.ToLowerInvariant()
    VerifierSha256 = (Get-FileHash -LiteralPath $HapSignToolPath -Algorithm SHA256).Hash.ToLowerInvariant()
}
