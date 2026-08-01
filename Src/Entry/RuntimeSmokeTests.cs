namespace BlazorApp.OpenHarmony;

public static class RuntimeSmokeTests
{
    public static bool HasExpectedRuntime(string value) =>
        value.Contains("runtime=", StringComparison.Ordinal) &&
        value.Contains("arch=", StringComparison.Ordinal) &&
        value.Contains("file=True", StringComparison.Ordinal);
}
