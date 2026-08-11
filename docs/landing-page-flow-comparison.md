# 落地页唤端流程对照分析

> 资料索引请先看：[归因与落地页对标资料索引](/Users/admin/Documents/JJ-TV/repos/tv-app/docs/attribution-comparator-index.md)。本文件是历史分析记录，包含分析过程；不作为本地资料清单。

分析日期：2026-08-05

本文件只记录对本地保存的三个对照落地页和 Yogo 当前实现的静态分析结果。对照页中的代码均标记为“对方代码”；没有把推测当成已验证事实。代码块若标注“语义化还原”，表示原始 bundle 已压缩，变量名被改成了便于阅读的名字；精确位置仍以右侧文件链接为准。

## 结论先行

三个对照实现的共同点不是“把一个自拼接的 Adjust URL 交给 Facebook 内置浏览器，然后等待 Adjust 中间页完成唤端”，而是把下面几件事分开处理：

1. 记录广告点击和归因参数；
2. 通过 Universal Link、App Link、SDK 唤端或自定义 Scheme 尝试打开 App；
3. App 未被唤起时跳转商店；
4. 对安装后的 Deferred Deep Link，使用 OneLink/SDK/剪贴板等机制继续传递内容参数。

Yogo 当前实现则是：落地页点击后直接导航到 `https://app.adjust.com/{token}`，把 `com.yogotv.app://open?...` 放进 Adjust 参数，由 Adjust 的 Facebook/iOS 中间页再尝试唤起 App。

因此，Yogo 当前看到的 Adjust 中间页并不能与这三个对照页的“落地页行为”直接等价。最需要先验证的是：Facebook 内置浏览器是否允许 Adjust 中间页在跨域导航、延迟定时器和隐藏 iframe 中调用自定义 Scheme。

## 1. 对照页一：`w2a.shorttv.live`

### 1.1 配置明确区分 Universal/App Link 与自定义 Scheme

**对方代码：**

来源：[config.js](/Users/admin/Downloads/w2a.shorttv.live/w2a.shorttv.live/v6/3/utils/config.js:1)

```js
// 唤端的链接 ios:Universal Links, 安卓：appLinks
appLinks: {
    ios: 'https://deeplink.dev',
    android: 'https://deeplink.dev',
},
// 已安装
locationUrl: {
    ios: 'shorttv://showDrama',
    android: 'shorttv://www.shorttv.live/web',
},
// 未安装
storeUrl: {
    ios: 'https://apps.ishort.tv/install/market/AppStore',
    android: 'https://apps.ishort.tv/install/market/GooglePlay?id=live.shorttv.apps',
},
deepLinkInterval: 2000,
```

这里的设计意图很明确：HTTPS 链接用于 Universal Link/App Link，Scheme 用于已安装 App，商店 URL 用于未安装 App。`locationUrl` 在当前保存的 `fillBackUrlToSkip` 路径中没有直接被调用，不能据此断言线上一定使用它；实际线上唤端还依赖配置和 SDK 环境。

### 1.2 测试环境直接跳 HTTPS App Link，生产环境交给 Deeplink SDK

**对方代码：**

来源：[index02.js](/Users/admin/Downloads/w2a.shorttv.live/w2a.shorttv.live/v6/3/js/index02.js:356)

```js
const type = $fetchUserAgent(userAgent)
let appUrl = $shortMaxConfig[$env].appLinks[type];
const appendQuery = transformQueryString()

if (type === 'ios') {
    appUrl = appUrl + `?app=shortmax&shortid=${campaignObj.shortid || configObj.shortPlayCode}&${appendQuery}`
    const ppidStr = configObj.ppid ? ((new URLSearchParams(configObj.ppid)).get("ppid") || "") : "";
    if (ppidStr) {
        appUrl = appUrl + `&ppid=${ppidStr}`
    }
} else {
    appUrl = appUrl + `?app=shortmax&shortid=${campaignObj.shortid || configObj.shortPlayCode}&${appendQuery}`
}

if ($env === 'test' && platformShortName !== 'SNAP') {
    window.location.href = appUrl;
    return;
}

deeplink('track', 'JumpToTarget', {
    deeplinkOpt: {
        app: "shortmax",
        ppid: ppid,
        referrer: refererStr,
        app_clickId: app_clickId,
        ttp: newDeepLinkObj.cookieId || (platformShortName === 'FB' ? myFbp : null)
    },
    content: {
        contentName: shortPlayName
    }
});
```

这与 Yogo 的差异是：对方在测试路径中直接把 HTTPS App Link 交给系统，生产路径使用自己的 Deeplink SDK；不是先进入一个通用 Adjust 中间页再由中间页二次唤端。

### 1.3 未安装回退依赖页面隐藏/失焦检测

**对方代码：**

来源：[utils.js](/Users/admin/Downloads/w2a.shorttv.live/w2a.shorttv.live/v6/3/utils/utils.js:353)

```js
const startTime = Date.now();
window.location.href = localUrl;

const timer = setTimeout(() => {
    if (Date.now() - startTime >= deepLinkInterval) {
        window.location.href = storeUrl;
    }
}, deepLinkInterval);

document.addEventListener('visibilitychange', function() {
    if (document.visibilityState === 'hidden') {
        clearTimeout(timer);
    }
});

window.addEventListener('blur', function() {
    clearTimeout(timer);
});
```

这是一条“直接唤端 + 页面状态检测 + 2 秒商店回退”的完整链路。Yogo 当前无 Adjust URL 时也有类似逻辑，但有 Adjust URL 时会绕过自己的 `launchAppWithFallback`，把控制权交给 Adjust：

来源：[app-share.html](/Users/admin/Documents/JJ-TV/repos/slot-TV/op_new/app-share.html:695)

```js
if (isIos()) {
    var iosAdjustUrl = buildAdjustTrackerUrl(...);
    if (iosAdjustUrl) {
        window.location.href = iosAdjustUrl;
        return;
    }
    launchAppWithFallback(buildIosDeepLink(...), APP_STORE_URL);
}
```

### 1.4 对方在点击前后还主动上报和传递点击 ID

**对方代码：**

来源：[index02.js](/Users/admin/Downloads/w2a.shorttv.live/w2a.shorttv.live/v6/3/js/index02.js:458)

```js
async function handleClickSkip(event) {
    event.preventDefault();
    newDeepLinkObj = await getDeeplinkValuesWithTimeout(['cookieId', 'clickId'], 40);
    await reportV5();
    await fillBackUrlToSkip();
}

document.querySelector('.container').addEventListener('click', handleClickSkip);
```

即使最终唤端失败，对方也先把点击事件、设备标识和点击 ID 上报了。Yogo 当前主要依赖 Adjust 请求本身记录点击，落地页没有单独的点击上报闭环。

## 2. 对照页二：`dramacps.top`

### 2.1 通过 AppsFlyer Smart Script 生成 OneLink 归因请求

**对方代码：**

来源：[CPS-2075501067421347840.html](/Users/admin/Downloads/dramacps.top/dramacps.top/app/CPS-2075501067421347840.html:375)

```js
function jssdkSrc(linkId, origin) {
    const params = new URLSearchParams(window.location.search);
    const url = new URL(origin + "/feedback/v1/report/jssdk");

    // 复制 campaign、adgroup、creative、fbclid 等参数
    // ...
    url.searchParams.set("af_force_deeplink", "true");
    url.searchParams.set("af_dp", params.get("af_dp") || params.get("deep_link_value") || "");
    url.searchParams.set("landing_url", decodeURIComponent(location.href));
    return url.toString();
}

const script = document.createElement("script");
script.src = jssdkSrc("CPS-2075501067421347840", "https://san-api.stardust-tv.com");
document.head.appendChild(script);
```

页面入参中明确带有：

```text
deep_link_value=shanhai://push?link_id=...&playletId=20060&type=1
af_dp=shanhai://push?playletId=20060&type=1
```

来源：[CPS-2075501067421347840.html](/Users/admin/Downloads/dramacps.top/dramacps.top/app/CPS-2075501067421347840.html:375)

### 2.2 Deeplink SDK 使用 iOS 唤端地址，失败后跳下载地址

**对方代码：**

来源：[Layout.astro_astro_type_script_index_0_lang.CVeg0QLZ.js](/Users/admin/Downloads/dramacps.top/dramacps.top/app/_astro/Layout.astro_astro_type_script_index_0_lang.CVeg0QLZ.js:5164)

```js
if (_r === "iOS") {
    const wakeUrl = this.data.ios_info.ios_wake_url || this.data.ios_info.url_schemes;
    const downloadUrl = this.data.ios_info.download_url;

    window.location.href = wakeUrl;
    this.timer = setTimeout(function() {
        if (document[qt]) return;
        window.location.href = downloadUrl;
    }, this.timeout);
}
```

这里可以确认对方采用了“直接给 iOS 唤端地址 + 监听页面隐藏 + 超时下载”的模式。唤端 URL 来自服务端 Deeplink SDK 配置，不是前端硬编码一个固定 Scheme。

### 2.3 点击和自动跳转都由同一套 OneLink URL 驱动

**对方代码：**

来源：[script.client.4xEMPr_U.js](/Users/admin/Downloads/dramacps.top/dramacps.top/app/_astro/script.client.4xEMPr_U.js:11017)

```js
function u0(r) {
    const e = C => {
        // 记录 LandingPageClick 等事件
        C.go_page_url && (window.location.href = C.go_page_url)
    };
    try {
        const C = su(),
            { jumpTime: s = 2 } = window.__DATA__ || {};
        // 先把生成的 OneLink 发送到页面事件接口
        t(C);
        r ? e({ go_page_url: C }) : Pi = setTimeout(() => {
            e({ go_page_url: C })
        }, Math.min(s * 1e3, 2147483647))
    } catch (C) {
        e({ go_page_url: "" })
    }
}
```

这是从压缩 bundle 中抽出的关键原代码结构；`u0`、`su`、`t`、`e` 是对方实际使用的压缩名称。可确认流程是：生成 OneLink → 上报落地页事件 → 用户点击或定时器触发 → 导航到 OneLink。Yogo 当前是在点击时动态构造 Adjust tracker URL，然后直接导航到 Adjust。

## 3. 对照页三：`www.dramawavew2a.com`

### 3.1 把自定义 Scheme 放入 AppsFlyer `deep_link_value` 和 `af_dp`

**对方代码：**

来源：[fb_tt_drama_campaign.js](/Users/admin/Downloads/www.dramawavew2a.com/cdn.usrgrow.com/js/fb_tt_drama_campaign.js:193)

```js
function getDlParama(dl_data, params) {
    const dramaId = getDramaId(dl_data);
    const paramsStr = `/detail?id=${dramaId}&${params}`;
    return encodeURIComponent(
        `dramawave://dramawave.app?redirect=${encodeURIComponent(paramsStr)}`
    );
}

// 生成 OneLink 参数
a += "&deep_link_value=" + af_dp + "&af_dp=" + af_dp;
```

对方不是把业务参数散落在顶层 URL，而是先构造完整的：

```text
dramawave://dramawave.app?redirect=/detail?id=...
```

再把它作为 AppsFlyer 的深链参数传递。

### 3.2 对方把归因点击、剪贴板和商店跳转拆开

**对方代码：**

来源：[view.html](/Users/admin/Downloads/www.dramawavew2a.com/www.dramawavew2a.com/ads/0/1723/view.html:1001)

```js
async function onContainerClick(e) {
    const t = Date.now();
    const n = e || buildDeeplink();
    sendBeacon({
        clip_content: n.dp
    }, ONELINK_CLICK_API);
    copyNDAction(n.dp + "&dm_timestamp=" + t + "&event_time=" + t).then(() => {
        sendBeacon({
            clip_content: n.dp + "&dm_event=" + EventTypes.WRITE_CLIP
        })
    });
    sendBeacon({
        clip_content: n.dp + "&dm_event=" + EventTypes.PAGE_CLICK
    });
    window.location.href = n.st;
}
```

页面加载时还会上报 Page View：

来源：[view.html](/Users/admin/Downloads/www.dramawavew2a.com/www.dramawavew2a.com/ads/0/1723/view.html:1025)

```js
setupEventListeners();
window.onload = function() {
    initializeClipboard();
};
```

这说明对方的落地页并不依赖“点击后必须直接拉起 App”来完成归因。它先把 OneLink/深链内容写入上报和剪贴板，再跳商店，依赖 AppsFlyer 完成安装后的 Deferred Deep Link。

## 4. 与 Yogo 当前实现的逐项对比

### 4.1 当前 Yogo 落地页代码

**Yogo 代码：**

来源：[app-share.html](/Users/admin/Documents/JJ-TV/repos/slot-TV/op_new/app-share.html:596)

```js
var url = new URL('https://app.adjust.com/' + token);
url.searchParams.set('campaign', campaign);
url.searchParams.set('adgroup', adgroup);
url.searchParams.set('creative', creative);
url.searchParams.set('deep_link', deepLinkUrl);
url.searchParams.set('redirect', fallbackUrl);

window.location.href = iosAdjustUrl;
```

### 4.2 已确认的差异

| 项目 | 对照页 | Yogo 当前实现 |
|---|---|---|
| 归因点击 | 额外上报、OneLink 请求或 SDK 事件 | 主要依赖 Adjust tracker 请求 |
| iOS 唤端 | Universal Link、SDK 唤端或自定义 Scheme | Adjust 中间页内部尝试 Scheme |
| 触发时机 | 通常仍保留用户点击上下文 | 跨域导航到 Adjust 后由中间页延迟触发 |
| fallback | 页面自己监听 hidden/blur 后跳商店，或由 SDK 处理 | 有 Adjust URL 时由 Adjust 负责 fallback |
| Deferred Deep Link | OneLink/SDK/剪贴板显式传递 | 依赖 Adjust 配置和 App SDK 回调 |
| Universal Link | 对方代码有 HTTPS App Link 设计 | Yogo iOS 工程当前没有 Associated Domains |

## 5. Yogo 当前已确认的 iOS 配置状态

### 5.1 自定义 Scheme 匹配

Yogo 页面使用 `com.yogotv.app://open`：

来源：[app-share.html](/Users/admin/Documents/JJ-TV/repos/slot-TV/op_new/app-share.html:396)

iOS 工程 Bundle ID 为 `com.yogotv.app`：

来源：[project.pbxproj](/Users/admin/Documents/JJ-TV/repos/tv-app/ios/Runner.xcodeproj/project.pbxproj:530)

Info.plist 注册的是 `$(PRODUCT_BUNDLE_IDENTIFIER)`：

来源：[Info.plist](/Users/admin/Documents/JJ-TV/repos/tv-app/ios/Runner/Info.plist:70)

AppDelegate 也按 Bundle ID 接收：

来源：[AppDelegate.swift](/Users/admin/Documents/JJ-TV/repos/tv-app/ios/Runner/AppDelegate.swift:74)

这一部分目前没有发现明显的 Scheme 字符串不一致。

### 5.2 Universal Link 尚未形成闭环

当前 entitlements 没有 `com.apple.developer.associated-domains`：

来源：[Runner.entitlements](/Users/admin/Documents/JJ-TV/repos/tv-app/ios/Runner/Runner.entitlements:1)

线上 `https://yogoshort.com/.well-known/apple-app-site-association` 当前返回 HTML 页面，而不是 AASA JSON。因此不能认为 Yogo 已经具备 Universal Link 能力。

Apple 要求网站 AASA 文件和 App 的 Associated Domains entitlement 同时配置：[Supporting associated domains](https://developer.apple.com/documentation/xcode/supporting-associated-domains)。

## 6. 当前最可信的故障定位

### 已确认事实

- `22o1da5v` 可以被 Adjust 识别；请求返回了 Adjust 的 iOS/Facebook 中间页。
- Facebook UA 下，Adjust 中间页会通过隐藏 iframe 尝试 `com.yogotv.app://open?...`，随后再跳 App Store。
- Yogo 的 Bundle ID、Info.plist Scheme、AppDelegate 接收 Scheme 目前是一致的。
- Yogo 当前没有可用的 Universal Link 配置。
- 本地未提交版本添加 `deeplink` 参数，线上版本仍只使用 `deep_link`；分别测试两种参数时，Adjust 都能生成同样的 iOS Scheme 尝试，因此这不是当前首要嫌疑。

### 尚未确认事实

- 测试设备是否安装了与 `com.yogotv.app` 完全一致的线上 App。
- Facebook iOS 内置浏览器是否阻止 Adjust 中间页的隐藏 iframe Scheme 调用。
- Adjust Dashboard 是否已经记录 token `22o1da5v` 的点击。
- App Store 安装后的 Deferred Deep Link 是否能被当前 App SDK 正确接收。

### 排查优先级

1. 同一台 iPhone、同一个已安装 App，分别从 Safari 和 Facebook 内置浏览器点击 Yogo 链接。
2. 直接在 Safari 的用户点击事件中测试 `com.yogotv.app://open?movieId=10665&episodeNum=1`，区分 App Scheme 本身和 Adjust 中间页的问题。
3. 对比 Adjust 后台 token `22o1da5v` 的 Clicks、iOS Deep Link、fallback 配置。
4. 再决定是继续使用 Adjust 中间页，还是改成“点击事件归因 + 直接 Universal Link/Scheme 唤端 + 页面自有商店 fallback”的组合。

## 7. 对照代码中的额外风险

`dramacps.top` 的某个前端 bundle 中包含了用于请求签名的私钥材料，位置在：[script.client.4xEMPr_U.js](/Users/admin/Downloads/dramacps.top/dramacps.top/app/_astro/script.client.4xEMPr_U.js:10841)。这里不复制具体密钥内容，但这说明对方实现虽然流程完整，安全性并不适合作为 Yogo 的直接模板。

## 最终判断

不能直接照搬某一个对照页的跳转代码。对方真正值得借鉴的是“归因、唤端、fallback、Deferred Deep Link 分层”的架构，而不是某个具体参数名。

Yogo 当前最接近失败点的是：Adjust 中间页在 Facebook 内置浏览器里延迟调用自定义 Scheme；Universal Link 又尚未配置，导致没有第二条可靠的 iOS 唤端路径。上线前应先用真实 iPhone 完成上述对比测试，再决定改 Adjust 配置、改 App 的 Associated Domains，还是改落地页的触发链路。

## 8. 2026-08-05 新增实测问题记录

本节记录本次反馈的三个问题。当前不改代码，先把现象、证据和判断边界固定下来。

### 8.1 问题一：从 Safari 打开，无法进入对应剧集

#### 用户实测

- 不经过 Facebook，直接在 Safari 打开落地页并点击 Open。
- iPhone 14 测试时没有进入 `movieId=10665`、`episodeNum=1` 对应的剧集。
- 当前体验至少不是“打开链接后直接拉起 App 并进入目标剧集”。

#### 已确认的网络行为

对同一 Adjust tracker 使用 iOS Safari User-Agent 请求时，Adjust 返回的是中间 HTML 页面，页面直接执行 App Store fallback：

```text
window.location.href = "https://apps.apple.com/us/app/yogotv/id6751373638";
```

在这条 Safari 响应中，没有观察到 Facebook UA 响应里用于尝试自定义 Scheme 的隐藏 iframe：

```text
<iframe id="deeplink-iframe" ...></iframe>
...
deeplink-iframe.src = "com.yogotv.app://open?...";
```

因此当前最可信的解释是：

```text
Safari
  -> 落地页
  -> app.adjust.com
  -> Adjust 的 Safari 响应
  -> App Store fallback
```

也就是说，Safari 这条链路目前没有可靠地把 `movieId` 和 `episodeNum` 送进 App。它不是已经进入 App 后剧集路由失败，而是更早的“唤端/传递深链”阶段就没有完成。

#### 判断边界

如果后续实测发现 App 实际已经被打开，只是没有进入目标剧集，则还要单独检查 AppDelegate 的 Scheme 接收、冷启动 deep link 保存和 `/play` 路由；但目前“没有打开对应剧集”的主要证据指向 Adjust Safari fallback 没有尝试唤端。

### 8.2 问题二：Facebook 内置浏览器出现 Adjust 中间页和系统确认框

#### 用户看到的界面

截图 1：iOS 提示“此网页试图打开 Facebook 以外的应用”，需要用户确认离开 Facebook。

![截图 1：Facebook 内置浏览器尝试打开外部 App](/var/folders/p0/tm9g8qq93j56f360bx913xb80000gn/T/codex-clipboard-1bfa8a70-7751-476c-9900-44124ac717b0.png)

截图 2：Adjust 中间页显示 `Yogo - ios`、`DOWNLOAD APP` 和 `Please press the button to proceed to your app`。

![截图 2：Adjust iOS 中间页](/var/folders/p0/tm9g8qq93j56f360bx913xb80000gn/T/codex-clipboard-72619f3e-c11a-4f4c-82d6-b997e8933b47.png)

#### 当前实际链路

Facebook UA 下，`app.adjust.com/22o1da5v` 返回的 HTML 包含：

1. 页面先展示 Adjust 中间页。
2. 大约 500ms 后，通过隐藏 iframe 尝试：

   ```text
   com.yogotv.app://open?movieId=10665&episodeNum=1&adjust_reftag=...
   ```

3. 如果没有成功唤端，大约 2 秒后跳转 App Store。
4. iOS 认为这是 Facebook 页面尝试打开外部 App，因此显示“退出 Facebook/打开应用”的系统确认框。

这两个截图不是两个独立的归因流程，而是同一条“Facebook -> Adjust 中间页 -> 自定义 Scheme -> iOS 外部 App 确认”的链路状态。它之所以看起来不像对方的直接跳转，是因为当前 Yogo 把唤端动作放在了 Adjust 中间页里；对方页面则更多是在落地页或 SDK/Universal Link 层完成唤端。

#### 这能说明什么

- 当前确实不是 Facebook 点击后直接拉起 App，而是先跨域进入 Adjust，再由 Adjust 延迟尝试 Scheme。
- iOS 系统确认框是跨 App 打开行为的直接结果。
- Adjust 中间页出现本身不能证明归因失败；它只说明当前唤端方式经过了 Adjust 的中间页。
- 即使用户最后成功打开 App，也仍需另外验证 `movieId=10665`、`episodeNum=1` 是否被 App 接收并路由到目标剧集。

### 8.3 问题三：ATT 权限表现不同，但服务端收到的归因数据是 Organic

#### 用户提供的两组日志

两组日志都请求：

```text
POST https://i.yogoshort.com/api/login/token
```

关键字段完全相同：

```json
{
  "ad_id": "077549742866dab140e42a52670d0cd7",
  "ad_attr_info": {
    "trackerToken": "22qdy9rw",
    "trackerName": "Organic",
    "network": "Organic",
    "campaign": "",
    "adgroup": "",
    "creative": "",
    "clickLabel": "",
    "costType": "",
    "costAmount": "null",
    "costCurrency": "",
    "fbInstallReferrer": null
  },
  "package_name": "com.yogotv.app",
  "app_version": "1.0.8",
  "app_code": "4"
}
```

#### 已确认结论

- 两组日志是相同的，不能用它们证明“拒绝追踪”和“允许追踪”在服务端产生了不同结果。
- `trackerName=Organic`、`network=Organic` 且 campaign/adgroup/creative 为空，说明这一次发送 `login/token` 时，Adjust SDK 给 App 的当前归因结果是 Organic。
- `ad_id` 是 Adjust 的 Adid，不是 IDFA；相同的 `ad_id` 不能证明 ATT 权限相同，也不能证明 ATT 已授权。
- `22qdy9rw` 是当前 App 上报的 Organic tracker，不能当作本次广告 tracker `22o1da5v` 的 campaign 归因结果。
- 目前没有证据表明这两组请求已拿到 Facebook 广告的 campaign、adgroup、creative 信息。

#### ATT 和 Adjust 归因不能混为一谈

ATT 权限回答的是“App 是否可以访问广告标识符相关能力”；Adjust 归因回答的是“这次安装是否匹配到了某个点击/广告来源”。因此：

```text
允许 ATT  !=  一定得到 Facebook campaign 归因
拒绝 ATT  !=  一定只能得到 Organic
```

当前 Organic 结果更直接指向“点击到安装的匹配、Deferred Deep Link、Adjust 配置/环境，或归因回调时序没有完成”，而不是单凭 ATT 弹窗就能解释。

#### 当前 App 的时序风险

当前代码存在“先用当前结果登录，再等待后续归因更新”的可能时序：

| 阶段 | 当前行为 | 风险 |
|---|---|---|
| ATT | `Global.initTracking()` 请求 ATT | 不同设备可能返回 authorized/denied/notDetermined |
| Adjust 初始化 | ATT 请求完成后才初始化 Adjust | 初始化时间受系统权限流程影响 |
| 首次取归因 | 最多等待约 3 秒取 Adid/Attribution | 3 秒内仍可能只有 Organic/空结果 |
| 首次登录 | `login/token` 发送当时的 `ad_attr_info` | 可能先把 Organic 写入服务端 |
| 后续回调 | attribution callback 再保存结果并尝试 refresh token | 需要确认回调是否到达、refresh 是否成功 |

相关代码位置：

- ATT 请求：[global.dart](/Users/admin/Documents/JJ-TV/repos/tv-app/lib/global.dart:120)
- Adjust 初始化和首次取归因：[adjust_tracking.dart](/Users/admin/Documents/JJ-TV/repos/tv-app/lib/adjust_tracking.dart:34)
- 启动阶段等待和恢复登录：[main.dart](/Users/admin/Documents/JJ-TV/repos/tv-app/lib/main.dart:456)
- 首次发送当前归因：[global.dart](/Users/admin/Documents/JJ-TV/repos/tv-app/lib/global.dart:600)
- 接收并保存 Adjust attribution callback：[adjust_tracking.dart](/Users/admin/Documents/JJ-TV/repos/tv-app/lib/adjust_tracking.dart:242)
- 后续刷新 token：[global.dart](/Users/admin/Documents/JJ-TV/repos/tv-app/lib/global.dart:672)

这里暂时只记录风险，不把它定性为已经确认的代码 Bug。现有服务端日志没有展示 callback 和 refresh 的完整时间序列。

### 8.4 三个问题的边界

| 现象 | 当前最可能所在层 | 现有证据能证明什么 | 不能证明什么 |
|---|---|---|---|
| Safari 不进目标剧 | Adjust Safari fallback / iOS 唤端链路 | Safari 响应直接走 App Store，未观察到 Scheme iframe | 不能单凭此断定 App 内部路由一定有 Bug |
| Facebook 出现 Adjust 中间页/确认框 | Facebook 内置浏览器 + Adjust 中间页 + Scheme | Adjust 延迟 iframe 调 Scheme，iOS 弹外部 App 确认 | 不能仅凭中间页断定点击归因失败 |
| App 上报 Organic | Adjust 安装归因/回调/服务端同步 | 当前 `login/token` 上报的是 Organic，广告字段为空 | 不能用 `ad_id` 或 ATT 弹窗单独证明授权/拒绝原因 |

### 8.5 后续验证顺序（仍然不改代码）

1. 在同一台 iPhone 上分别测试：App 已安装和未安装时，从 Safari 点击；记录是否打开 App、是否进入 `10665/1`、最终是否落到 App Store。
2. 在 Safari 的真实用户点击事件中直接测试 `com.yogotv.app://open?movieId=10665&episodeNum=1`，先把“App Scheme 本身能否唤端”与“Adjust 中间页是否能唤端”分开。
3. 在 Facebook 内置浏览器记录完整视频/时间线：落地页、Adjust 中间页、系统确认框、App 是否打开、打开后是否进目标剧集。
4. 做一次干净的 Adjust 归因测试：删除 App、确认设备不是旧安装状态、从同一个广告 tracker 点击并完成安装，等待 attribution callback，再查看首次和后续 `login/token` 请求。
5. 同时记录 ATT 状态、Adjust attribution callback 原始内容、Adid、deep link callback、首次登录时间和 refresh 请求；不要只看最终的一条 `login/token` 日志。
6. 在 Adjust 后台单独核对 token `22o1da5v` 的 Click、iOS Deep Link、安装匹配和 fallback 配置；服务端出现 `22qdy9rw / Organic` 只能说明 App 当时拿到的是 Organic 结果。

## 9. 三个对标页面的代码复核与可借鉴方案

本节不是根据页面现象猜流程，而是根据下载到的 HTML/JS 逐段核对后的结果。

### 9.1 对标一：`w2a.shorttv.live`

关键代码：

- 页面初始化自有 DeepLink SDK：[fb02.html](/Users/admin/Downloads/w2a.shorttv.live/w2a.shorttv.live/v6/3/fb02.html:332)
- 点击入口：[index02.js](/Users/admin/Downloads/w2a.shorttv.live/w2a.shorttv.live/v6/3/js/index02.js:458)
- 组装 iOS/Android App URL：[index02.js](/Users/admin/Downloads/w2a.shorttv.live/w2a.shorttv.live/v6/3/js/index02.js:345)
- 点击归因并触发唤端：[index02.js](/Users/admin/Downloads/w2a.shorttv.live/w2a.shorttv.live/v6/3/js/index02.js:378)
- Scheme fallback：[dlink-new.js](/Users/admin/Downloads/w2a.shorttv.live/w2a.shorttv.live/v6/3/lib/dlink-new.js:709)

实际流程：

```text
点击
  -> 读取 cookieId/clickId
  -> 写入 clipboard 备用信息
  -> 上报 reportV5
  -> deeplink SDK 上报 JumpToTarget
  -> SDK 返回 appUrl
  -> window.location.href = appUrl
```

代码里的关键点：

- 生产环境使用配置下发的 `appLinks[type]`，不是直接跳 Adjust 中间页。
- iOS App URL 携带 `shortid`、`attr`、`ppid` 等内容参数。
- `JumpToTarget` 的上报发生在跳转前，并且带有 `app_clickId`、`ppid`、`referrer`、`ttp`。
- TikTok 内置浏览器分支会直接使用 `shorttv://...`，失败后 3 秒跳商店；页面隐藏或卸载时清除 fallback 定时器。
- 下载代码本身没有证明其 HTTPS `appLinks` 一定是 Universal Link；这需要再查其线上域名的 AASA/苹果配置。

可借鉴部分：

1. 把“点击归因上报”和“唤端”拆成两个动作。
2. 唤端 URL 明确携带剧集标识和点击标识，而不是只把广告参数留在 H5 URL 上。
3. fallback 由页面控制，并在 App 成功唤起后取消。

不能直接照搬：

- `deeplink.dev` 是对方自己的 SDK 和后端，Yogo 没有同样的服务端协议。
- 对方的 `shortid`、`ppid`、`app_clickId` 不是 Yogo 的 `movieId`、Adjust token 和 campaign 字段。

### 9.2 对标二：`dramacps.top`

关键代码：

- 组装 AppsFlyer OneLink：[script.client.4xEMPr_U.js](/Users/admin/Downloads/dramacps.top/dramacps.top/app/_astro/script.client.4xEMPr_U.js:2721)
- 点击/自动跳转控制：[script.client.4xEMPr_U.js](/Users/admin/Downloads/dramacps.top/dramacps.top/app/_astro/script.client.4xEMPr_U.js:11017)
- 落地页自身的归因数据上报：[CPS-2075501067421347840.html](/Users/admin/Downloads/dramacps.top/dramacps.top/app/CPS-2075501067421347840.html:375)
- 实际保存到的 OneLink 请求：[qJ7j.html](/Users/admin/Downloads/dramacps.top/stardusttv.onelink.me/qJ7j.html:1)

实际流程：

```text
页面加载/点击
  -> su() 生成 stardusttv.onelink.me/qJ7j
  -> 填入 deep_link_value、af_dp、fbclid、link_id、w2a_uid
  -> ao() 上报落地页跳转信息
  -> window.location.href = OneLink
  -> OneLink/AppsFlyer 配置决定唤端或商店及安装后的 Deferred Deep Link
```

代码里的关键点：

- 前端没有直接写 `shanhai://...` 到 `window.location.href`。
- `deep_link_value` 和 `af_dp` 被写进 AppsFlyer OneLink；保存的请求中确实能看到这两个字段。
- OneLink 的最终唤端、商店 fallback 和安装后深链由 AppsFlyer 的 Smart Script/OneLink 配置负责。
- 点击既支持用户点击，也支持 `jumpTime` 到时自动跳转，默认约 2 秒。
- 页面另外把 `campaign_name`、`campaign_id`、`ad_set_id`、`ad_id`、`fbclid` 等发到自有 `san-api`，这是自有数据链路，不等于 AppsFlyer 归因回调。

可借鉴部分：

1. 深链平台链接是唯一的跳转入口，前端只负责把剧集深链值和广告字段拼入 OneLink。
2. 让平台配置负责“已安装唤端、未安装商店、安装后 Deferred Deep Link”，避免前端自己同时实现多套中间页逻辑。
3. 用 `link_id`/`w2a_uid` 记录一次落地页实例，便于把 H5 点击和 App 安装串起来。

不能直接照搬：

- Yogo 当前使用的是 Adjust，不是 AppsFlyer；`deep_link_value`、`af_dp` 不能直接作为 Adjust 参数。
- 对方的 `san-api` 上报字段和 Yogo 的 `login/token` 无法直接互换。

### 9.3 对标三：`www.dramawavew2a.com`

关键代码：

- 组装 Adjust/AppsFlyer 链接：[fb_tt_drama_campaign.js](/Users/admin/Downloads/www.dramawavew2a.com/cdn.usrgrow.com/js/fb_tt_drama_campaign.js:206)
- 把链接作为图片请求发送：[fb_tt_drama_campaign.js](/Users/admin/Downloads/www.dramawavew2a.com/cdn.usrgrow.com/js/fb_tt_drama_campaign.js:150)
- 打开商店并同时发送 OneLink 请求：[fb_tt_drama_campaign.js](/Users/admin/Downloads/www.dramawavew2a.com/cdn.usrgrow.com/js/fb_tt_drama_campaign.js:159)
- 页面加载时预发链接：[fb_tt_drama_campaign.js](/Users/admin/Downloads/www.dramawavew2a.com/cdn.usrgrow.com/js/fb_tt_drama_campaign.js:251)
- 保存到的 AppsFlyer OneLink 请求：[e1bu.html](/Users/admin/Downloads/www.dramawavew2a.com/dramawave.onelink.me/e1bu.html:1)

实际流程：

```text
页面加载
  -> R2() 生成并通过 img 请求 OneLink/Adjust 链接

点击
  -> 打开 t.st（商店/配置的目标地址）
  -> 再通过 img 请求 t.lk

链接参数
  -> deep_link_value = dramawave://dramawave.app?redirect=/detail?... 
  -> af_dp 同样携带该 Scheme
```

代码里的关键点：

- Adjust 分支会拼 `campaign`、`adgroup`、`creative`、`adj_*`，并根据配置决定是否加 `redirect`。
- AppsFlyer 分支会拼 `deep_link_value` 和 `af_dp`，值是自定义 Scheme 加详情页参数。
- `RL()` 使用 `img.src = oneLink` 预发平台点击请求。
- `its()` 的页面动作是 `window.open(t.st)`；当脚本参数为 `r=2` 时，`t.st` 就是完整 Adjust/AppsFlyer 平台链接，而不是前端直接执行 `dramawave://...`。
- 因此已安装时是否打开 App、未安装时是否进入 Apple Store，取决于 `t.st` 对应的平台链接及其后台配置；前端负责进入平台链接，不自行判断安装状态。

可借鉴部分：

1. 归因链接可以用图片请求触发，避免页面顶层先进入 Adjust 中间页。
2. `deep_link_value`/`af_dp` 中同时携带剧集路径和广告上下文，平台负责安装后的回传。
3. Adjust 的 campaign/adgroup/creative 仍然作为链接参数明确传递。

风险和限制：

- 图片请求能证明浏览器发出了链接请求，但不能单凭前端代码证明 Adjust 已完成安装归因。
- 这种方案依赖第三方请求、浏览器隐私策略和平台后台配置，必须用同一台真实 iPhone 做“点击—卸载—安装—首次启动”验证。

### 9.4 三个对标共同说明的结论

| 结论 | 对标证据 | 对 Yogo 的含义 |
|---|---|---|
| 不把顶层 Adjust 中间页当作唤端页面 | 对标一直接 SDK/App Link；对标二直接 OneLink；对标三用 img 请求链接 | Yogo 当前 `window.location.href = app.adjust.com/...` 是失败体验的主要结构差异 |
| 点击归因和 App 唤端分层 | 对标一先 `JumpToTarget`，对标二先生成 OneLink， 对标三先 `img.src` | Yogo 需要验证“Adjust 点击请求”和“直接进入 App”能否分开完成 |
| 剧集参数放进平台深链值 | 对标一 `shortid`/`attr`，对标二 `deep_link_value`，对标三 `deep_link_value`/`af_dp` | Yogo 要保证 `movieId=10665`、`episodeNum=1` 在平台深链和 App 路由都有闭环 |
| fallback 与平台配置配合 | 对标一页面 3 秒 fallback；对标二 OneLink；对标三 `t.st` | 不能只改 H5 参数名，必须核对 Adjust token 的 iOS destination/deep link 配置 |

### 9.5 基于对标的 Yogo 解决路线

#### 第一优先级：先按对标二的“平台链接单入口”验证 Adjust 配置

先不改前端唤端算法，使用同一个 `22o1da5v` 验证 Adjust 后台是否满足：

1. iOS App destination 已绑定 `com.yogotv.app` 对应的 App Store App。
2. iOS Deep Link/App Scheme 配置与 `com.yogotv.app://open` 一致。
3. `deep_link` 中包含 `movieId=10665`、`episodeNum=1`。
4. 已安装 App、未安装 App、Facebook 内置浏览器、Safari 的结果分别符合预期。
5. 安装后 Adjust SDK 能回调同一个 deep link，并且 attribution callback 不再是 `Organic`。

如果这一步不能让 Safari/FB 正常唤端，就说明当前 token 的平台配置或 Adjust iOS 链接能力与对标二的 OneLink 配置不同，不能继续只调整 H5 参数名。

#### 第二优先级：按对标三验证“链接请求与顶层导航分离”的实验分支

这可以作为本地/测试环境实验，不直接上线：

- 用 `img.src` 或同等方式发送 Adjust tracker 请求，观察 Adjust Click 是否增加。
- 随后单独执行 Yogo Scheme/Universal Link 唤端。
- 记录 App 是否打开、App 是否收到 `movieId/episodeNum`、Adjust 是否收到 SDK deep link click、服务端是否最终拿到 campaign。

只有这四项同时通过，才有资格考虑把它作为 Yogo 的生产链路。否则不能因为对标三使用了图片请求，就认定图片请求一定能完成 Yogo 的安装归因。

#### 第三优先级：补齐 App 侧可观测性后再打本地包

本地包必须能打印以下完整时间线，才能判断“ATT 问题”和“Organic 问题”是否相关：

```text
ATT status
Adjust init
Adid
attribution callback
direct/deferred deep link callback
login/token 首次请求
login/token attribution refresh 请求
movieId/episodeNum 路由结果
```

当前最安全的执行顺序是：先完成 Adjust token 配置核对和对标代码验证，再决定是否采用对标三的分离请求实验；确认链路后才修改代码并打本地 iOS 包。

## 10. 新增对标：`www.dramawavew2a.com/ads/0/2049/view`

本次新增页面的本地代码目录：

`/Users/admin/Downloads/www.dramawavew2a.com (1) 2`

入口页面：[view.html](</Users/admin/Downloads/www.dramawavew2a.com (1) 2/www.dramawavew2a.com/ads/0/2049/view.html>)

外部脚本：[fb_tt_drama_campaign.js](</Users/admin/Downloads/www.dramawavew2a.com (1) 2/cdn.usrgrow.com/js/fb_tt_drama_campaign.js>)

### 10.1 页面实际配置

入口页面内嵌的配置在：[view.html](</Users/admin/Downloads/www.dramawavew2a.com (1) 2/www.dramawavew2a.com/ads/0/2049/view.html:364>)

关键字段：

```text
tp: 0
l: https://dramawave.onelink.me/e1bu?... 
dl: dramawave://dramawave.app?redirect=%2Fdetail%3Fid%3DAg0rfr5F0F
c: yingliang_post_CLV_VL_gaoyuan_1785814911_none_en_Her Beast__702885
adset: Drama Switch
adset_id: 1011843385335542
ad_id: 12124551390
site_id: 2049
```

这里的 `af_dp=Ag0rfr5F0F` 是页面请求中的内容 ID。页面服务端再把它转换为 `link[0].dl` 里的自定义 Scheme，并把详情 ID 放进：

```text
dramawave://dramawave.app?redirect=/detail?id=Ag0rfr5F0F
```

### 10.2 点击前后的真实流程

#### 页面加载

入口页面加载外部脚本后，会执行 `initializeClipboard()`：[view.html](</Users/admin/Downloads/www.dramawavew2a.com (1) 2/www.dramawavew2a.com/ads/0/2049/view.html:1046>)

页面加载阶段会发送：

- 页面浏览 Beacon 到 `trace.mydramawave.com/yl/clip-content-report`。
- `onelink_view` 请求到 `business.yingliangads.com/log/onelink_view`。

这说明对方在用户点击前就开始记录 OneLink/深链曝光信息。

#### 生成深链数据

`buildDeeplink()` 会先生成 OneLink 请求：[view.html](</Users/admin/Downloads/www.dramawavew2a.com (1) 2/www.dramawavew2a.com/ads/0/2049/view.html:890>)

AppsFlyer 分支会把以下信息写入 OneLink：

- `pid`
- `af_sub1` 到 `af_sub5`
- `c`
- `af_c_id`
- `af_ad`、`af_ad_id`
- `af_adset`、`af_adset_id`
- `af_channel`
- `deep_link_value`
- `af_dp`

对应代码：[fb_tt_drama_campaign.js](</Users/admin/Downloads/www.dramawavew2a.com (1) 2/cdn.usrgrow.com/js/fb_tt_drama_campaign.js:233>)

然后 `buildDeeplinkString()` 生成一段文本形式的深链数据：

```text
1 https://mydramawave.com?redirect=%2Fdetail%3Fid%3DAg0rfr5F0F&pid=...&c=...&af_adset=...
```

这段文本不是页面直接执行的 Scheme，而是后面用于 Beacon 和剪贴板的 payload。

#### 用户点击

点击处理函数在：[view.html](</Users/admin/Downloads/www.dramawavew2a.com (1) 2/www.dramawavew2a.com/ads/0/2049/view.html:1001>)

执行顺序：

```text
点击
  -> Facebook/TikTok Download/ViewContent 事件
  -> sendBeacon(onelink_click, clip_content)
  -> 写入剪贴板：clip_content + 时间戳
  -> sendBeacon(write_clip)
  -> sendBeacon(page_click)
  -> window.location.href = n.st
```

### 10.3 这个项目如何打开 App、跳 Apple Store并归因？

这份代码已经能确认完整的平台入口，之前把 `r=2` 分支中的 `st` 判断为空是错误的，现更正如下：

1. 入口配置中的 `tp=0` 选择 AppsFlyer。
2. 外部脚本参数 `?r=2` 使 AppsFlyer 分支执行 ``o = `${a}` ``；其中 `a` 是拼好全部广告参数的完整 OneLink：[fb_tt_drama_campaign.js](</Users/admin/Downloads/www.dramawavew2a.com (1) 2/cdn.usrgrow.com/js/fb_tt_drama_campaign.js:233>)
3. 因此 `n.st` 不是空值，而是 `https://dramawave.onelink.me/e1bu?...`。
4. 点击最后执行 `window.location.href = n.st`，浏览器顶层进入 OneLink：[view.html](</Users/admin/Downloads/www.dramawavew2a.com (1) 2/www.dramawavew2a.com/ads/0/2049/view.html:1019>)
5. OneLink GET 记录 AppsFlyer 点击归因；链接中的 `deep_link_value` 和 `af_dp` 携带 `dramawave://.../detail?id=Ag0rfr5F0F`。
6. 本地抓取目录中同时保存到了 [AppsFlyer OneLink 请求](</Users/admin/Downloads/www.dramawavew2a.com (1) 2/dramawave.onelink.me/e1bu.html:1>) 和 [Apple Store 落地页](</Users/admin/Downloads/www.dramawavew2a.com (1) 2/apps.apple.com/US/app/dramawave-dramas-reels/id6670430706.html:1>)，证明该次链路由 OneLink继续跳到了 Apple Store。

准确流程是：

```text
广告落地页点击
  -> 自有 click 日志 + 剪贴板备份
  -> 浏览器顶层进入 AppsFlyer OneLink（记录平台点击归因）
  -> 已安装：由 AppsFlyer/iOS 打开 App，并交付剧集深链
  -> 未安装：AppsFlyer 跳 Apple Store；首次启动后由 SDK 尝试交付 Deferred Deep Link
```

这里 `as=""` 不会造成目标为空，因为 `r=2` 明确选择完整 OneLink `a`；只有其他分支才直接使用 `u.as`。

### 10.4 对 Yogo 的可借鉴点

可以借鉴：

- 页面加载时记录 view，点击时记录 click，且二者使用同一份深链 payload。
- 深链 payload 同时携带剧集 ID 和广告上下文，而不是只保存 `fbclid`。
- 使用 `navigator.sendBeacon` 发送点击日志，避免顶层跳转前请求未完成。
- 通过 `link_id`/内容 ID把落地页内容和广告点击绑定起来。

不能直接借鉴：

- 剪贴板方案没有证明能解决 iOS 已安装 App 的直接唤端；还会受 iOS 剪贴板隐私提示和 Facebook 容器限制影响。
- `deep_link_value`、`af_dp` 是 AppsFlyer 字段，不能直接塞进 Yogo 的 Adjust 流程当作同义参数。
- 本地文件只能证明 OneLink 请求和跳 Apple Store确实发生，不能仅凭 H5 文件证明安装后 AppsFlyer SDK 最终回传成功；这一步仍需真机和后台数据闭环验证。
- 可以借鉴“顶层进入有效平台链接”的结构，但不能照搬 AppsFlyer 字段到 Adjust。

### 10.5 与 Yogo 当前问题的直接对照

| 项目 | 新页面 | Yogo 当前页面 |
|---|---|---|
| 点击归因 | 顶层 OneLink GET；`sendBeacon(onelink_click)` 是自有辅助日志 | 顶层跳转 Adjust tracker |
| 深链保存 | `deep_link_value`/`af_dp` + 剪贴板 | `deep_link`/`deeplink` 放在 Adjust URL |
| App/商店分流 | `n.st` 是完整 AppsFlyer OneLink，由 AppsFlyer/iOS 决定打开 App 或去商店 | Facebook 下先进入 Adjust 中间页，再由 Adjust 尝试打开 App或去商店 |
| 未安装 fallback | 本地抓取已保存到 Apple Store 页面 | Adjust 页面约 2 秒后 App Store |
| 安装后传递 | 依赖 AppsFlyer/剪贴板/App 侧 | 依赖 Adjust attribution/deferred deep link callback |

这个新项目明确使用“平台链接单入口”：点击进入 OneLink，同时完成平台点击归因，再由平台处理 App/Apple Store 分流。剪贴板和自有 Beacon 是补充链路，不是 AppsFlyer 归因本身。

## 11. 对方发送归因的准确链路与 Yogo 剪贴板实现

### 11.1 对方不是只靠剪贴板归因

对方页面实际存在三条独立的数据链路。

#### 第一条：AppsFlyer OneLink 点击请求

外部脚本的 `R2()` 在页面加载后调用 `RL()`：[fb_tt_drama_campaign.js](</Users/admin/Downloads/www.dramawavew2a.com (1) 2/cdn.usrgrow.com/js/fb_tt_drama_campaign.js:251>)

`RL()` 使用图片请求访问完整 OneLink：[fb_tt_drama_campaign.js](</Users/admin/Downloads/www.dramawavew2a.com (1) 2/cdn.usrgrow.com/js/fb_tt_drama_campaign.js:150>)

```js
let image = document.createElement("img");
image.src = oneLinkUrl;
```

OneLink URL 中已经包含：

```text
pid
campaign / campaign_id
adset / adset_id
ad / ad_id
channel
fbp / fbc
deep_link_value
af_dp
```

本地抓取结果中存在实际请求文件：[e1bu.html](</Users/admin/Downloads/www.dramawavew2a.com (1) 2/dramawave.onelink.me/e1bu.html:1>)。这条 GET 才是发给 AppsFlyer 的平台归因点击请求。

#### 第二条：对方自己的 view/click 日志

页面使用 `navigator.sendBeacon` 向自己的服务发送 JSON：[view.html](</Users/admin/Downloads/www.dramawavew2a.com (1) 2/www.dramawavew2a.com/ads/0/2049/view.html:996>)

接口包括：

```text
https://business.yingliangads.com/log/onelink_view
https://business.yingliangads.com/log/onelink_click
https://trace.mydramawave.com/yl/clip-content-report
```

请求体格式核心是：

```json
{
  "clip_content": "剧集 ID + campaign/adset/ad + 点击标识 + 时间戳"
}
```

这条链路用于对方自己的曝光、点击、写剪贴板和页面事件核对，不等同于 AppsFlyer attribution callback。

#### 第三条：Facebook/TikTok 像素事件

用户点击时还会发送：

```text
fbq("track", "ViewContent", ...)
ttq.track("Download", ...)
```

对应代码：[view.html](</Users/admin/Downloads/www.dramawavew2a.com (1) 2/www.dramawavew2a.com/ads/0/2049/view.html:1005>)

这用于广告平台事件优化，也不能替代 AppsFlyer 的安装归因。

### 11.2 剪贴板在对方流程中的作用

点击时，对方把同一份 `clip_content` 写入剪贴板：[view.html](</Users/admin/Downloads/www.dramawavew2a.com (1) 2/www.dramawavew2a.com/ads/0/2049/view.html:1011>)

剪贴板的作用是给安装后的 App 一个额外的剧集/广告上下文传递通道。它本身不会在 AppsFlyer 后台生成 attribution；真正的平台点击仍由 OneLink GET 请求产生。

剪贴板内容并非没有 Facebook 信息，只是没有使用 `fbclid` 这个字段名：

- `_fbp` 被放进 `af_sub1`。
- `_fbc` 被放进 `af_sub2`。
- `deep_link_value`/`af_dp` 内又写入 `fbp` 和 `fbc`。
- `_fbc` 的格式是 `fb.1.<timestamp>.<fbclid>`，所以原始 `fbclid` 位于 `fbc` 的末段。

对应代码：[fb_tt_drama_campaign.js](</Users/admin/Downloads/www.dramawavew2a.com (1) 2/cdn.usrgrow.com/js/fb_tt_drama_campaign.js:218>)。本地保存的 [OneLink 请求](</Users/admin/Downloads/www.dramawavew2a.com (1) 2/dramawave.onelink.me/e1bu.html:1>) 中，`af_sub1`、`af_sub2`、`fbp`、`fbc` 均有实际值。

当前下载内容没有对方 App 端读取剪贴板的代码，因此只能确认 H5 已经写入，不能确认 App 端如何解析、何时读取以及是否成功回传。

### 11.3 Yogo 本地草稿已加入剪贴板 payload（线上尚未部署）

Yogo 本地文件已在 Open 点击时生成并写入 JSON payload：

来源：[app-share.html](/Users/admin/Documents/JJ-TV/repos/slot-TV/op_new/app-share.html:630)

格式：

```json
{
  "version": 1,
  "type": "yogo_attribution",
  "movieId": "10665",
  "episodeNum": "1",
  "deepLink": "com.yogotv.app://open?...",
  "adjust": {
    "trackerToken": "22o1da5v",
    "campaign": "tf (120247630333670133)",
    "adgroup": "10665 - IOS (120247630333650133)",
    "creative": "10665-11 (120247630333660133)",
    "fbclid": "..."
  },
  "tracking": {
    "fbclid": "...",
    "fbc": "...",
    "fbp": "...",
    "utm_source": "fb",
    "utm_medium": "paid",
    "utm_campaign": "120247630333670133",
    "utm_content": "120247630333660133",
    "utm_term": "120247630333650133"
  },
  "createdAt": 1785915811630
}
```

写入时先使用同步的隐藏 textarea + `document.execCommand("copy")`，失败时再尝试 `navigator.clipboard.writeText`：[app-share.html](/Users/admin/Documents/JJ-TV/repos/slot-TV/op_new/app-share.html:660)

调用发生在 `openApp()` 的用户点击上下文内，并位于任何页面跳转之前：[app-share.html](/Users/admin/Documents/JJ-TV/repos/slot-TV/op_new/app-share.html:792)

广告分支会从 localStorage/cookie 补充 `_fbc` 和 `_fbp`；`fbp` 的新增读取只在 Adjust 广告参数组装中生效，不改变无广告 Deep Link：[app-share.html](/Users/admin/Documents/JJ-TV/repos/slot-TV/op_new/app-share.html:596)

### 11.4 当前边界

- 该剪贴板实现目前只存在于本地未提交草稿；线上 `https://yogoshort.com/op_new/app-share.html` 尚无 `buildAttributionClipboardPayload`/`writeAttributionClipboard`，线上测试不会得到这份 JSON。
- App 目前还没有为这份 `yogo_attribution` JSON 增加读取和消费逻辑。
- 写入剪贴板不会自动解决 Adjust 的 `Organic` 问题。
- Yogo 仍需保留 Adjust tracker 点击请求，才能验证 Adjust 是否记录 Click 和安装归因。
- 后续 App 端读取时必须校验 `type`、`version`、时间戳和剧集 ID，且读取后去重，避免旧剪贴板反复打开旧剧集。

### 11.5 改造范围：仅广告归因入口

明确约束：自然量/无广告参数页面必须保持原流程，不写归因剪贴板、不额外请求 Adjust，也不改变原有 App/商店跳转。

本地草稿现已增加门控：只有同时存在剧集 `id` 且能从 `adjust_tracker_url`/`adjust_token` 解析出有效 token 时，才调用 `writeAttributionClipboard(...)`。`campaign`、`adgroup`、`creative`、`fbclid`、UTM 只作为附加广告上下文，不能仅凭普通剧集 `id` 判断为广告流量。

```text
无 Adjust tracker/token
  -> 完全执行原有流程

有有效 Adjust tracker/token
  -> 写广告归因 payload
  -> 用户浏览器通过隐藏图片直接请求 Adjust，记录点击
  -> 前台执行 Yogo iOS Scheme
  -> 2 秒内 App 未打开则自动进入 Apple Store
```

## 12. Yogo iOS/Android 浏览器直报 Adjust 的本地实现与验证

### 12.1 实现流程

带有效 Adjust token 的 iOS/Android 点击不再执行 `window.location.href = app.adjust.com/...`。当前本地实现为：

```text
Open 点击
  -> 写归因剪贴板
  -> new Image().src = Adjust tracker URL
     （用户浏览器直接请求 Adjust，不经过 Yogo 后端）
  -> iOS: window.location.href = com.yogotv.app://open?movieId=...&episodeNum=...
  -> Android: window.location.href = open://yogo.com/movie?movieId=...&episodeNum=...
  -> visibilitychange/pagehide 表示 App 已打开，取消 fallback
  -> 2 秒内页面仍可见，自动跳 Apple Store
```

浏览器后台 Adjust 请求：[app-share.html](/Users/admin/Documents/JJ-TV/repos/slot-TV/op_new/app-share.html:730)

iOS/Android 点击分流：[app-share.html](/Users/admin/Documents/JJ-TV/repos/slot-TV/op_new/app-share.html:800)

### 12.2 参数统一

`collectAdjustAttributionParams()` 统一组装 Adjust URL、前台 App Deep Link和剪贴板使用的广告上下文：[app-share.html](/Users/admin/Documents/JJ-TV/repos/slot-TV/op_new/app-share.html:596)

已包含：

- tracker token / `adjust_t`
- campaign、adgroup、creative
- fbclid、fbc、fbp
- `adj_sub1 = fbp`
- `adj_sub2 = fbc`
- UTM 和剧集 ID/集数

Adjust tracker 的 `deep_link`/`deeplink` 与前台实际执行的 Yogo Scheme 使用同一个 URL；剪贴板中的 `deepLink` 也与其一致。

token 不是写死值，按以下优先级解析：

1. 外层 `adjust_token`。
2. 外层 `adj_t` 或 `adjust_t`。
3. `adjust_tracker_url`/`adjust_url` 内层的 `adj_t` 或 `adjust_t`。
4. 老格式 `https://app.adjust.com/<token>` 的路径末段。

解析后仅接受字母、数字、下划线和连字符；缺失或非法 token 不进入广告归因分支。

### 12.3 自动化模拟结果

使用与正式测试链接相同的嵌套参数结构完成浏览器模拟，并完成 iOS/Android × 新旧 token格式矩阵，结果：

- 浏览器发出了 `https://app.adjust.com/22o1da5v?...` 图片请求。
- 当前页面保持在 `app-share.html`，没有顶层进入 Adjust。
- campaign/adgroup/creative/fbclid/fbp/fbc 均进入 Adjust 请求。
- iOS 前台 Scheme为 `com.yogotv.app:`，Android为 `open:`；二者均包含 `movieId=10665`、`episodeNum=1`、campaign 和 `adjust_t=22o1da5v`。
- `adjust_tracker_url`、`adjust_url`、`adjust_token`、`adj_t`、`adjust_t` 均通过解析测试。
- 非法 token不会发送 Adjust 请求。
- Adjust 内嵌 `deeplink`、前台 Scheme、剪贴板 `deepLink` 完全一致。
- fallback 是 Yogo Apple Store地址。
- 无广告入口发出的 Adjust 请求数为 0，剪贴板未变化，Deep Link仍为原始 Yogo剧集链接。

### 12.4 尚需真机/Adjust 后台确认

本地模拟证明浏览器请求、参数和前端分流正确，但不能代替以下验证：

1. Facebook iOS/Android 内置浏览器是否允许该图片请求完整到达 Adjust。
2. token `22o1da5v` 的 Adjust 后台是否新增 Click。
3. 已安装 App是否从 Facebook确认框后进入正确剧集。
4. ~~未安装时是否在约 2 秒后进入 Apple Store。~~ 真机已确认会被 Safari“网址无效”系统弹窗阻断，见第 13 节。
5. 卸载、Forget Device、点击、安装、首次打开后，Adjust 是否返回非 Organic campaign及 Deferred Deep Link。

## 13. 2026-08-10 真机结论与 Adjust 确定性验收模式

### 13.1 已确认：iOS 自定义 Scheme 失败会阻断商店 fallback

在 App 已卸载的 iPhone Safari 中点击当前本地落地页，系统立即显示：

```text
Safari 浏览器打不开该网页，因为网址无效。
```

触发地址是顶层的 `com.yogotv.app://open?...`。该系统弹窗出现后，网页中的 2 秒定时器不能按预期继续完成 App Store fallback。因此，“后台请求 Adjust + 顶层 Scheme + JavaScript 定时跳商店”不能作为 iOS 未安装场景的可靠正式方案。

这不是 Adjust 点击请求本身的错误，而是 iOS 自定义 Scheme 无法可靠判断 App 是否已安装。正式上线要做到“已安装直接进 App、未安装自然进入网页/商店”，仍需使用 HTTPS Universal Link，并完成 Adjust 平台配置、App Associated Domains 和域名关联。

### 13.2 本地真机验收不增加广告 URL 参数

本地验收链接继续使用原始广告参数，不增加任何测试字段。页面仅通过 `localhost`/局域网 IP 判断当前为本地测试环境。

只在同时具备有效 Adjust token 的本地 iOS 广告入口生效：

```text
用户点击 Open
  -> 写归因剪贴板
  -> 浏览器后台 GET https://app.adjust.com/<token>?campaign=...&deep_link=...
  -> 等待 1.2 秒，让点击请求先发出
  -> 直接进入 Yogo App Store
```

本地环境不会尝试 `com.yogotv.app://`，因此 App 未安装时不会再出现 Safari“网址无效”弹窗。它用于验证：

1. Adjust 是否收到 token `22o1da5v` 的点击。
2. 点击和首次打开能否由 Adjust 完成安装匹配。
3. Adjust SDK 是否向 App 返回 campaign/adgroup/creative。
4. Deferred Deep Link 是否在安装后首次打开时进入 `movieId=10665`、`episodeNum=1`。

由于链接不附加 IDFA，这不是 IDFA 确定性匹配测试；最终以 Adjust 点击数据、App attribution callback 和服务端 `ad_attr_info` 为准。它也不用于验证已安装 App 的直接唤端；该部分最终应由 Universal Link 验证。

实现位置：[app-share.html](/Users/admin/Documents/JJ-TV/repos/slot-TV/op_new/app-share.html)

### 13.3 官方验收依据

- Adjust Testing Console 文档要求在测试链接附加 iOS `idfa` 以进行设备匹配；同一链接两次点击至少间隔 60 秒，否则可能被识别为 click spam：<https://www.help.adjust.com/en/article/testing-console>
- Adjust Deferred Deep Link 的新用户测试顺序是：卸载 App、Testing Console Forget device、点击测试链接、安装 App、首次打开；预期结果是进入指定 App 内容：<https://help.adjust.com/en/article/test-adjust-deep-links>
- Adjust Universal Link 正式配置需要 iOS Bundle ID、App Prefix、App Scheme，并在 App 中加入 `applinks:<domain>` Associated Domain：<https://help.adjust.com/en/article/set-up-universal-links>
- Apple 说明 Universal Link 在已安装时可直接打开 App，未安装时仍是正常 HTTPS 网页；网站 AASA 与 App Associated Domains 共同建立关联：<https://developer.apple.com/library/archive/documentation/General/Conceptual/AppSearch/UniversalLinks.html>

### 13.4 当前测试目标

```text
目标: movieId=10665, episodeNum=1
Adjust token: 22o1da5v
```

本地验收不改变无 Adjust token 的自然量流程。

## 14. 采用对标组合方案后的实现（2026-08-10）

最终选择的是 ShortTV 与 DramaWave 的组合，不恢复 Adjust 顶层中间页：

```text
带 Adjust token 的 iOS Open 点击
  -> 写归因剪贴板
  -> 隐藏图片 GET Adjust tracker（记录点击）
  -> 顶层打开 https://www.yogoshort.com/open/index.html
       已安装且域名关联有效：iOS 打开 Yogo App
       未安装：网页立即进入 Apple Store
```

落地页实现：[app-share.html](/Users/admin/Documents/JJ-TV/repos/slot-TV/op_new/app-share.html)

商店 fallback 页面：[open/index.html](/Users/admin/Documents/JJ-TV/repos/slot-TV/open/index.html)

AASA 文件：[apple-app-site-association](/Users/admin/Documents/JJ-TV/repos/slot-TV/.well-known/apple-app-site-association)

iOS App 已增加：

- `applinks:yogoshort.com`
- `applinks:www.yogoshort.com`
- `NSUserActivityTypeBrowsingWeb` 接收与转发
- Flutter 对 `/open`、`/open/*` 的 `movieId`、`episodeNum` 路由解析

对应代码：[Runner.entitlements](/Users/admin/Documents/JJ-TV/repos/tv-app/ios/Runner/Runner.entitlements)、[AppDelegate.swift](/Users/admin/Documents/JJ-TV/repos/tv-app/ios/Runner/AppDelegate.swift)、[deep_link_handler.dart](/Users/admin/Documents/JJ-TV/repos/tv-app/lib/deep_link_handler.dart)

约束保持不变：没有 Adjust token 的自然量入口仍执行原来的 Scheme/fallback；Android 暂不改变。

### 14.1 部署前不能完成 Universal Link 真机验收

修改前核对结果：

- `https://yogoshort.com/.well-known/apple-app-site-association` 返回普通 HTML，不是 AASA JSON。
- `https://www.yogoshort.com/.well-known/apple-app-site-association` 返回普通 HTML，不是 AASA JSON。
- App 原签名没有 `com.apple.developer.associated-domains`。

修改后本地 Release 包已成功构建，最终签名包含正确的应用标识 `STXC8U7UJR.com.yogotv.app` 和两个 Associated Domains。

上线时必须同时发布以下三个文件，不能只上传落地页：

1. `/op_new/app-share.html`
2. `/open/index.html`
3. `/.well-known/apple-app-site-association`，响应必须是 JSON、不能重定向

只有 AASA 上线并重新安装带 entitlement 的新包后，HTTPS 链接才能完成已安装 App 唤端。AASA 未部署时，链接会按未安装分支进入 App Store，这是预期行为而不是 App 路由失败。
