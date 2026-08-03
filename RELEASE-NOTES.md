# OpenHarmony .NET 10 API13-26 Compatibility Preview

Version: `10.0.10-ohos.2-preview.1`

This preview uses API13 as the NativeAOT runtime baseline for build APIs 13-24
and 26 on `arm64-v8a` and `x86_64`. API25 is unsupported because neither an
installable Native SDK nor a system image is available.

## Verified State

- Installed Native SDK APIs 13, 14, 15, 18, 20, 23, and 26 build for both ABIs.
- APIs 16, 17, 19, 21, 22, and 24 are explicit build-time skips; their installed
  x86_64 emulator images remain covered as run targets.
- The x86_64 lower-triangular matrix contains 91 records: 54 executed passes and
  37 explicit unavailable-HAP skips. API26 runs every buildable target HAP.
- The clean NuGet consumer publishes API13 and API26 for both ABIs without a
  runtime source or developer-local release path.
- Seven arm64 HAPs pass hash, signature, ELF, NUMA-import, provenance, and static
  thunk-layout readiness checks.

## Deferred Hardware Gate

No API24 arm64 HDC target was connected for this evidence snapshot. The release
state is `READY_WITH_DEVICE_DEFERRED`, not `PASS`. Preview/RC publication remains
blocked until API13 and API14 pass first on an API24 arm64 device, followed by
the remaining buildable APIs through API24. Missing Native SDK rows remain
`SKIPPED`; API26 is not installed on the lower API24 target.
