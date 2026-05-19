import 'dart:async';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:yogotv/api.dart';
import 'package:yogotv/global.dart';
import 'package:yogotv/i18n/strings.g.dart';

class Purchase {
  static late final StreamSubscription<List<PurchaseDetails>> subscription;
  static dynamic result;
  static bool canProcess = false;
  static void Function()? _loadingCallback;

  static init() {
    subscription = InAppPurchase.instance.purchaseStream.listen((
      purchaseDetailsList,
    ) async {
      if (!canProcess) {
        return;
      }
      try {
        for (var details in purchaseDetailsList) {
          if (details.status == PurchaseStatus.pending) {
            Global.logger.d('pending');
          } else {
            if (details.status == PurchaseStatus.error) {
              Global.logger.d('${details.error!}');
            } else if (details.status == PurchaseStatus.purchased ||
                details.status == PurchaseStatus.restored) {
              await _processPurchase(details);
            }
            if (details.pendingCompletePurchase) {
              await InAppPurchase.instance.completePurchase(details);
            }
          }
        }
      } on Exception catch (e) {
        Global.logger.d(e);
      } finally {
        if (purchaseDetailsList.isEmpty) {
          Global.warning(t.no_order);
        }
        _loadingCallback?.call();
      }
    });
  }

  static dispose() async {
    _loadingCallback?.call();
    await subscription.cancel();
  }

  static loading() {
    _loadingCallback = Global.loading();
  }

  static closeLoading() {
    _loadingCallback?.call();
  }

  static Future<void> _processPurchase(PurchaseDetails details) async {
    await api(
      'pay/iap',
      method: Method.post,
      data: {
        'source': details.verificationData.source,
        'data': details.verificationData.localVerificationData,
      },
    );
  }

  static Future<bool> making({required String product}) async {
    loading();
    if (!await InAppPurchase.instance.isAvailable()) {
      Global.error('Purchase Failed');
      _loadingCallback?.call();
      return false;
    }

    final response = await InAppPurchase.instance.queryProductDetails({
      product,
    });

    if (response.productDetails.isEmpty) {
      Global.error('No Product');
      _loadingCallback?.call();
      return false;
    }

    try {
      return await InAppPurchase.instance.buyNonConsumable(
        purchaseParam: PurchaseParam(
          productDetails: response.productDetails.first,
        ),
      );
    } on Exception catch (_) {
      return false;
    } finally {
      closeLoading();
    }
  }

  static Future<void> restore() async {
    await InAppPurchase.instance.restorePurchases();
  }
}
