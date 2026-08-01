# .NET 10 OpenHarmony Blazor Hybrid

样例使用 .NET 10 NativeAOT，默认 HarmonyOS API15，保留 API18/20/23/26 的构建覆盖；真机使用 `linux-musl-arm64`，模拟器使用 `linux-musl-x64`。

仓库提供 `PublishApi15`、`PublishApi18`、`PublishApi20`、`PublishApi23`、`PublishApi26` 五个 API profile；默认 ABI 为 arm64-v8a，模拟器可将 `OpenHarmonyAbi` 设为 `x86_64`。也可以直接覆盖 API 属性，runtime.targets 会优先选择对应 split 包并回退到 API15 基线：

```powershell
dotnet publish Src/Entry/Entry.csproj -p:OpenHarmonyTarget=true -p:OpenHarmonyApiLevel=26 `
  -p:RuntimeIdentifier=linux-musl-arm64 -p:PublishProfile=PublishArm64
```

例如使用 API26 profile 构建 x86_64 模拟器：

```powershell
dotnet publish Src/Entry/Entry.csproj -p:PublishProfile=PublishApi26 -p:OpenHarmonyAbi=x86_64
```

发布结果会复制到 HAP 的 `resfile/wwwroot/{arm64-v8a,x86_64}`。HAP 的 compatible SDK 最低设为 API15，两个 ABI 已保留在 `OHOS_Project/entry/build-profile.json5`。

设备安装、启动、HDC 日志和网络/IPC/回调 smoke 需要连接 API26 真机或 x86_64 模拟器后执行；API26 x86_64 模拟器的签名 HAP 验收已通过，公开证据见 [schema v3 attestation](docs/device-evidence/api26-x86_64/api26-x86_64-evidence.json) 和 [normalized smoke record](docs/device-evidence/api26-x86_64/api26-x86_64-hilog.txt)。当前工作站仍未连接 API26 arm64 真机。

CI 会对 API15/18/20/23/26 与 arm64-v8a/x86_64 的十种组合执行
NativeAOT 发布。手动触发设备验收时，专用 runner 会构建签名 HAP，分别在
API26 arm64 真机和 x86_64 模拟器上验证启动、GC、线程、文件、网络栈、ICU、
HiLog、IPC parcel 与回调往返，并上传带依赖提交 SHA-256 的验收证据。
设备 runner 的 `DEVECO_SDK_HOME` 必须指向 DevEco SDK 父目录（例如
`C:\Program Files\Huawei\DevEco Studio\sdk`），该目录下应存在
`default\sdk-pkg.json`、`default\openharmony` 和 `default\hms`；不要指向
`...\sdk\default` 或 OpenHarmony SDK 目录。设备 runner 还需要 HDC、Hvigor，并通过仓库 secret
`HARMONYOS_SIGNING_CONFIG_JSON` 提供 `default` 签名配置；证书、profile 和密钥库
路径必须在两个专用 runner 上可访问。设备安装前，验收脚本会使用 SDK 自带的
`hap-sign-tool.jar verify-app` 独立验证 HAP 签名，解析导出的 X.509 证书，重新验证
签名 profile，并通过 CMS SignerId 定位实际 HAP signer 证书；profile 授权证书与该 signer 的
SubjectPublicKeyInfo 身份必须一致。schema v3 证据会绑定 sample source commit、run ID、验收 producer、签名 policy、HDC、Java、HAP 私有快照、profile 授权证书、CMS signer
证书、双方 SPKI、证书链、签名 profile、验签与 signer 解析日志、解析器和 verifier 的 SHA-256；
验签失败时不会调用 HDC。设备脚本会先验证已安装 bundle 清单；旧 bundle 存在时必须成功卸载，不存在时记录 `already-absent`，并要求 `hdc install`、HiLog reset 和 `aa start` 输出明确且不矛盾的成功语义，只接受来自新启动 bundle 唯一 PID、source commit 与当前 run ID 都匹配的 `Dotnet10Smoke`。
CI artifact 仅发布哈希证据 JSON、规范化的 smoke 状态记录和不含异常原文的 workflow 阶段状态；原始 HAP、profile、证书、验签/HDC/系统 HiLog、PID 和 HDC target 标识只在 runner temp 的受控私有证据目录中留存，不会上传或提交。
