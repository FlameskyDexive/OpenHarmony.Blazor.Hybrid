using System.Globalization;
using System.Net.Sockets;
using System.Reflection;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using OpenHarmony.NDK.Bindings.Native;
using OpenHarmony.NDK.Bindings.Native.Generated.IPC;
using OpenHarmony.NDK.Bindings.Native.Manual.IPC;

namespace BlazorApp.OpenHarmony;

public static class RuntimeSmoke
{
    private static int s_destroyCallbackUserData;

    public static unsafe string Run()
    {
        IReadOnlyDictionary<string, string> build = typeof(RuntimeSmoke).Assembly
            .GetCustomAttributes<AssemblyMetadataAttribute>()
            .ToDictionary(attribute => attribute.Key, attribute => attribute.Value ?? string.Empty, StringComparer.Ordinal);

        string temp = Path.Combine(Path.GetTempPath(), "openharmony-dotnet10-smoke.txt");
        File.WriteAllText(temp, "dotnet10");
        string content = File.ReadAllText(temp);
        File.Delete(temp);

        int collections = GC.CollectionCount(0);
        GC.Collect();
        GC.WaitForPendingFinalizers();

        int threadValue = 0;
        using ManualResetEventSlim threadCompleted = new(false);
        Thread thread = new(() =>
        {
            threadValue = 42;
            threadCompleted.Set();
        });
        thread.Start();
        bool threadPassed = threadCompleted.Wait(TimeSpan.FromSeconds(5)) && thread.Join(TimeSpan.FromSeconds(5)) && threadValue == 42;

        using Socket socket = new(AddressFamily.InterNetwork, SocketType.Stream, ProtocolType.Tcp);
        CultureInfo culture = CultureInfo.GetCultureInfo("zh-CN");
        bool icuPassed = culture.CompareInfo.Compare("HarmonyOS", "HarmonyOS", CompareOptions.None) == 0 &&
            new DateTime(2026, 8, 1).ToString("D", culture).Length > 0;

        using IpcParcelHandle parcel = IpcParcelHandle.Create();
        int parcelValue = 0;
        bool ipcPassed = IpcNative.WriteInt32(parcel.DangerousGetParcel(), 42) == 0 &&
            IpcNative.ReadInt32(parcel.DangerousGetParcel(), &parcelValue) == 0 && parcelValue == 42;

        Interlocked.Exchange(ref s_destroyCallbackUserData, 0);
        using IpcCallbackLifetime callbackLifetime = new(IpcRequestCallback, IpcDestroyCallback);
        ReadOnlySpan<byte> descriptor = "OpenHarmony.NET.RuntimeSmoke\0"u8;
        bool callbackPassed;
        fixed (byte* descriptorBytes = descriptor)
        {
            var requestCallback = (delegate* unmanaged[Cdecl]<uint, OHIPCParcel*, OHIPCParcel*, void*, int>)(void*)callbackLifetime.RequestFunction;
            var destroyCallback = (delegate* unmanaged[Cdecl]<void*, void>)(void*)callbackLifetime.DestroyFunction;
            OHIPCRemoteStub* stub = IpcNative.CreateRemoteStub((sbyte*)descriptorBytes, requestCallback, destroyCallback, (void*)42);
            callbackPassed = stub is not null;
            if (stub is not null)
            {
                IpcNative.DestroyRemoteStub(stub);
                callbackPassed = Volatile.Read(ref s_destroyCallbackUserData) == 42;
            }
        }

        string result = string.Join(';',
            "status=PASS",
            $"runtime={Environment.Version}",
            $"arch={RuntimeInformation.ProcessArchitecture}",
            $"api={build.GetValueOrDefault("OpenHarmonyApiLevel", "unknown")}",
            $"abi={build.GetValueOrDefault("OpenHarmonyAbi", "unknown")}",
            $"runtimeSource={build.GetValueOrDefault("OpenHarmonyRuntimeSourceCommit", "unknown")}",
            $"runtimePackage={build.GetValueOrDefault("OpenHarmonyRuntimePackageCommit", "unknown")}",
            $"bindings={build.GetValueOrDefault("OpenHarmonyBindingsCommit", "unknown")}",
            $"publishAot={build.GetValueOrDefault("PublishAotCrossCommit", "unknown")}",
            $"startup={Environment.Version.Major == 10}",
            $"gc={GC.CollectionCount(0) > collections}",
            $"thread={threadPassed}",
            $"file={content == "dotnet10"}",
            $"network={socket.AddressFamily == AddressFamily.InterNetwork}",
            $"icu={icuPassed}",
            $"hilog=True",
            $"ipc={ipcPassed}",
            $"callback={callbackPassed}");
        Hilog.OH_LOG_INFO(LogType.LOG_APP, "Dotnet10Smoke", result);
        return result;
    }

    private static unsafe int IpcRequestCallback(uint code, OHIPCParcel* data, OHIPCParcel* reply, nint userData) => 0;

    private static void IpcDestroyCallback(nint userData)
    {
        Interlocked.Exchange(ref s_destroyCallbackUserData, checked((int)userData));
    }
}
