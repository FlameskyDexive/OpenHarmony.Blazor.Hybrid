using System.Net.Http;
using System.Runtime.InteropServices;
using OpenHarmony.NDK.Bindings.Native;

namespace BlazorApp.OpenHarmony;

public static class RuntimeSmoke
{
    public static string Run()
    {
        string temp = Path.Combine(Path.GetTempPath(), "openharmony-dotnet10-smoke.txt");
        File.WriteAllText(temp, "dotnet10");
        string content = File.ReadAllText(temp);
        File.Delete(temp);
        GC.Collect();
        GC.WaitForPendingFinalizers();
        using HttpClient client = new();
        string result = $"runtime={Environment.Version};arch={RuntimeInformation.ProcessArchitecture};file={(content == "dotnet10")};network={client.Timeout.TotalSeconds}";
        Hilog.OH_LOG_INFO(LogType.LOG_APP, "Dotnet10Smoke", result);
        return result;
    }
}
