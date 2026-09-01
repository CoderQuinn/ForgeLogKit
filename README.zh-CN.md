# ForgeLogKit

<p align="center">
  <a href="README.md">English</a> |
  <strong>简体中文</strong>
</p>

[![CI / Tests](https://github.com/CoderQuinn/ForgeLogKit/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/CoderQuinn/ForgeLogKit/actions/workflows/ci.yml)
[![License](https://img.shields.io/github/license/CoderQuinn/ForgeLogKit)](LICENSE)

ForgeLogKit 是构建于 `os_log` 之上的轻量级日志基础设施，面向 **Swift、Objective-C 和纯 C** 代码。

它适合网络栈、VPN / Network Extension 以及混合语言工程等底层组件。

---

## 安装（Swift Package Manager）

添加 package：

```swift
dependencies: [
  .package(url: "https://github.com/CoderQuinn/ForgeLogKit.git", .upToNextMinor(from: "0.2.0")),
],
```

## 组件

ForgeLogKit 分为三层：

- **ForgeLogKitC**
  - 对 `os_log` 的纯 C 封装
  - 安全处理动态 `printf` 风格格式字符串
  - 明确的 public/private 隐私控制
  - 适用于 lwIP、C 代码和性能敏感路径

- **ForgeLogKitOC**
  - 基于 C 层的 Objective-C 适配器
  - 为 Objective-C 工程提供便捷 API

- **ForgeLogKit**
  - 对 `os_log` 的 Swift 封装
  - 统一的日志级别和隐私 API
  - 并发安全配置以及符合 `Sendable` 的 logger 值
  - 保持源码兼容的 `StaticString` 和 `String` 便捷 API

---

## 设计说明

- 所有日志最终统一通过 **`os_log`** 输出
- 动态格式字符串通过缓冲区安全处理
- Swift、C 与 Objective-C 共享稳定的结构化字段序列化
- Swift、C 与 Objective-C 消息在输出前共享同一轮内容脱敏
- 新的统一日志接口默认将消息数据标记为 private
- 不依赖应用层上下文或业务逻辑
- 适用于 Network Extension（VPN）环境
- 有意不提供文件日志、异步流水线和后端抽象

---

## Swift 使用方式

```swift
let log = FLLog(category: "network")
let path = "/Users/example/Documents"

log.info("connected")
log.debug("state updated")
log.error("connection failed")
log.fault("unrecoverable state")
// StaticString 和 String 便捷重载仍然可用。

// 统一接口会延迟求值消息，并默认使用 private 数据。
log.log(.info, "selected path: \(path)")
log.log(.error, "cleanup failed", privacy: .public)

// 也可以使用支持隐私参数的便捷重载。
log.info("user-selected path: \(path)", privacy: .private)

let fields = FLLogFields(
  component: "packet-tunnel",
  phase: "connect",
  errorCode: "TCP_TIMEOUT",
  correlationID: "flow-42"
)!
log.log(.error, "connection failed", fields: fields)
```

为保持兼容，原有的 `info(_:)`、`debug(_:)`、`warn(_:)` 和 `error(_:)` 便捷方法继续沿用 0.2 版本公开消息数据的行为，但内容在输出前仍会脱敏。若脱敏后的整条消息也应通过 Unified Logging 的 private 路由，请使用 `log(_:_:privacy:)` 或显式指定隐私级别的重载。

## 结构化字段

Swift、C 与 Objective-C 的结构化事件使用相同的固定字段名与顺序：

```text
[network] [ERROR] [component=packet-tunnel][phase=connect][error_code=TCP_TIMEOUT][correlation_id=flow-42] connection failed
```

`component` 必填；`phase`、`error_code` 与 `correlation_id` 可选，未提供时不会输出。每个字段值必须由 1...64 个 ASCII 标识符字节组成，可使用字母、数字、`.`、`_`、`:` 或 `-`。包含空白、分隔符、空值或超长标识符的输入会 fail closed，不会产生含义不明确的字段。这些字段用于与产品模型无关的关联标识，不应承载原始配置或密钥；消息内容仍会在输出前经过默认脱敏。

## 默认密钥脱敏

所有 Swift、C 与 Objective-C 入口都会先脱敏已识别的敏感内容，再应用所请求的 public/private 路由：

- 不区分大小写的命名值，例如 `password`、`token`、`api_key`、`private_key` 与 `proxy_url`，包括查询参数和带引号的 JSON 形式
- 完整的 `Authorization`、`Proxy-Authorization`、`Cookie`、`Set-Cookie` 与 `X-API-Key` header 值
- URL 中的用户凭据，例如 `socks5://user:password@proxy.example`
- label 中包含 `PRIVATE KEY` 的完整 PEM 块

普通值替换为 `<redacted>`，私钥块替换为 `<redacted-private-key>`。C redactor 对非空输出缓冲区始终写入 NUL 终止符，并基于已经脱敏的结果执行截断，因此短缓冲区不会暴露已匹配值的片段。输入达到 64 KiB 扫描上限时会 fail closed，不产生输出。隐私路由仍是独立防线：调用方不应记录无法识别、没有字段标签的原始密钥，并应默认使用 `.private`，除非消息明确需要公开。

---

## Objective-C 使用方式

```objc
FLLogOCHandle h = FLLogOCCreate(nil, @"network");
FLLogOCInfoH(h, "connected");
FLLogOCErrorH(h, "connection failed");
FLLogOCLogH(h, FLLogOCLevelInfo, FLLogOCPrivacyPrivate,
            @"user-selected path");
FLLogOCLogStructuredH(h, FLLogOCLevelError, FLLogOCPrivacyPrivate,
                     @"packet-tunnel", @"connect", @"TCP_TIMEOUT",
                     @"flow-42", @"connection failed");
FLLogOCDestroy(h);
```

---

## C 使用方式

```c
FLLogCHandle h = FLLogCCreate(NULL, "lwip");
FLLogCLogfH(h, FL_LOG_LEVEL_DEBUG, "recv len=%u", len);
FLLogCLogH(h, FL_LOG_LEVEL_INFO, FL_LOG_PRIVACY_PRIVATE,
           "user-selected path");
FLLogCFields fields = {
    .component = "packet-tunnel",
    .phase = "connect",
    .errorCode = "TCP_TIMEOUT",
    .correlationID = "flow-42",
};
FLLogCLogStructuredH(h, FL_LOG_LEVEL_ERROR, FL_LOG_PRIVACY_PRIVATE,
                     &fields, "connection failed");
FLLogCDestroy(h);
```

C 与 Objective-C handle 必须由一个生命周期 owner 独占管理。在 registry 移除前已
borrow handle 的日志与 `isEnabled` 调用可以完成，之后到达的竞态调用会 fail closed；
`FLLogCDestroy` / `FLLogOCDestroy` 会在回收 handle 前等待进行中的 borrow 结束。
owner 必须在开始销毁前停止调度新调用、只调用一次 destroy，并且在 destroy 返回后不再
使用该 handle 值。这个所有权约束也避免 allocator 未来把同一地址分配给另一个 handle
时产生含义不明的旧值复用。

---

## 版本策略

**最新标签版本：** 0.2.0

- 已有 0.2 便捷 API 保持公开消息数据行为
- 所有入口在输出前都会脱敏已识别的敏感内容
- 内部实现行为可能继续演进
- 当前尚不承诺 API 兼容性

---

## 开发与 CI

在仓库根目录运行与 GitHub Actions 相同的 macOS 门禁：

```sh
./Scripts/ci.sh
```

门禁会重置并解析 package dependencies，打印当前 Swift、Xcode 和 macOS 工具链，构建和测试 Debug/Release 配置，检查完整 Swift 并发诊断，并执行生产代码覆盖率门禁。

仅运行覆盖率门禁：

```sh
./Scripts/coverage.sh
```

覆盖率统计包含 `Sources/` 下 Swift `ForgeLogKit`、C `ForgeLogKitC` 和 Objective-C `ForgeLogKitOC` target 的全部可插桩文件，不包含测试和 test-support 源码。生产代码总行覆盖率门槛为 95%；脚本会将按 target 和文件汇总的结果写入 `.build/coverage/production-summary.md`。

Objective-C 适配器和 Apple Unified Logging API 依赖 macOS/Xcode，因此首版 required gate 有意使用一个稳定的 macOS runner，而不使用跨平台矩阵。

---

## 许可证

[Apache License 2.0](LICENSE)
