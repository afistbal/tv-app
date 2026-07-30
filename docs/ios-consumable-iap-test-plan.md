# iOS 消耗型内购真机测试方案

日期：2026-07-24

目标：确认同一个 Consumable SKU 可以连续购买，并用可复制日志区分服务端预订单、
Apple 支付、服务端验单、Apple finish 和余额刷新问题。

## 一、准备诊断包

### 方式 A：连接 iPhone 直接调试

在 VS Code 选择：

```text
YogoShort iOS Payment Debug
```

Debug 构建默认开启诊断，配置中也显式传入：

```text
--dart-define=PAYMENT_DIAGNOSTICS=true
```

项目使用 Flutter Dio。Flutter 默认不会跟随 iPhone 的系统级 HTTP 代理，因此
`YogoShort iOS Payment Debug` 还会显式配置：

```text
--dart-define=PROXY_HOST=192.168.0.41
--dart-define=PROXY_PORT=9090
```

`PROXY_HOST` 必须是运行 Proxyman 的 Mac 当前局域网 IP。IP 变化后，需要同步修改
`.vscode/launch.json`；可以在 Proxyman 的
`Certificate -> Install Certificate on iOS -> Physical Devices` 中查看当前地址。

该代理配置只在诊断构建中生效，并会临时允许 Proxyman 的调试证书。不要把
`PROXY_HOST` 带入普通生产包。

### 方式 B：TestFlight 诊断包

构建 Release IPA 时加入：

```bash
flutter build ipa --release --dart-define=PAYMENT_DIAGNOSTICS=true
```

若 TestFlight 诊断包也需要显式经过当前 Mac 的 Proxyman：

```bash
flutter build ipa --release \
  --dart-define=PAYMENT_DIAGNOSTICS=true \
  --dart-define=PROXY_HOST=192.168.0.41 \
  --dart-define=PROXY_PORT=9090
```

这种包离开该 Mac/网络后可能无法联网，只用于短期抓包。

App Store Connect 不接受重复的构建号。当前仓库是 `1.0.5 (9)`；上传新的
TestFlight 包前需要把 build number 改成大于 9。

普通生产包不要传 `PAYMENT_DIAGNOSTICS=true`。诊断日志不记录登录 Token 或完整
Apple JWS，但仍包含订单号、Product ID、transaction ID 和接口错误信息。

## 二、手机测试步骤

1. 安装包含本次修复的诊断包。不要继续用旧的 `1.0.5 (9)` 判断修复结果。
2. 在这台已经出现过问题的手机上首次启动新包。
3. 先进入充值页，点右上角日志按钮并复制一次日志，保留启动时恢复旧
   unfinished 交易的证据。
4. 再点 `Clear`，返回充值页。
5. 打开“我的”并记录当前金币。
6. 购买一个金币 SKU，例如 `coin2000`。
7. Apple 沙盒支付完成后，在诊断弹窗点 `Copy logs`。
8. 点 `Continue`，确认返回“我的”后金币无需手动刷新就已增加。
9. 立即再次进入充值页，购买同一个 `coin2000`。
10. 确认第二次出现新的 Apple 支付框。
11. 完成第二次支付，复制第二份日志。
12. 确认第二笔 `transactionId` 与第一笔不同，并且金币只增加一次。

建议再选择另一个从未测试过的 SKU 做一轮首次购买；不必为“可重复购买”更换
Sandbox 账号，因为 Consumable 本来就允许同账号重复购买。

## 三、成功日志应出现的顺序

```text
stage=store_availability
stage=unfinished_check
stage=unfinished_clear
stage=create_started
stage=create_ok orderNo=...
stage=product_query
stage=apple_sheet_requested
stage=transaction_received status=purchased transactionId=...
stage=verify_started
stage=verify_ok
stage=finish_started
stage=finish_ok
stage=purchase_complete
stage=balance_refresh_started
stage=balance_refresh_ok
stage=profile_balance_refresh_started
stage=profile_balance_refresh_ok
```

第二次购买必须有新的 `create_ok orderNo` 和新的 `transactionId`。

## 四、按最后阶段定位问题

| 最后阶段或错误 | 判断 |
| --- | --- |
| 没有 `create_started` | 在检查商店或恢复旧交易前停止 |
| `create_rejected` | `applePay/create` 服务端拒绝 |
| 有 `create_ok`，没有 `apple_sheet_requested` | 商品查询或客户端参数问题 |
| `apple_purchase_request_failed code=storekit_duplicate_product_object` | Apple 仍有同 SKU unfinished 交易 |
| `unfinished_found` 后 `verify_rejected` | 旧交易已找到，但服务端不接受重验，需检查验单幂等 |
| `apple_sheet_requested` 后用户未见支付框，随后 PlatformException | StoreKit 在拉框前拒绝，查看错误 code |
| `transaction_received` 后 `verify_rejected` | Apple 已产生/重放交易，`applePay/verify` 服务端拒绝 |
| `verify_ok` 后 `finish_failed` | 服务端已发货，但 Apple transaction 未 finish |
| `finish_ok` 后 `balance_refresh_rejected/failed` | 支付完成，余额接口失败 |
| 充值页 `balance_refresh_ok`，Profile 刷新前仍是旧值 | 路由返回或 Profile 刷新问题 |
| 两次 transaction ID 相同 | 第二次收到的是旧 unfinished 交易，不是新购买 |

## 五、这台已出现问题的手机

升级后，客户端会在启动时和购买前查询 Apple unfinished 交易。预期先看到：

```text
stage=unfinished_found product=... transactionId=...
stage=verify_started
```

如果该交易第一次已经发过金币，服务端应按 `transactionId` 幂等返回成功，然后日志
继续到 `finish_ok`。完成后，同 SKU 的下一次购买才会正常拉起新支付框。

如果服务端把“已发过金币”返回成错误，日志会停在 `verify_rejected`。此时客户端不能
无条件 finish，否则可能造成已付款但未发货；需要服务端把同一 transaction ID 的
重复验单改成成功等价值。

## 六、服务端核对

重点查询旧截图订单：

```text
AP20260724102119TQEVKAAO
```

至少核对：

- 每次 `applePay/create` 的 `order_no` 和 `appAccountToken`
- `applePay/verify` 收到的 `transactionId`
- 第二次报错用的是第一笔还是新的 transaction ID
- 第一次 transaction ID 是否已有金币流水
- 已入账 transaction ID 再次验单时返回的 `c`、`m`
- 每个 transaction ID 是否最多发货一次

## 七、验收标准

- 首次交易为 `status=purchased` 且 `pendingCompletePurchase=true`。
- `verify_ok` 后必须出现 `finish_ok`。
- 返回“我的”后无需手动刷新即可看到新余额。
- 同 SKU 第二次购买出现 Apple 支付框。
- 两次购买使用不同 transaction ID。
- 每个 transaction ID 只产生一次金币流水。
