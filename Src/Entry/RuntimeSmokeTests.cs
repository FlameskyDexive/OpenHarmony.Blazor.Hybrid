namespace BlazorApp.OpenHarmony;

public static class RuntimeSmokeTests
{
    private static readonly string[] RequiredTokens =
    [
        "status=PASS",
        "runtime=10.",
        "arch=",
        "api=",
        "abi=",
        "sample=",
        "run=",
        "runtimeSource=",
        "runtimePackage=",
        "bindings=",
        "publishAot=",
        "startup=True",
        "gc=True",
        "thread=True",
        "file=True",
        "network=True",
        "icu=True",
        "hilog=True",
        "ipc=True",
        "callback=True"
    ];

    public static bool HasExpectedRuntime(string value) =>
        RequiredTokens.All(token => value.Contains(token, StringComparison.Ordinal)) &&
        !value.Contains("=unknown", StringComparison.Ordinal);
}
