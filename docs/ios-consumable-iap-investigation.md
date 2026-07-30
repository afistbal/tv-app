# iOS 消耗型内购问题调查

调查日期：2026-07-24

调查基线：分支 `dev-ios`、提交 `36d5e88`、App `1.0.5 (9)`。

说明：本文前半部分保留修复前现场和因果链，文中的旧行号也指该基线。调查完成后，工作区已经实施客户端修复；具体改动和真机验收步骤见第八、九节及
[`ios-consumable-iap-test-plan.md`](ios-consumable-iap-test-plan.md)。

## 一、结论摘要

### 问题 1：购买成功后，“我的”页面金币不立即增加

已确认客户端确实会在 Apple 回调后调用服务端：

1. 收到 Apple `purchased` 或 `restored` 交易。
2. 调用 `applePay/verify` 验单和发货。
3. 只有 `applePay/verify` 返回 `c == 0`，当前购买流程才返回成功。
4. 随后调用 `user/balance` 查询金币。

但是查询到的余额只写入充值页 `_VipPaySheetState._balance`。充值页关闭后，下面已经存在的“我的”页面没有收到新余额，也没有在路由返回时重新查询，所以仍显示旧值；用户手动刷新后才更新。

另外，`user/balance` 的结果不是关闭充值页的成功条件。即使余额接口失败或暂时返回旧值，代码仍会关闭充值页。因此：

- Apple 沙盒提示成功，不等于服务端发金币成功。
- 当前代码以 `applePay/verify c == 0` 作为购买成功条件。
- `user/balance` 会调用，但调用失败或页面没有同步结果，都不会阻止返回“我的”页面。

### 问题 2：第一次买成功后，再买相同金币包不弹 Apple 支付框

官方结论是：**消耗型商品允许重复购买。Apple 不会因为这个商品曾经买过，就永久禁止再次拉起支付。**

当前项目存在一个与现象高度吻合、且已被 Flutter 官方确认和修复的插件缺陷：

- 项目使用 `in_app_purchase 3.2.3`。
- 锁定的 iOS 实现是 `in_app_purchase_storekit 0.4.3`。
- `0.4.3` 会把 StoreKit 2 的正常新购买错误标记为 `PurchaseStatus.restored`。
- 该状态下 `pendingCompletePurchase == false`。
- 当前客户端因此不会调用 `completePurchase`。
- Apple 交易留在 unfinished 队列中。
- 再买相同 Product ID 时，Apple/插件可能直接拒绝、重放旧交易，或者不再展示新的支付框。

Flutter 官方在 `in_app_purchase_storekit 0.4.8` 修复了这个问题。官方修复说明与本项目的依赖版本、代码分支和用户现象完全一致，因此这是问题 2 的首要根因，置信度高。

“这个商品第一次购买前从未买过”并不能排除此问题。unfinished 状态是在**第一次购买完成后**产生的，不需要更早的购买历史，也不依赖安装前已有的本地缓存。

## 二、版本与现场信息

修复前仓库快照：

- 分支：`dev-ios`
- 提交：`36d5e88`
- `pubspec.yaml`：`1.0.5+9`
- `in_app_purchase`：`3.2.3`
- `in_app_purchase_storekit`：`0.4.3`
- 本机 Flutter SDK：`3.44.4`

用户描述中出现了“1.0.9”。仓库当前声明的是 `1.0.5 (9)`，后续验证前应确认 TestFlight 中实际安装包的版本、构建号和构建所用的 `pubspec.lock`，避免把不同构建混在一起。

截图中的错误订单号：

`AP20260724102119TQEVKAAO`

建议直接用该订单号查询服务端的 `applePay/create`、`applePay/verify`、金币入账和 Apple transaction ID 记录。

## 三、问题 1 的实际代码链路

### 3.1 Apple 回调与服务端验单

`lib/purchase.dart`：

- 第 23 行：订阅 `purchaseStream`。
- 第 43-44 行：处理 `purchased` 和 `restored`。
- 第 58 行：调用 `_processPurchase`。
- 第 173-179 行：请求 `applePay/verify`。
- 第 187-198 行：`verify c != 0` 时返回失败，并保留 Apple 交易。
- 第 200-213 行：`verify c == 0` 时才返回 verified。

所以当前代码不是只看到“沙盒购买成功”就直接当作发金币完成，它会调用后端验单。

### 3.2 验单成功后的余额查询

`lib/pages/membership.dart`：

- 第 553-557 行：调用 `Purchase.making`。
- 第 559 行：只有 `Purchase.making == true` 才进入成功分支。
- 第 575-576 行：金币商品调用 `_refreshBalance()`。
- 第 637-647 行：请求 `user/balance`，结果只写入充值页自己的 `_balance`。
- 第 583-584 行：随后关闭充值页。

问题在于 `_refreshBalance()` 返回 `void`：

- 它没有把新余额返回给“我的”页面。
- `balance.c != 0` 时只提前 return，外层仍然关闭充值页。
- 没有校验余额是否比购买前增加。
- 没有针对服务端入账延迟进行重试或短轮询。

### 3.3 “我的”页面没有在充值返回时刷新

`lib/pages/profile.dart`：

- 第 52-56 行：`_loadData()` 才会请求 `user/balance`。
- 第 41-43 行：只有底部 Tab 从非激活变为激活时才自动 `_loadData`。
- 第 775-776 行：进入充值页只是 `context.push('/top-up')`，没有 await 路由结果，也没有在返回后 `_loadData`。

从“我的”页面 push 充值页再 pop 回来时，“我的”Tab 始终是 active，`didUpdateWidget` 不会触发，因此显示旧余额是当前代码的确定行为。

### 3.4 问题 1 的判断

| 判断 | 结论 |
| --- | --- |
| Apple 沙盒成功后是否调用 `applePay/verify` | 是 |
| `applePay/verify` 是否必须成功才自动关闭充值页 | 是 |
| 验单成功后是否调用 `user/balance` | 是 |
| `user/balance` 失败是否阻止关闭充值页 | 否 |
| 新余额是否同步到“我的”页面 | 否 |
| 手动刷新后能增加说明什么 | 服务端大概率已入账，当前主要是客户端页面状态未刷新 |

服务端是否存在短暂入账延迟，仅凭客户端代码不能完全排除；需要按订单号核对接口时间和返回值。

## 四、Apple 对重复购买的官方规则

App Store Connect 中的四个金币商品显示为 `Consumable`，即消耗型商品。

Apple 官方说明：

- Consumable 会被消耗，用户可以购买多次。
- Non-consumable 才是购买一次后长期拥有的商品。
- 交易在调用 `finish()` / `finishTransaction()` 前都属于 unfinished。
- unfinished 交易会继续留在队列中，App 再次启动或恢复时会继续收到它们，并可能阻止新的购买。

因此正确判断是：

> 买过同一个消耗型商品，本身不会导致无法再次拉起 Apple 支付；未完成的上一笔交易才会。

官方资料：

- [Apple：Consumables can be purchased multiple times](https://developer.apple.com/documentation/StoreKit/original-api-for-in-app-purchase)
- [Apple：Offering, completing, and restoring in-app purchases](https://developer.apple.com/documentation/StoreKit/offering-completing-and-restoring-in-app-purchases)
- [Apple：Transaction.unfinished](https://developer.apple.com/documentation/storekit/transaction/unfinished)
- [Apple：Finishing a transaction](https://developer.apple.com/documentation/storekit/finishing-a-transaction)

## 五、与项目完全匹配的 Flutter 官方缺陷

### 5.1 项目锁定了问题版本

`pubspec.lock` 当前为：

```text
in_app_purchase: 3.2.3
in_app_purchase_storekit: 0.4.3
```

从 `in_app_purchase_storekit 0.4.0` 开始，支持的设备默认使用 StoreKit 2。

### 5.2 `0.4.3` 为什么会留下 unfinished 交易

本机锁定包 `0.4.3` 的实现存在以下组合：

1. StoreKit 2 正常购买成功后会附带 JWS receipt。
2. `StoreKit2Translators.swift` 用 `receipt != nil` 判断 `restoring`。
3. 因此正常新购买也被标成 `restored`。
4. `SK2PurchaseDetails.pendingCompletePurchase` 只有在状态为 `purchased` 时才返回 true。
5. 于是正常新购买得到：

```text
status = restored
pendingCompletePurchase = false
```

Flutter 官方 Issue #172434 记录了相同版本和相同结果；官方修复提交说明普通购买因此没有调用 `completePurchase`，交易违反 StoreKit 约定而留在 unfinished 状态。

### 5.3 当前业务代码如何触发这个缺陷

`lib/purchase.dart` 第 70-73 行：

```dart
if (verification.shouldComplete &&
    details.pendingCompletePurchase) {
  await InAppPurchase.instance.completePurchase(details);
}
```

业务代码同时接受 `purchased` 和 `restored` 做服务端验单，所以第一次购买可以：

1. 被错误标成 `restored`。
2. `applePay/verify` 成功并发金币。
3. `_completePending(..., true)` 让页面走成功流程。
4. 因为 `pendingCompletePurchase == false`，不执行 `completePurchase`。
5. Apple 交易仍是 unfinished。

这正好解释“第一次买成功并到账，但第二次同商品不弹支付框”。

### 5.4 Flutter 官方修复

Flutter 官方在 `in_app_purchase_storekit 0.4.8` 修复：

> StoreKit 2 purchases were reported as `restored` and left unfinished because `pendingCompletePurchase` was false.

修复后，正常购买保持 `purchased`，`pendingCompletePurchase` 为 true，客户端按文档调用 `completePurchase`。

`0.4.10` 又增加了显式检查：同 Product ID 已有 unfinished 交易时，抛出 `storekit_duplicate_product_object`，使问题更容易识别。

官方资料：

- [Flutter 插件 Changelog：0.4.8 修复 restored/unfinished](https://flutter.googlesource.com/mirrors/packages/+/HEAD/packages/in_app_purchase/in_app_purchase_storekit/CHANGELOG.md)
- [Flutter 官方修复提交 #10656](https://chromium.googlesource.com/external/github.com/flutter/packages/+/63505183ffbadcf7bfa9aa69b0f10b0c6f7df564)
- [Flutter Issue #172434：0.4.3 新购买被标成 restored](https://github.com/flutter/flutter/issues/172434)
- [Flutter `in_app_purchase`：完成交易与同商品重复购买说明](https://pub.dev/packages/in_app_purchase)

## 六、截图中的 “Order exception” 表示什么

截图文案只会在以下代码分支出现：

`lib/purchase.dart` 第 187-196 行：

```text
applePay/verify 返回 c != 0
```

所以该弹层不是 Apple 原生的“此商品不可重复购买”提示，而是客户端收到某笔 Apple 交易后，服务端 `applePay/verify` 拒绝了它。

第二次点击时的高概率链路是：

1. 客户端先调用 `applePay/create` 创建新订单。
2. 新订单按 Product ID 放入 `_pendingOrders` 和本地缓存。
3. Apple/StoreKit 重放第一次留下的 unfinished 交易，或阻止同 Product ID 的新交易。
4. 当前代码仅用 Product ID 判断“这是不是本次交互交易”。
5. 旧 Apple transaction 可能被配到第二次创建的新订单号。
6. 服务端发现订单号、transaction ID、appAccountToken 或商品状态不匹配，返回 `c != 0`。
7. 客户端显示截图中的 `Order exception`。

这部分是高概率推断，必须用订单
`AP20260724102119TQEVKAAO`
对应的服务端日志确认。

## 七、“之前从未购买”为什么仍会发生

需要区分三种状态：

| 状态 | 是否影响本问题 |
| --- | --- |
| 购买前从未买过该商品 | 不排除问题 |
| App 本地在购买前没有订单缓存 | 不排除问题 |
| 第一次购买后的 Apple transaction 没有 finish | 会直接影响第二次购买 |

本项目的问题版本会在第一次购买后制造 unfinished 交易。即使换全新的 Sandbox 账号、全新的 Product ID 和全新安装，第一次可能成功，紧接着第二次仍可能失败。

卸载 App 或清理普通本地缓存也不等于完成 Apple transaction，因为 unfinished 状态属于 StoreKit/Apple 交易队列。

## 八、已实施的客户端处理

### P0：修复 StoreKit 插件版本

`pubspec.yaml` 已直接锁定，`pubspec.lock` 已解析为：

```text
in_app_purchase_storekit 0.4.10+1
```

该版本包含 `0.4.8` 的 restored/unfinished 修复，并会在同 SKU
仍有 unfinished 交易时明确返回 `storekit_duplicate_product_object`。

### P0：恢复已经卡住的 unfinished 交易

客户端现在会在启动后以及每次购买前查询 `Transaction.unfinished`：

1. 用旧交易自己的 `appAccountToken`、`transactionId` 和 JWS 调用
   `applePay/verify`。
2. 只有服务端确认已发货，才调用 `completePurchase`。
3. finish 成功后才允许创建同 SKU 的下一笔订单。
4. 如果服务端拒绝旧交易，客户端保留它并输出可复制诊断日志，不会无条件
   finish。

服务端仍必须把已发过金币的同一 `transactionId` 视为幂等成功；否则客户端无法安全
finish 这笔旧交易。

### P1：修正订单与 Apple transaction 的关联

交易现在优先使用 `appAccountToken` 找本地预订单，并以 `transactionId` 防重复处理。
当 Apple 重放旧交易时，不再仅凭 Product ID 把它绑定到第二次刚创建的订单。关联字段为：

- Apple `transactionId`：服务端幂等键。
- `appAccountToken`：关联 App 用户和服务端预订单。
- 服务端 `order_no`：业务订单。

### P1：修复金币页面状态同步

`Profile` 现在 await `/top-up` 路由结果。充值成功返回后会重新调用
`user/balance`，因此“我的”页面不再依赖手动刷新。充值页自己的余额请求和 Profile
返回后的余额请求都会写入诊断日志。

### P1：成功顺序

购买成功顺序已经改为：

1. `applePay/verify c == 0`；
2. `completePurchase` 成功；
3. 向页面返回成功；
4. 查询充值页余额；
5. 返回 Profile 后再次查询余额。

任何一步失败都会保留阶段、订单号、transaction ID 和错误码。完整 Apple JWS 和登录
Token 不写入可复制日志。

### 诊断入口

- Debug 构建默认开启支付诊断。
- Release/TestFlight 构建需加入
  `--dart-define=PAYMENT_DIAGNOSTICS=true`。
- 诊断构建的充值页和会员页右上角显示日志按钮。
- 成功或失败后显示可复制日志弹窗；用户主动取消 Apple 支付时不弹诊断框。

## 九、下一轮验证清单

### 9.1 当前问题版本的证据

在一台真机、一个新的 Sandbox 测试账号上：

1. 记录购买前金币。
2. 首次购买一个从未买过的 Consumable。
3. 记录 `productID`、`purchaseID/transactionId`。
4. 记录 `PurchaseStatus`。
5. 记录 `pendingCompletePurchase`。
6. 记录 `applePay/verify` 的 `order_no`、`c`、`m`。
7. 记录是否实际调用并成功完成 `completePurchase`。
8. 立即再次购买相同 Product ID。

对 `0.4.3` 的预期故障证据：

```text
首次新购买 status = restored
pendingCompletePurchase = false
服务端验单成功
客户端未调用 completePurchase
第二次同 Product ID 无新支付框或收到旧交易
```

### 9.2 修复版本的验收标准

升级后的必要验收：

```text
首次购买 status = purchased
pendingCompletePurchase = true
applePay/verify c = 0
completePurchase 成功
user/balance 返回新余额
返回“我的”页面立即显示新余额
第二次同 Product ID 拉起新的 Apple 支付框
第二笔 transactionId 与第一笔不同
每个 transactionId 只增加一次金币
```

建议对四个金币 Product ID 各做一次首次购买，并至少选择一个 SKU 连续购买两次。

## 十、需要服务端提供的最小日志

针对截图订单号和相邻时间段，至少导出：

- 用户 ID / 匿名用户 ID
- `order_no`
- 本地商品 ID
- Apple Product ID
- `appAccountToken`
- Apple `transactionId`
- `originalTransactionId`
- `applePay/create` 返回值
- `applePay/verify` 请求时间、`c`、`m`
- Apple JWS 验证结果和 environment
- 金币账变流水 ID、变更前余额、增加值、变更后余额
- 重复 transactionId 的处理结果

关键判断：

- 第一次验单是否 `c == 0` 并已产生金币流水；
- 第二次报错时收到的是第一笔 transactionId，还是新的 transactionId；
- 第二次的新 `order_no` 是否错误关联了第一笔 transactionId；
- 已入账 transactionId 再次验单时，服务端是否返回错误而不是幂等成功。

## 十一、当前判断等级

| 结论 | 置信度 |
| --- | --- |
| Consumable 官方允许重复购买 | 已确认 |
| “我的”页面未同步充值页余额 | 已确认 |
| 当前代码会调用 `applePay/verify` 和 `user/balance` | 已确认 |
| 修复前项目锁定 `in_app_purchase_storekit 0.4.3` | 已确认 |
| `0.4.3` 存在新购买误报 restored、交易不 finish 的官方缺陷 | 已确认 |
| 该插件缺陷是第二次同 SKU 不弹窗的首要根因 | 高置信度 |
| 截图错误是 `applePay/verify c != 0` | 已确认 |
| 第二次新订单错误匹配了第一笔 unfinished transaction | 已由服务端日志确认 |
| 工作区已升级到 `in_app_purchase_storekit 0.4.10+1` | 已确认 |

## 十二、服务端日志确认结果

2026-07-24 11:15 的服务端日志已经把“高概率推断”确认为实际发生：

```text
新订单：AP20260724111511HDLA7RGD
客户端上报 appAccountToken：0d3ae2b4-c97f-486d-91cd-9bbf9e7dd530
Apple 签名 appAccountToken：9dabd6a8-5e2f-46c1-ba06-3c9c42f1bc72
Apple transactionId：2000001210340492
Apple purchaseDate：2026-07-24 10:21:07 CST
服务端上报时间：2026-07-24 11:15:13 CST
服务端结果：invalid appAccountToken
```

即 10:21 的旧 Apple transaction 在 11:15 被重放，并绑定到了 11:15 新创建的
业务订单。服务端比较客户端字段与 Apple 签名字段后拒绝是正确行为。

客户端修复进一步调整为：

- 直接解析 Apple 签名 JWS payload；
- `appAccountToken`、`transactionId`、`productId` 优先采用签名值；
- 只有 token 匹配时才绑定本地预订单；
- 旧 unfinished 交易恢复时禁用 Product ID 兜底关联。

因此新诊断包不应再把上述两个不同的 `appAccountToken` 放进同一次验单请求。
