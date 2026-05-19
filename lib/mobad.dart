import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:yogotv/global.dart';

class MobAd extends StatefulWidget {
  const MobAd({super.key});

  @override
  State<StatefulWidget> createState() {
    return _MobAd();
  }
}

class _MobAd extends State<MobAd> {
  NativeAd? _nativeAd;
  bool _nativeAdIsLoaded = false;

  final String _adUnitId = Platform.isAndroid
      ? 'ca-app-pub-3940256099942544/2247696110'
      : 'ca-app-pub-3940256099942544/3986624511';

  @override
  void initState() {
    super.initState();
    _loadAd();
  }

  void _loadAd() {
    _nativeAd = NativeAd(
      adUnitId: _adUnitId,
      listener: NativeAdListener(
        onAdLoaded: (ad) {
          setState(() {
            _nativeAdIsLoaded = true;
          });
        },
        onAdFailedToLoad: (ad, error) {
          // Dispose the ad here to free resources.
          ad.dispose();
        },
        // Called when a click is recorded for a NativeAd.
        onAdClicked: (ad) {},
        // Called when an impression occurs on the ad.
        onAdImpression: (ad) {},
        // Called when an ad removes an overlay that covers the screen.
        onAdClosed: (ad) {},
        // Called when an ad opens an overlay that covers the screen.
        onAdOpened: (ad) {},
        // For iOS only. Called before dismissing a full screen view
        onAdWillDismissScreen: (ad) {},
        // Called when an ad receives revenue value.
        onPaidEvent: (ad, valueMicros, precision, currencyCode) {},
      ),
      request: const AdRequest(),
      // Styling
      nativeTemplateStyle: NativeTemplateStyle(
        // Required: Choose a template.
        templateType: TemplateType.small,
        // Optional: Customize the ad's style.
        mainBackgroundColor: Colors.purple,
        cornerRadius: 10.0,
        callToActionTextStyle: NativeTemplateTextStyle(
          textColor: Colors.cyan,
          backgroundColor: Colors.red,
          style: NativeTemplateFontStyle.monospace,
          size: 16.0,
        ),
        primaryTextStyle: NativeTemplateTextStyle(
          textColor: Colors.red,
          backgroundColor: Colors.cyan,
          style: NativeTemplateFontStyle.italic,
          size: 16.0,
        ),
        secondaryTextStyle: NativeTemplateTextStyle(
          textColor: Colors.green,
          backgroundColor: Colors.black,
          style: NativeTemplateFontStyle.bold,
          size: 16.0,
        ),
        tertiaryTextStyle: NativeTemplateTextStyle(
          textColor: Colors.brown,
          backgroundColor: Colors.amber,
          style: NativeTemplateFontStyle.normal,
          size: 16.0,
        ),
      ),
    )..load();
  }

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(
        minWidth: 320,
        minHeight: 320,
        maxWidth: 400,
        maxHeight: 400,
      ),
      child: _nativeAdIsLoaded
          ? AdWidget(ad: _nativeAd!)
          : Container(
              color: Colors.amber,
              child: Center(child: Text('loading...')),
            ),
    );
  }
}

splashAd(void Function(bool) callback) async {
  AppOpenAd.load(
    adUnitId: kDebugMode
        ? Platform.isAndroid
              ? 'ca-app-pub-3940256099942544/9257395921'
              : 'ca-app-pub-3940256099942544/5575463023'
        : Platform.isAndroid
        ? 'ca-app-pub-3139952175368675/5838274670'
        : 'ca-app-pub-3139952175368675/6558930609',
    request: AdRequest(),
    adLoadCallback: AppOpenAdLoadCallback(
      onAdLoaded: (ad) {
        debugPrint('$ad loaded.');
        var completed = false;
        ad.fullScreenContentCallback = FullScreenContentCallback(
          // Called when the ad showed the full screen content.
          onAdShowedFullScreenContent: (ad) {
            Global.logger.d('AD show');
          },
          // Called when an impression occurs on the ad.
          onAdImpression: (ad) {
            Global.logger.d('AD imprese');
          },
          // Called when the ad failed to show full screen content.
          onAdFailedToShowFullScreenContent: (ad, err) {
            // Dispose the ad here to free resources.
            ad.dispose();
            callback(completed);
            Global.logger.d('AD failed');
          },
          // Called when the ad dismissed full screen content.
          onAdDismissedFullScreenContent: (ad) {
            // Dispose the ad here to free resources.
            ad.dispose();
            callback(completed);
            Global.logger.d('AD dismissed');
          },
          // Called when a click is recorded for an ad.
          onAdClicked: (ad) {},
        );

        ad.show();
      },
      onAdFailedToLoad: (LoadAdError error) {
        debugPrint('RewardedAd failed to load: $error');
        callback(false);
      },
    ),
  );
}

rewardedAd(void Function(bool) callback) async {
  await RewardedAd.load(
    adUnitId: kDebugMode
        ? (Platform.isAndroid
              ? 'ca-app-pub-3940256099942544/5224354917'
              : 'ca-app-pub-3940256099942544/1712485313')
        : (Platform.isAndroid
              ? 'ca-app-pub-3139952175368675/4481102537'
              : 'ca-app-pub-3139952175368675/9256246051'),
    request: AdRequest(),
    rewardedAdLoadCallback: RewardedAdLoadCallback(
      // Called when an ad is successfully received.
      onAdLoaded: (ad) {
        debugPrint('$ad loaded.');
        var completed = false;
        ad.fullScreenContentCallback = FullScreenContentCallback(
          // Called when the ad showed the full screen content.
          onAdShowedFullScreenContent: (ad) {
            Global.logger.d('AD show');
          },
          // Called when an impression occurs on the ad.
          onAdImpression: (ad) {
            Global.logger.d('AD imprese');
          },
          // Called when the ad failed to show full screen content.
          onAdFailedToShowFullScreenContent: (ad, err) {
            // Dispose the ad here to free resources.
            ad.dispose();
            callback(completed);
            Global.logger.d('AD failed');
          },
          // Called when the ad dismissed full screen content.
          onAdDismissedFullScreenContent: (ad) {
            // Dispose the ad here to free resources.
            ad.dispose();
            callback(completed);
            Global.logger.d('AD dismissed');
          },
          // Called when a click is recorded for an ad.
          onAdClicked: (ad) {},
        );

        ad.show(
          onUserEarnedReward: (a, b) {
            completed = true;
            Global.logger.d('AD earned');
          },
        );
      },
      // Called when an ad request failed.
      onAdFailedToLoad: (LoadAdError error) {
        debugPrint('RewardedAd failed to load: $error');
        callback(false);
      },
    ),
  );
}

rewardedInterstitialAd(void Function(bool) callback) async {
  await RewardedInterstitialAd.load(
    adUnitId: kDebugMode
        ? Platform.isAndroid
              ? 'ca-app-pub-3940256099942544/5354046379'
              : 'ca-app-pub-3940256099942544/6978759866'
        : Platform.isAndroid
        ? 'ca-app-pub-3139952175368675/3265718701'
        : 'ca-app-pub-3139952175368675/6831792140',
    request: const AdRequest(keywords: ['tools']),
    rewardedInterstitialAdLoadCallback: RewardedInterstitialAdLoadCallback(
      // Called when an ad is successfully received.
      onAdLoaded: (ad) async {
        debugPrint('$ad loaded.');
        var completed = false;
        // Keep a reference to the ad so you can show it later.
        ad.fullScreenContentCallback = FullScreenContentCallback(
          // Called when the ad showed the full screen content.
          onAdShowedFullScreenContent: (ad) {
            Global.logger.d('AD show');
          },
          // Called when an impression occurs on the ad.
          onAdImpression: (ad) {
            Global.logger.d('AD imprese');
          },
          // Called when the ad failed to show full screen content.
          onAdFailedToShowFullScreenContent: (ad, err) {
            // Dispose the ad here to free resources.
            ad.dispose();
            callback(completed);
            Global.logger.d('AD failed');
          },
          // Called when the ad dismissed full screen content.
          onAdDismissedFullScreenContent: (ad) {
            // Dispose the ad here to free resources.
            ad.dispose();
            callback(completed);
            Global.logger.d('AD dismissed');
          },
          // Called when a click is recorded for an ad.
          onAdClicked: (ad) {},
        );

        ad.show(
          onUserEarnedReward: (a, b) {
            completed = true;
            Global.logger.d('AD earned');
          },
        );
      },
      // Called when an ad request failed.
      onAdFailedToLoad: (LoadAdError error) {
        debugPrint('RewardedInterstitialAd failed to load: $error');
        callback(false);
      },
    ),
  );
}

interstitialAd(void Function(bool) callback) async {
  await InterstitialAd.load(
    adUnitId: kDebugMode
        ? Platform.isAndroid
              ? 'ca-app-pub-3940256099942544/1033173712'
              : 'ca-app-pub-3940256099942544/4411468910'
        : Platform.isAndroid
        ? 'ca-app-pub-3139952175368675/9143982913'
        : 'ca-app-pub-3139952175368675/3891656237',
    request: const AdRequest(),
    adLoadCallback: InterstitialAdLoadCallback(
      // Called when an ad is successfully received.
      onAdLoaded: (ad) {
        Global.logger.d('Ad loaded.');
        ad.fullScreenContentCallback = FullScreenContentCallback(
          // Called when the ad showed the full screen content.
          onAdShowedFullScreenContent: (ad) {
            Global.logger.d('Ad show.');
          },
          // Called when an impression occurs on the ad.
          onAdImpression: (ad) {
            Global.logger.d('Ad impression.');
          },
          // Called when the ad failed to show full screen content.
          onAdFailedToShowFullScreenContent: (ad, err) {
            // Dispose the ad here to free resources.
            ad.dispose();
            Global.logger.d('Ad failed.');
            callback(false);
          },
          // Called when the ad dismissed full screen content.
          onAdDismissedFullScreenContent: (ad) {
            // Dispose the ad here to free resources.
            ad.dispose();
            Global.logger.d('Ad done.');
            callback(true);
          },
          // Called when a click is recorded for an ad.
          onAdClicked: (ad) {
            Global.logger.d('Ad click.');
          },
        );
        ad.show();
      },
      // Called when an ad request failed.
      onAdFailedToLoad: (LoadAdError error) {
        Global.logger.d('InterstitialAd failed to load: $error');
        callback(false);
      },
    ),
  );
}
