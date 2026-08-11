# ShortMax iOS 2.24.0 归因与 Deep Link 静态分析

## 1. 分析对象与限制

- 安装包：`/Applications/ShortMax.app/Wrapper/Shorts.app`
- Bundle ID：`live.shorttv.ios`
- 版本：`2.24.0`
- 主程序：`Shorts`，arm64
- 主程序仍带 App Store DRM，`LC_ENCRYPTION_INFO_64 cryptid = 1`。

因此，本文可以确认 SDK、配置、类名、成员、回调、接口路径和日志字符串，但不能把主程序完整恢复成原始 Swift 源码，也不能仅凭静态文件确认远程开关在某一次运行中最终选择了哪一路。

## 2. 已确认的归因组件

### 2.1 AppsFlyer

- `AppsFlyerLib` 版本 `6.17.7` 静态链接在主程序中。
- App 实现了 `didResolveDeepLink`、`onConversionDataSuccess`、`onConversionDataFail` 和 `onAppOpenAttribution` 等回调。
- Associated Domains 包含：
  - `applinks:shorttv.onelink.me`
  - `applinks:shorttv.go.link`
- `Info.plist` 的 `NSAdvertisingAttributionReportEndpoint` 是：
  - `https://appsflyer-skadnetwork.com/`

这证明 Apple 的隐私归因回传副本被配置为发送给 AppsFlyer；AppsFlyer 同时负责 OneLink、Universal Link 和延迟 Deep Link。

### 2.2 Adjust

- `AdjustSdk.framework` 版本 `5.5.1`。
- `AdjustSigSdk.framework` 版本 `1.0`。
- App 自己有 `AdjustManager.swift`，实现：
  - `adjustDeferredDeeplinkReceived`
  - `adjustAttributionChanged`
  - Scheme URL 和 Universal Link 处理
- 自有后台存在以下 Adjust 匹配上报接口：
  - `/attr-svc/attr/track/adjust-match-upload`
  - `/attr-svc/attr/track/adjust/udl-match-upload`

这说明 ShortMax 并没有放弃 Adjust。AppsFlyer 和 Adjust 两套代码都存在，实际启用策略还受本地/远程配置控制。

### 2.3 Meta 官方统计

App 包含：

- `FBSDKCoreKit` 16.3.1
- `FBAEMKit` 16.3.1
- Meta SKAdNetwork/AEM 相关实现
- `FBSDKAppEventsCAPIManager`

`Info.plist` 明确配置：

- `FacebookAutoLogAppEventsEnabled = true`
- `FacebookAdvertiserIDCollectionEnabled = true`
- `GatewayDomain = https://capi.shorttv.live`
- `GatewayDataSourceID` 已配置

因此 ShortMax 不只依赖落地页 Pixel。App 内还使用 Meta App Events、AEM/SKAdNetwork，并配置了自己的 Meta CAPI Gateway。

### 2.4 Apple 隐私归因

- `Info.plist` 内有 256 个去重后的 `SKAdNetworkIdentifier`。
- 其中包含 Meta 使用的 `v9wttpbfk9.skadnetwork`。
- App 同时包含 AppsFlyer、Adjust 和 Meta 的 SKAdNetwork 更新/回传代码。

用户拒绝 ATT 后，IDFA 不可用，但这套 Apple 聚合归因链路仍可统计广告活动的安装和转化。它不等于每个 App 用户都能获得完整 campaign/adgroup/creative。

## 3. 安装后来源恢复不是只靠剪贴板

主程序的 `SourceTrackManager` 同时保存和等待：

- `isAPPSourceTrackFinished`
- `isAFSourceTrackFinished`
- `isAdjustSourceTrackFinished`
- `pasteboardContent`
- `AFConversionInfo`
- `AFUDLInfo`
- `adjustUDLInfo`
- `adjustAttribution`
- `isUniversalLinkOpen`

同时存在以下自有后台接口：

- `/attr-svc/attr/track/self-match-upload`
- `/attr-svc/attr/track/af-match-upload`
- `/attr-svc/attr/track/adjust-match-upload`
- `/attr-svc/attr/track/udl-match-upload`
- `/attr-svc/attr/track/adjust/udl-match-upload`
- `/attr-svc/app/hiAdActivate/lpActivate`

可确认的结构是：

```text
App 首次启动
├─ 读取自有来源/剪贴板
├─ 请求 AppsFlyer conversion data / UDL
├─ 请求 Adjust attribution / UDL
├─ 处理 Universal Link / Scheme
└─ 将各路匹配结果上传 ShortMax 自己的 attr-svc
   ├─ 保存 attributedPlatform
   └─ 保存 attributedShortPlayId
```

因此，剪贴板只是其中一路。用户拒绝粘贴后，AppsFlyer、Adjust、Universal Link、Apple/Meta 聚合归因和自有匹配仍可继续工作。

## 4. 剪贴板证据

App 内有自己的：

- `PasteboardAuthProvider.swift`
- `PasteboardAuthProvider`
- `pasteboardContent`
- `ddl_preparePasteBoardContentParser`
- 日志 `start request pasteboard`、`get pasteboard content`

另外，`TurboLinkSDK` 也包含：

- `enablePasteboard`
- `pasteboardContent`
- `linkClickTime`
- `inClipboard`
- `InstallOrOpen`、`Install`、`Open`、`Reopen`

这证明 ShortMax 确实读取剪贴板并把它用于链接/活动恢复，但不能证明剪贴板是每次安装归因的必需条件。

## 5. 跳指定短剧的证据

App 包含：

- `EpisodeDetailUniversalLinkAdapter`
- `EpisodeDetailUniversalLinkModel`
- `universalLinkShortPlayDidResolved`
- `_attributedShortPlayId`
- `_universalShortPlayInfo`
- `dramaId`、`shortPlayId`

Associated Domains 包含：

- `applinks:h5.reelplay.me`
- `applinks:shorttv.onelink.me`
- `applinks:shorttv.go.link`
- `applinks:deeplink.dev`

因此，已安装场景主要由 Universal Link/OneLink 直接把短剧参数交给 App；新安装场景再由 AppsFlyer/Adjust 延迟 Deep Link、自有匹配和剪贴板多路恢复。

## 6. 用户拒绝权限后的实际结果

### 拒绝 ATT

- IDFA 不可用。
- Apple SKAdNetwork、Meta AEM、AppsFlyer SKAN 和 Adjust SKAN 仍可提供汇总归因。
- AppsFlyer/Adjust/自有接口可能仍返回部分匹配数据，但不能保证每个用户都有完整广告层级。

### 拒绝粘贴

- 剪贴板路径失效。
- AppsFlyer UDL、Adjust UDL、Universal Link、自有来源匹配仍会继续。
- 如果其余路径都匹配失败，只能保留平台侧汇总广告统计，具体用户来源和目标短剧可能丢失。

## 7. 与 Yogo 当前实现的差距

Yogo 当前只有 Adjust SDK 和自有 Universal Link 草稿，尚未发现：

- Meta iOS SDK/FBAEMKit
- Meta CAPI Gateway 配置
- AppsFlyer SDK/OneLink
- `NSAdvertisingAttributionReportEndpoint`
- `SKAdNetworkItems`
- App 读取落地页剪贴板的实现
- 汇总 AppsFlyer、Adjust、Universal Link、自有匹配结果的归因协调器
- 对应的自有点击/安装匹配接口

## 8. 可借鉴的无 Adjust 版本

如果 Yogo 决定不使用 Adjust，最接近 ShortMax 已验证结构的方案是：

```text
落地页 Meta Pixel + Yogo 点击接口
        ↓
Yogo Universal Link / AppsFlyer OneLink
        ↓
App 首次启动
├─ AppsFlyer UDL / conversion data
├─ Universal Link
├─ 剪贴板兜底
└─ Yogo 自有匹配接口
        ↓
Meta App Events + FBAEMKit + CAPI Gateway
        ↓
Apple SKAdNetwork 汇总归因
```

这一方案能在拒绝 ATT 时保留 Meta/Apple 汇总统计，并提高安装后恢复剧集和广告来源的成功率。但在用户同时拒绝 ATT、拒绝粘贴，且 AppsFlyer/自有匹配失败时，仍不能保证具体用户级归因；ShortMax 也没有绕过这一苹果限制。
