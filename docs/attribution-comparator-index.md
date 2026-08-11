# 归因与落地页对标资料索引

用途：提供给后续分析 Agent 的本地对标资料清单。

规则：

- 优先记录本地下载包地址、App 包地址和已看到的客观资料。
- `未找到` 表示当前工作区和 `/Applications` 中没有对应文件，不表示对方没有该 App。
- 不根据域名、Scheme 或 App Store 页面推断应用归属。
- 代码分析分别记录在各自的文件中。

## 对标 1：ShortMax / shorttv

### H5 资料

- 本地 H5 包：`/Users/admin/Downloads/w2a.shorttv.live`
- 原始压缩包：`/Users/admin/Downloads/w2a.shorttv.live.zip`
- 同一资料的另一份副本：`/Users/admin/Downloads/w2a.shorttv.live 2`
- 本地入口文件：`/Users/admin/Downloads/w2a.shorttv.live/w2a.shorttv.live/v6/3/fb02.html`

### iOS App 资料

- 本地 App 包：`/Applications/ShortMax.app/Wrapper/Shorts.app`
- 外层安装包：`/Applications/ShortMax.app`
- Bundle ID：`live.shorttv.ios`
- 版本：`2.24.0`
- IPA 文件：未找到独立 `.ipa` 文件；当前为已安装 `.app` 包。

### H5 代码资料位置

- `/Users/admin/Downloads/w2a.shorttv.live/w2a.shorttv.live/v6/3/js/index02.js`
- `/Users/admin/Downloads/w2a.shorttv.live/w2a.shorttv.live/v6/3/utils/config.js`
- `/Users/admin/Downloads/w2a.shorttv.live/w2a.shorttv.live/v6/3/utils/utils.js`
- `/Users/admin/Downloads/w2a.shorttv.live/w2a.shorttv.live/v6/3/lib/clipboard.js`
- `/Users/admin/Downloads/w2a.shorttv.live/api.shorttv.live/attr-svc/attr/click/lp-click-upload.json`
- `/Users/admin/Downloads/w2a.shorttv.live/api.shorttv.live/attr-svc/attr/click/redirect-page-upload.json`

### 现有分析文件

- [ShortMax iOS 静态分析](/Users/admin/Documents/JJ-TV/repos/tv-app/docs/shortmax-ios-attribution-static-analysis.md)

## 对标 2：NetShort

### H5 资料

- 本地 H5 包：`/Users/admin/Downloads/fb.netshort.com`
- 本地入口文件：`/Users/admin/Downloads/fb.netshort.com/fb.netshort.com/netshort-h5-landing-page/wiQJZHPug1S.html`
- 业务脚本：`/Users/admin/Downloads/fb.netshort.com/fb.netshort.com/netshort-h5-landing-page/js/index.js`
- Meta Smart Script：`/Users/admin/Downloads/fb.netshort.com/fb.netshort.com/netshort-h5-landing-page/afSmartScript/Meta_Web_W2A.js`
- H5 点击采集响应样本：`/Users/admin/Downloads/fb.netshort.com/secapi.netshort.com/prod-web-api/auth/collect_w2a_data.html`

### iOS App 资料

- 本地 App 包：`/Applications/NetShort.app/Wrapper/NetShort.app`
- 外层安装包：`/Applications/NetShort.app`
- Bundle ID：`com.netshort.abroad`
- 版本：`2.2.6`（build `2607301729`）
- IPA 文件：未找到独立 `.ipa` 文件；当前为已安装且 DRM 加密的 `.app` 包。

### 现有分析文件

- [NetShort iOS 与 W2A 静态分析](/Users/admin/Documents/JJ-TV/repos/tv-app/docs/netshort-ios-attribution-static-analysis.md)

## 文件对应关系

| 编号 | 对标项目 | H5 本地资料 | iOS App/IPA 本地资料 | 独立 IPA |
|---|---|---|---|---|
| 1 | ShortMax / shorttv | `/Users/admin/Downloads/w2a.shorttv.live` | `/Applications/ShortMax.app/Wrapper/Shorts.app` | 未找到 |
| 2 | NetShort | `/Users/admin/Downloads/fb.netshort.com` | `/Applications/NetShort.app/Wrapper/NetShort.app` | 未找到 |

## Yogo 待改文件地址

### H5 落地页

- `/Users/admin/Documents/JJ-TV/repos/slot-TV/op_new/app-share.html`

### App 归因、Deep Link、剪贴板与启动入口

- `/Users/admin/Documents/JJ-TV/repos/tv-app/lib/adjust_tracking.dart`
- `/Users/admin/Documents/JJ-TV/repos/tv-app/lib/deep_link_handler.dart`
- `/Users/admin/Documents/JJ-TV/repos/tv-app/ios/Runner/AppDelegate.swift`
- `/Users/admin/Documents/JJ-TV/repos/tv-app/ios/Runner/Runner.entitlements`
- `/Users/admin/Documents/JJ-TV/repos/tv-app/lib/main.dart`
- `/Users/admin/Documents/JJ-TV/repos/tv-app/lib/global.dart`

### App 页面调用入口

- `/Users/admin/Documents/JJ-TV/repos/tv-app/lib/pages/home.dart`
- `/Users/admin/Documents/JJ-TV/repos/tv-app/lib/pages/login.dart`

### App 依赖配置

- `/Users/admin/Documents/JJ-TV/repos/tv-app/pubspec.yaml`

## Yogo 当前问题记录

以下内容是当前测试中已经出现的现象，不代表根因已经确认。

### 1. Adjust 归因结果不正确

- 广告落地页 URL 中带有 Adjust token、campaign、adgroup、creative、`fbclid` 和 UTM 参数。
- 测试点击来自广告链接，但 App 登录接口收到的 `ad_attr_info` 仍然出现：

```json
{
  "trackerName": "Organic",
  "network": "Organic",
  "campaign": "",
  "adgroup": "",
  "creative": "",
  "fbInstallReferrer": null
}
```

- 已出现的 tracker token 示例：`22qdy9rw`。
- 现象：有广告点击，但安装后没有恢复对应的广告来源，结果显示为 Organic。
- ATT 允许和不允许的测试中，都出现过没有恢复广告层级信息的情况。

### 2. Facebook 内置浏览器点击后出现 Adjust 页面

- 落地页点击 `Open` 后，浏览器顶层进入 `app.adjust.com`。
- 页面可能显示：`Yogo - ios`、`DOWNLOAD APP`、`Please press the button to proceed to your app`。
- 部分测试会先出现 iOS 的“退出 Facebook，打开应用”确认框。
- 点击后不是直接进入 App，而是先展示 Adjust 页面或需要再次点击下载/打开。

### 3. Safari 直接打开时没有进入对应剧集

- 从 Safari 直接打开落地页时，部分 iPhone 测试机没有进入指定剧集。
- 已测试参数示例：`movie id=10665`、`episode=1`。
- 页面能够展示剧集封面，但未确认 App 是否收到并执行对应的剧集参数。

### 4. App 安装后没有自动进入指定剧集

- 安装并登录后，部分测试机停留在 YogoShort 封面或首页。
- 未稳定自动进入 `movie id=10665`、`episode=1`。
- 当前需要单独确认：Deep Link 是否收到、剪贴板是否读到、归因回调是否在跳剧前完成。

### 5. H5 与 Adjust 请求的已观察行为

- 当前 H5 会根据 URL 参数生成 Adjust 请求。
- Adjust 请求能够返回 `302`。
- 返回内容曾尝试跳转到 `com.yogotv.app://...`。
- 隐藏图片请求遇到非 HTTP Scheme 时，浏览器控制台出现 `Redirection to URL with a scheme that is not HTTP(S)`。
- Facebook 和 Safari 对该跳转的表现不一致。

### 6. 当前尚未确认的项目

- Adjust 后台对应 token 的 Deep Link 配置是否正确。
- Adjust 是否已经记录了广告点击。
- iOS App 是否正确接收 Adjust deferred deep link 回调。
- iOS Universal Link、Associated Domains 和 AASA 文件是否完整匹配。
- App 是否在首次启动时正确读取剪贴板内容。
- Adjust 归因数据变成 Organic 的具体环节：落地页请求、Adjust 匹配、App 首次启动回调，还是 App 上报时序。

## 资料状态

- 对标 1：H5 和 iOS App 已有本地资料。
- 对标 2：H5 和 iOS App 已有本地资料，已完成第一轮静态分析。
