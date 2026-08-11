# NetShort iOS 2.2.6 归因、Deferred Deep Link 与跳剧静态分析

分析日期：2026-08-10

## 1. 分析对象与结论

- 已安装 App：`/Applications/NetShort.app/Wrapper/NetShort.app`
- Bundle ID：`com.netshort.abroad`
- 版本：`2.2.6`（build `2607301729`）
- H5 本地包：`/Users/admin/Downloads/fb.netshort.com`
- H5 入口：`/Users/admin/Downloads/fb.netshort.com/fb.netshort.com/netshort-h5-landing-page/wiQJZHPug1S.html`

已确认的完整设计是：

```text
NetShort 自有落地页
├─ 保存 link_id、广告渠道、剧 ID、视频 ID、集数
├─ AppsFlyer Smart Script 生成 OneLink
├─ 把 OneLink 写入剪贴板（页面加载和点击时都会尝试）
├─ 把 OneLink、UA、系统/浏览器和粗粒度设备信息加密上传自有后台
└─ 点击后打开 OneLink
   ├─ 已安装：Universal Link / netshort:// 拉起 App
   └─ 未安装：跳 App Store

App 首次启动
├─ AppsFlyer UDL：didResolveDeepLink
├─ AppsFlyer conversion data：onConversionDataSuccess
├─ Universal Link / Scheme
├─ 剪贴板兜底
└─ NetShort 自有归因协调器
   ├─ 汇总 AppsFlyer ID、SDK 回调、剪贴板和启动状态
   ├─ 上报 NetShort 后台
   └─ 取得业务数据后跳到指定视频/短剧
```

因此 NetShort 不是只靠剪贴板，也不是只靠 AppsFlyer。它用 AppsFlyer 作为主归因和 Deferred Deep Link，用剪贴板和自有 W2A 点击采集作为补充，再由自己的协调器和后台完成业务匹配、去重与跳剧。

## 2. 落地页已确认行为

### 2.1 AppsFlyer Smart Script 生成 OneLink

本次下载包中参与该流程的文件是：

- `netshort-h5-landing-page/wiQJZHPug1S.html`
- `netshort-h5-landing-page/js/index.js`
- `netshort-h5-landing-page/afSmartScript/Meta_Web_W2A.js`

页面加载后：

- 生成结果读取自 `window.result.clickURL`
- 默认 OneLink 域名为 `https://netshort.onelink.me/7xW2`
- `pid`、`c`、`af_adset`、`af_ad`、`af_channel` 分别映射渠道、计划、广告组、广告和版位
- `link_id` 被映射为 `deep_link_value`
- `type` 被映射为 `af_sub1` 和 `deep_link_sub1`
- `fbclid`、`af_c_id`、`af_adset_id`、`af_ad_id` 也会进入 OneLink

页面业务数据还包含：

- `linkId`
- `shortPlayLibraryId`
- `videoId`
- `playEpisodeNo`
- `promotionChannel`
- `channelNo`

当前样本的广告入口模板是：

```text
https://fb.netshort.com/welcome
?pid=metaweb_int
&c={{campaign.name}}
&af_c_id={{campaign.id}}
&af_adset={{adset.name}}
&af_adset_id={{adset.id}}
&af_ad={{ad.name}}
&af_ad_id={{ad.id}}
&af_channel={{placement}}
&af_siteid={{site_source_name}}
&af_force_deeplink=true
&type=1
&link_id=2084661291229376513
&af_sub2=0
```

这说明广告后台宏先落到 NetShort H5，再由 Smart Script 原样映射或转换到最终 OneLink；业务 `link_id` 与广告层级参数没有混成一个对象。

### 2.2 OneLink 被主动写入剪贴板

对方页面定义了三级复制策略：优先使用 `navigator.clipboard.writeText()`；失败后监听 `copy` 事件并执行 `document.execCommand("copy")`；仍失败时创建隐藏文本节点并再次复制。

```js
document.execCommand("copy")
```

该复制函数至少在两个位置调用：

1. Smart Script 成功生成 `clickURL` 后立即复制；
2. 用户点击 `Watch it!` 时再次复制，然后打开 OneLink。

所以对方的剪贴板内容不是 Facebook 参数原文，而是完整的 AppsFlyer OneLink。

### 2.3 H5 将点击候选上传自有后台

生成 OneLink 后，H5 会调用：

```text
POST /auth/collect_w2a_data
```

生产域名来自下载包中的请求配置，完整路径为：

```text
https://secapi.netshort.com/prod-web-api/auth/collect_w2a_data
```

加密前的业务字段可以从前端代码确认：

```text
onelinkUrl
model
ua
mediaSourceType
os
osverion
httpReferrer
browserOsversion
```

请求体使用对称加密，临时密钥再加密放入请求头。下载包里保存的接口响应也是密文，所以仅靠静态文件不能还原后台匹配算法；但可以确认“落地页点击候选先上传 NetShort 自有后台”这条链路真实存在。

### 2.4 H5 的 Meta Pixel 与行为事件

当前样本带有 Meta Pixel ID。Facebook 渠道页面会执行 `fbq("init", ...)` 和 `PageView`，并把 `linkId + 时间戳` 形式的值作为 `external_id` 候选。页面还初始化神策 Web SDK：

```text
https://collect.netshort.net/sa?project=production
```

并记录 `PageLoadComplete`、`WebClick`、自动跳转开始/完成等事件。它把“广告平台 Web 事件”“自有页面行为分析”和“安装归因链接”分开处理，这三者不是同一条接口。

### 2.5 点击不展示 AppsFlyer 中间页

对方点击逻辑的核心是：

```js
window.open(oneLink) || (window.location.href = oneLink)
```

2026-08-10 在桌面 Chrome 实测：点击后直接打开 NetShort App Store 页面，浏览器没有停留在 AppsFlyer 中间页。实际仍经过 OneLink，AppsFlyer 请求和跳转只是对用户不可见。

## 3. App 内 AppsFlyer 与唤端配置

### 3.1 Universal Link 与 Scheme

App 注册自定义 Scheme：

```text
netshort://
```

签名权限中的 Associated Domains：

```text
applinks:netshort.onelink.me
webcredentials:netshort.onelink.me
applinks:w2atest01.onelink.me
webcredentials:w2atest01.onelink.me
applinks:www.netshort.com
webcredentials:www.netshort.com
```

这说明 OneLink 和 NetShort 自有域名都可以作为 Universal Link 入口。`netshort://` 是 Scheme 入口或 fallback。

### 3.2 AppsFlyer 回调

主程序静态链接了 AppsFlyer，并实现：

- `didResolveDeepLink(_:)`
- `onConversionDataSuccess(_:)`
- `onConversionDataFail(_:)`
- `AppsFlyerDeepLinkDelegate`
- `AppsFlyerLibDelegate`

程序明确区分：

- direct deep link
- deferred deep link
- organic install
- non-organic install
- first launch / not first launch
- `deep_link_value`
- `media_source`
- `campaign`
- `af_channel`
- `af_sub1` 至 `af_sub5`

`NSAdvertisingAttributionReportEndpoint` 配置为：

```text
https://appsflyer-skadnetwork.com/
```

App 同时配置了 261 条 `SKAdNetworkIdentifier`，所以拒绝 ATT 后仍有 Apple 聚合归因路径，但不能保证每个用户都返回完整的广告层级。

## 4. App 内剪贴板处理

主程序保留了源文件路径：

```text
MaiyaPlaylet/Classes/Main/AppDelegate+Pasteboard.swift
```

可确认的方法和状态包括：

- `checkPasteboard()`
- `pasteboardToInvite()`
- `pasteboardDone()`
- `ClipBoardRead`
- `MaiyaAnalytisClipBoardReadModel`
- `e_content`
- `e_parsed_link_id`
- `not_get_pasteboard`

AppsFlyer 处理流程还存在日志：

```text
Deferred deep link was already processed by pasteboard.
```

这说明 App 会对 AppsFlyer UDL、conversion data 和剪贴板结果做去重，而不是三路都重复跳转。

## 5. NetShort 自有“归因协调器”证据

主程序包含：

- `MaiyaAttributionApiReporter`
- `MaiyaAdAttributionContext`
- `MaiyaAttributionApiResult`
- `MaiyaAttributionTriggerSource`
- `MaiyaAttributionReason`

最关键的方法签名为：

```text
reportAfData(
  afId,
  afSdkBody,
  shearPlate,
  model,
  isHotStart,
  triggerSource,
  completion
)
```

其中：

- `afId`：AppsFlyer ID；
- `afSdkBody`：AppsFlyer SDK 回调数据；
- `shearPlate`：剪贴板内容；
- `isHotStart`：是否热启动；
- `triggerSource`：此次归因上报由哪一路触发。

App 还记录：

- `isTodayFirstStart`
- `isTodayFirstColdStart`
- `isTodayFirstHotStart`
- `reportAfDataByUDL`
- `deferred_dup`
- `not_gcd_success`
- `not_get_pasteboard`
- `af_body_null`
- `business_data_empty`

同时存在以下候选来源标识：

- `request_linkid_af_GCD`
- `request_linkid_af_UDL`
- `request_linkid_clipboard`
- `request_linkid_install_referrer`
- `request_linkid_self_attribution`
- `request_linkid_natural_user`

这说明协调器至少设计了 AppsFlyer GCD、UDL、剪贴板、install referrer、自归因和自然用户等候选入口。静态包能证明这些代码路径存在，但不能证明线上远程配置当前全部启用，也不能据此断言它们的运行时优先级。

## 6. 自有后台与跳剧证据

### 6.1 自有归因接口

已发现接口：

```text
/strategy/attr/report
```

它对应 `MaiyaAttributionApiReporter`，用于把 App 端归因结果上传 NetShort 自己的后台。

### 6.2 App Link 启动接口

已发现：

```text
/auth/app_link_startV2
```

对应方法：

```text
appLinkStart(linkId:deepLinkValue:mediaSource:completion:)
```

相关业务字符串包括：

- `user_first_install_open`
- `direct_video_jump`
- `videoId`
- `queryId`
- `deferPullSeries()`
- `loadNaturalNewUserVideo()`

据此可以确认：App 并不是仅在本地把 `deep_link_value` 当剧 ID 使用。它会把 `linkId`、`deepLinkValue`、`mediaSource` 发给自己的启动接口，由后台返回或补全业务数据，再决定跳指定视频还是走自然用户默认内容。

## 7. 另一套自有链接 SDK

App 还静态链接了 `TurboLinkSDK 2.0.9`，其服务域名和接口包括：

```text
https://www.allapp.link
/v3/deeplink/create
/v2/campaign/campaign-info
/v2/event/campaign-launch-stat
/v2/campaign/client-reward
```

该 SDK 支持：

- Universal Link / Scheme 验证；
- 剪贴板；
- install/open/reopen；
- campaign 与奖励活动；
- `linkClickTime`、`inClipboard`、`linkData`。

从当前广告落地页可以确认主广告链路是 AppsFlyer OneLink；TurboLink 更像 NetShort 另外的分享、邀请、活动链接体系，不能把它误认为本次 Facebook 广告归因的唯一入口。

## 8. Meta 与拒绝 ATT

App 包含：

- `FBSDKCoreKit`
- `FBAEMKit`
- Facebook App ID 与 Scheme
- Meta SKAdNetwork 配置

`FacebookAutoLogAppEventsEnabled = false`，说明对方没有完全依赖 Meta SDK 自动事件，业务事件可能由自己的分析层显式发送。App 的隐私清单声明 `NSPrivacyTracking = false`，但同时提供了 ATT 用途说明；这两项是包内配置事实，不能仅凭静态包判断线上何时弹 ATT 或其合规结论。

拒绝 ATT 后：

- IDFA 不可用；
- AppsFlyer 精确匹配能力可能下降；
- SKAdNetwork、Meta AEM、AppsFlyer 聚合归因仍可工作；
- AppsFlyer Deferred Deep Link、自有后台匹配和剪贴板仍是独立路径；
- 用户若同时拒绝 ATT 和粘贴，仍不能保证每一台手机都恢复完整广告来源和指定剧。

## 9. 对 Yogo 最有价值的借鉴

NetShort 值得借鉴的不是单独某一行跳转代码，而是分层：

```text
H5
├─ 保留完整广告参数和业务 link_id
├─ 生成归因服务链接
├─ 写剪贴板作为安装后兜底
├─ 把点击候选和粗粒度环境信息上传自有后台
└─ 打开归因链接，由其拉 App / 回退商店

iOS
├─ 接 Universal Link / Scheme
├─ 接归因 SDK 的 UDL 与 conversion data
├─ 读剪贴板（用户允许时）
└─ 交给统一协调器去重和上报

自有后台
├─ 点击 link_id 与广告参数落库
├─ 接收 App 的 Adjust/AppsFlyer/剪贴板结果
├─ 做用户、点击和业务内容匹配
└─ 返回 movieId、episode 和最终广告来源
```

如果 Yogo 继续使用 Adjust，也可以借用相同的协调器结构：把 AppsFlyer UDL/GCD 换成 Adjust attribution/deferred deep link。核心是“SDK + Universal Link + 规则化剪贴板 + 自有后台”多路汇总，而不是让 H5 的一次隐藏请求承担全部归因和跳剧。

其中自有后台至少需要两类接口：

1. H5 点击登记：生成一次性 `click_id`，保存广告参数、业务参数、时间、UA/IP 的服务端结果和有效期；
2. App 首启匹配：App 上送 SDK 结果、合法剪贴板载荷、设备侧可用信号和 `click_id`，后台按强弱规则返回唯一匹配结果。

匹配结果还必须带 `match_method`、`confidence`、`matched_at` 和幂等键，避免把多个候选直接覆盖成最后一次结果。IP/UA 只能作为短时间窗口内的低置信候选，不能作为确定性用户标识。

## 10. 静态分析限制

本文可以确认包内配置、类名、方法、接口和日志字符串，但不能仅凭 App Store 包确认：

- 某次线上请求最终返回了什么；
- AppsFlyer 后台当前 OneLink 模板配置；
- 用户拒绝 ATT/粘贴时每一台设备的实际匹配成功率；
- 远程配置是否暂时关闭某一路。
- `/auth/collect_w2a_data` 的服务端字段、匹配权重和保留期限。

最终仍需用一台干净测试机执行“点击广告链接 → 安装 → 首次启动”，同时查看 AppsFlyer 后台、NetShort 式自有归因接口日志和 App 跳剧结果。
