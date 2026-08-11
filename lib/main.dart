import 'dart:async';
import 'package:bot_toast/bot_toast.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:firebase_core/firebase_core.dart' show Firebase;
import 'package:go_router/go_router.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:tiktok_events_sdk/tiktok_events_sdk.dart';
import 'package:yogotv/adjust_tracking.dart';
import 'package:yogotv/api.dart';
import 'package:yogotv/deep_link_handler.dart';
import 'package:yogotv/pages/alert.dart';
import 'package:yogotv/firebase_options.dart' show DefaultFirebaseOptions;
import 'package:yogotv/global.dart';
import 'package:yogotv/i18n/strings.g.dart';
import 'package:yogotv/pages/about.dart';
import 'package:yogotv/pages/airwallex.dart';
import 'package:yogotv/pages/earn_detail.dart';
import 'package:yogotv/pages/earn_withdraw.dart';
import 'package:yogotv/pages/home.dart';
import 'package:yogotv/pages/language.dart';
import 'package:yogotv/pages/label_video.dart';
import 'package:yogotv/pages/login.dart';
import 'package:yogotv/pages/membership.dart';
import 'package:yogotv/pages/my_list.dart';
import 'package:yogotv/pages/profile.dart';
import 'package:yogotv/pages/recommend.dart';
import 'package:yogotv/pages/search.dart';
import 'package:yogotv/pages/play.dart';
import 'package:yogotv/pages/help.dart';
import 'package:yogotv/pages/settings.dart';
import 'package:yogotv/pages/delete_account.dart';
import 'package:yogotv/pages/wallet.dart';
import 'package:yogotv/purchase.dart';
import 'package:yogotv/splash.dart';
import 'package:yogotv/states/main.dart';
import 'package:yogotv/states/restart.dart';
import 'package:yogotv/states/user.dart';
import 'package:yogotv/video_playback_session.dart';

Future main() async {
  WidgetsBinding widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(
    SystemUiMode.manual,
    overlays: [SystemUiOverlay.top],
  );
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

  await Global.init();
  final savedLocale = Global.sp.getString('locale');
  if (savedLocale == null) {
    await LocaleSettings.setLocale(AppLocale.en);
  } else {
    await LocaleSettings.setLocaleRaw(savedLocale);
  }
  if (!kIsWeb && !Global.webPreview) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }

  runApp(TranslationProvider(child: App()));
  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(_initTrackingAfterAppBecomesActive());
  });
}

Future<void> _initTrackingAfterAppBecomesActive() async {
  if (!kIsWeb &&
      WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
    final resumed = Completer<void>();
    late final AppLifecycleListener listener;
    listener = AppLifecycleListener(
      onResume: () {
        if (!resumed.isCompleted) {
          resumed.complete();
        }
      },
    );
    try {
      await resumed.future.timeout(const Duration(seconds: 10));
    } on TimeoutException {
      Global.logger.d(
        'Timed out waiting for the app to become active before ATT',
      );
    } finally {
      listener.dispose();
    }
  }

  await Global.initTracking();
  await AdjustTracking.init();
}

final _router = GoRouter(
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) {
        return Main();
      },
    ),
    GoRoute(
      path: '/alert',
      pageBuilder: (context, state) {
        final params = state.extra as dynamic;
        return Alert(
          key: state.pageKey,
          title: params['title'],
          content: params['content'],
        );
      },
    ),
    GoRoute(
      path: '/play',
      builder: (context, state) {
        final data = state.extra as Map<String, dynamic>;
        return Play(
          key: ValueKey(data['openId'] ?? state.pageKey),
          id: data['id'],
          watchTo: data['watchTo'],
        );
      },
    ),
    GoRoute(
      path: '/search',
      builder: (context, state) {
        return Search();
      },
    ),
    GoRoute(
      path: '/label',
      builder: (context, state) {
        final data = state.extra as Map<String, dynamic>? ?? {};
        final query = state.uri.queryParameters;
        return LabelVideo(
          title: query['title'] ?? data['title']?.toString() ?? '',
          tagId: query['tag'] ?? query['id'] ?? data['id']?.toString() ?? '',
        );
      },
    ),
    GoRoute(
      path: '/login',
      builder: (context, state) {
        return _previewRoute(Login());
      },
    ),
    GoRoute(
      path: '/language',
      builder: (context, state) {
        return Language();
      },
    ),
    GoRoute(
      path: '/about',
      builder: (context, state) {
        return About();
      },
    ),
    GoRoute(
      path: '/settings',
      builder: (context, state) {
        return Settings();
      },
    ),
    GoRoute(
      path: '/delete-account',
      builder: (context, state) {
        return DeleteAccount();
      },
    ),
    GoRoute(
      path: '/help',
      builder: (context, state) {
        return Help();
      },
    ),
    GoRoute(
      path: '/wallet',
      builder: (context, state) {
        return Wallet();
      },
    ),
    GoRoute(
      path: '/wallet/history',
      builder: (context, state) {
        return WalletHistory(type: state.extra as int? ?? 1);
      },
    ),
    GoRoute(
      path: '/membership',
      builder: (context, state) {
        return _previewRoute(Membership());
      },
    ),
    GoRoute(
      path: '/top-up',
      builder: (context, state) {
        return _previewRoute(
          TopUpPage(episodeCoins: state.extra?.toString() ?? '0'),
        );
      },
    ),
    GoRoute(
      path: '/earn/detail',
      builder: (context, state) {
        return EarnDetail();
      },
    ),
    GoRoute(
      path: '/earn/withdraw',
      builder: (context, state) {
        return EarnWithdraw();
      },
    ),
    GoRoute(
      path: '/recommend',
      builder: (context, state) {
        return Recommend();
      },
    ),
    GoRoute(
      path: '/airwallex',
      builder: (context, state) {
        return Airwallex(
          product: (state.extra as Map<String, dynamic>)['product'] as int,
        );
      },
    ),
  ],
  observers: [BotToastNavigatorObserver()],
);

Widget _previewRoute(Widget child) {
  return _WebPreviewFrame(fillHeight: true, child: child);
}

class App extends StatefulWidget {
  const App({super.key});

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> {
  late final DeepLinkHandler _deepLinkHandler;

  @override
  void initState() {
    super.initState();
    _deepLinkHandler = DeepLinkHandler(_router);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_deepLinkHandler.init());
    });
  }

  @override
  void dispose() {
    unawaited(_deepLinkHandler.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider<RestartState>(
          create: (context) {
            return RestartState();
          },
        ),
        BlocProvider<MainState>(
          create: (context) {
            return MainState();
          },
        ),
        BlocProvider<UserState>(
          create: (context) {
            return UserState(Global.cachedUserState());
          },
        ),
      ],
      child: MaterialApp.router(
        key: Global.appKey,
        debugShowCheckedModeBanner: false,
        scrollBehavior: const _YogoScrollBehavior(),
        builder: (context, child) {
          child = BotToastInit()(context, child);
          return _AppViewportFrame(fillHeight: true, child: child);
        },
        theme: ThemeData(
          splashColor: Color(0x05ffffff),
          hintColor: Colors.transparent,
          highlightColor: Colors.transparent,
          scaffoldBackgroundColor: Colors.black,
          colorScheme: ColorScheme.dark(
            primary: Color(0xffff3d5d),
            secondaryContainer: Color(0xff666666),
            onSecondaryContainer: Colors.white,
            onPrimary: Colors.white,
          ),
          appBarTheme: AppBarTheme(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            surfaceTintColor: Colors.transparent,
            systemOverlayStyle: SystemUiOverlayStyle(
              statusBarBrightness: Brightness.dark,
              // statusBarColor: Colors.white,
            ),
          ),
          bottomNavigationBarTheme: BottomNavigationBarThemeData(
            selectedItemColor: Color(0xffff3d5d),
            backgroundColor: Colors.black,
          ),
          dividerTheme: DividerThemeData(color: Color(0x10ffffff)),
          inputDecorationTheme: InputDecorationTheme(
            border: OutlineInputBorder(
              borderSide: BorderSide(width: 0),
              gapPadding: 0,
              borderRadius: BorderRadius.circular(8),
            ),
            enabledBorder: OutlineInputBorder(
              borderSide: BorderSide(width: 0),
              gapPadding: 0,
              borderRadius: BorderRadius.circular(8),
            ),
            focusedBorder: OutlineInputBorder(
              borderSide: BorderSide(width: 0),
              gapPadding: 0,
              borderRadius: BorderRadius.circular(8),
            ),
            disabledBorder: OutlineInputBorder(
              borderSide: BorderSide(width: 0),
              gapPadding: 0,
              borderRadius: BorderRadius.circular(8),
            ),
            hintStyle: TextStyle(
              fontSize: 16,
              height: 1,
              color: Colors.white38,
            ),
            focusColor: Colors.white12,
            fillColor: Colors.transparent,
            filled: false,
            prefixIconColor: Colors.white54,
          ),
          buttonTheme: ButtonThemeData(
            splashColor: Color(0x05ffffff),
            highlightColor: Colors.transparent,
          ),
          tabBarTheme: TabBarThemeData(
            overlayColor: WidgetStateColor.resolveWith((state) {
              return Colors.transparent;
            }),
          ),
        ),
        locale: TranslationProvider.of(context).flutterLocale,
        supportedLocales: AppLocaleUtils.supportedLocales,
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        routerDelegate: _router.routerDelegate,
        routeInformationProvider: _router.routeInformationProvider,
        routeInformationParser: _router.routeInformationParser,
      ),
    );
  }
}

class _YogoScrollBehavior extends MaterialScrollBehavior {
  const _YogoScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    final platform = getPlatform(context);
    if (platform == TargetPlatform.iOS || platform == TargetPlatform.macOS) {
      return const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      );
    }
    return super.getScrollPhysics(context);
  }
}

class Main extends StatefulWidget {
  const Main({super.key});

  @override
  State<StatefulWidget> createState() {
    return _Main();
  }
}

class _Main extends State<Main> {
  final channel = MethodChannel('yogotv.com/channel');
  StreamSubscription<RestartStateValue>? _restartListener;
  StreamSubscription<void>? _adjustAttributionListener;
  Timer? _aliveTimer;
  final Set<int> _loadedTabs = {0, 1};
  bool _loading = true;
  bool _appServicesReady = false;
  bool _appIsForeground = true;
  bool _aliveRequestInFlight = false;
  bool _adjustTokenRefreshInFlight = false;
  bool _adjustTokenRefreshPending = false;
  bool _adjustAttributionPollingStarted = false;
  // bool _initialized = false;

  late final AppLifecycleListener _lifecycleListener;

  @override
  void dispose() {
    _restartListener?.cancel();
    _adjustAttributionListener?.cancel();
    _stopAliveHeartbeat();
    _lifecycleListener.dispose();
    Purchase.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();

    _lifecycleListener = AppLifecycleListener(
      onHide: () {
        Global.logger.d('hide');
        _appIsForeground = false;
        _stopAliveHeartbeat();
      },
      onPause: () {
        Global.logger.d('pause');
        _appIsForeground = false;
        _stopAliveHeartbeat();
        Global.pause();
      },
      onResume: () {
        Global.logger.d('resume');
        _appIsForeground = true;
        Global.resume();
        _startAliveHeartbeat();
        unawaited(_refreshAdjustAttributionFromSdk());
        // if (!_initialized || !Global.canShowAd()) {
        //   return;
        // }
        // final close = Global.loading();
        // interstitialAd((complete) {
        //   close();
        // });
      },
    );
    final locale = Global.sp.getString('locale');
    if (locale != null) {
      LocaleSettings.setLocaleRaw(locale);
    }
    Global.elapsed('App initialized');
    FlutterNativeSplash.remove();
    _restartListener = context.read<RestartState>().stream.listen((value) {
      if (!mounted) {
        return;
      }
      VideoPlaybackSession.silenceAllNow();
      context.read<MainState>().setIndex(0);
      while (context.canPop()) {
        context.pop();
      }
    });
    _adjustAttributionListener = AdjustTracking.attributionUpdates.listen((_) {
      unawaited(_refreshTokenAfterAdjustAttribution());
    });
    if (kIsWeb || Global.webPreview) {
      _appServicesReady = true;
      _startAliveHeartbeat();
      setState(() {
        _loading = false;
      });
      return;
    }
    unawaited(_startAppServices());
  }

  Future<void> _startAppServices() async {
    await AdjustTracking.waitForAdid(timeout: const Duration(seconds: 3));
    await AdjustTracking.waitForAttribution(
      timeout: const Duration(seconds: 3),
    );
    if (!mounted) {
      return;
    }
    await Global.restoreSession(context);
    if (!mounted) {
      return;
    }
    unawaited(_refreshTokenAfterAdjustAttribution());
    unawaited(_pollAdjustAttributionUntilResolved());
    final shouldPreloadIntroEligibility = !context.read<UserState>().isVip;
    await Purchase.init();
    if (shouldPreloadIntroEligibility) {
      unawaited(Purchase.preloadMembershipIntroductoryOfferEligibility());
      unawaited(Purchase.preloadRetentionIntroductoryOfferEligibility());
    }
    _appServicesReady = true;
    _startAliveHeartbeat();
    if (mounted) {
      setState(() {
        _loading = false;
        // _initialized = true;
      });
    }

    try {
      await MobileAds.instance.initialize();
      Global.elapsed('Mobile Ads initialized');
      await MobileAds.instance.updateRequestConfiguration(
        RequestConfiguration(
          testDeviceIds: ['6AC6039CD7E9873F6F9A0B635B9434A1'],
        ),
      );
      Global.elapsed('Mobile Ads configuration finished');
    } catch (error) {
      Global.logger.d('mobile ads init skipped: $error');
    }

    api('config')
        .then((res) async {
          if (res.d['tiktok_event']['enable'] != true) {
            return;
          }

          try {
            await TikTokEventsSdk.initSdk(
              androidAppId: res.d['tiktok_event']['android_app_id'],
              tikTokAndroidId: res.d['tiktok_event']['tiktok_android_id'],
              iosAppId: res.d['tiktok_event']['ios_app_id'],
              tiktokIosId: res.d['tiktok_event']['tiktok_ios_id'],
              isDebugMode: kDebugMode,
              logLevel: kDebugMode ? TikTokLogLevel.debug : TikTokLogLevel.info,
              iosOptions: TikTokIosOptions(
                disableTracking: Global.tracking ? false : true,
                disableAutomaticTracking: true,
                disableSKAdNetworkSupport: true,
                accessToken: res.d['tiktok_event']['ios_token'],
              ),
              androidOptions: TikTokAndroidOptions(
                disableAutoStart: true,
                enableAutoIapTrack: true,
                disableAdvertiserIDCollection: false,
              ),
            );
            Global.logger.d('tiktok initialized');
          } catch (error) {
            Global.logger.d('tiktok init skipped: $error');
          }
          // TikTokEventsSdk.logEvent(
          //   event: TikTokEvent(eventName: 'launch_app'),
          // );
        })
        .catchError((error) {
          Global.logger.d('tiktok config skipped: $error');
        });
  }

  Future<void> _refreshTokenAfterAdjustAttribution() async {
    if (kIsWeb || Global.webPreview) {
      return;
    }
    _adjustTokenRefreshPending = true;
    if (_adjustTokenRefreshInFlight) {
      return;
    }
    _adjustTokenRefreshInFlight = true;
    try {
      while (_adjustTokenRefreshPending && mounted) {
        _adjustTokenRefreshPending = false;
        Global.logger.d('adjust token sync waiting for attribution');
        final hasAdid = await AdjustTracking.waitForAdid(
          timeout: const Duration(seconds: 3),
        );
        await AdjustTracking.waitForAttribution(
          timeout: const Duration(seconds: 3),
        );
        final shouldSync =
            hasAdid &&
            mounted &&
            AdjustTracking.shouldRefreshTokenForCurrentAdid;
        if (!shouldSync) {
          Global.logger.d(
            'adjust token sync skipped hasAdid=$hasAdid mounted=$mounted shouldSync=$shouldSync',
          );
          continue;
        }
        final value = await Global.refreshTokenAfterAdjustAdid();
        if (!mounted || value == null) {
          Global.logger.d('adjust token sync finished without user update');
          continue;
        }
        Global.logger.d('adjust token sync applied');
        context.read<UserState>().set(value);
        if (context.read<MainState>().state.current == 0) {
          refreshHomePopularAfterAttributionSync();
        }
      }
    } finally {
      _adjustTokenRefreshInFlight = false;
      if (_adjustTokenRefreshPending && mounted) {
        unawaited(_refreshTokenAfterAdjustAttribution());
      }
    }
  }

  Future<void> _refreshAdjustAttributionFromSdk() async {
    await AdjustTracking.refreshAttribution();
    if (!mounted) {
      return;
    }
    await _refreshTokenAfterAdjustAttribution();
  }

  Future<void> _pollAdjustAttributionUntilResolved() async {
    if (_adjustAttributionPollingStarted) {
      return;
    }
    _adjustAttributionPollingStarted = true;
    const retryDelays = <Duration>[
      Duration(seconds: 5),
      Duration(seconds: 15),
      Duration(seconds: 30),
      Duration(minutes: 1),
      Duration(minutes: 2),
      Duration(minutes: 5),
      Duration(minutes: 10),
      Duration(minutes: 15),
    ];
    for (final delay in retryDelays) {
      if (!mounted || !AdjustTracking.attributionNeedsRefresh) {
        return;
      }
      await Future<void>.delayed(delay);
      if (!mounted) {
        return;
      }
      await _refreshAdjustAttributionFromSdk();
    }
  }

  void _startAliveHeartbeat() {
    if (!_appServicesReady || !_appIsForeground) {
      return;
    }
    _aliveTimer?.cancel();
    unawaited(_pingAlive());
    _aliveTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      unawaited(_pingAlive());
    });
  }

  void _stopAliveHeartbeat() {
    _aliveTimer?.cancel();
    _aliveTimer = null;
  }

  Future<void> _pingAlive() async {
    if (_aliveRequestInFlight) {
      return;
    }
    _aliveRequestInFlight = true;
    try {
      final result = await api<dynamic>(
        'alive',
        method: Method.post,
        loading: false,
        showError: false,
      );
      if (result.c != 0) {
        Global.logger.d('alive failed c=${result.c} m=${result.m}');
      }
    } catch (error) {
      Global.logger.d('alive failed: $error');
    } finally {
      _aliveRequestInFlight = false;
    }
  }

  void _handleChangeIndex(int value) {
    final current = context.read<MainState>().state.current;
    if (current != value) {
      VideoPlaybackSession.silenceAllNow();
    }
    setState(() {
      _loadedTabs.add(value);
    });
    context.read<MainState>().setIndex(value);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        channel.invokeMethod('moveToBack');
      },
      child: _loading
          ? Splash()
          : BlocBuilder<MainState, MainStateValue>(
              builder: (context, state) {
                return Scaffold(
                  body: _AppViewportFrame(
                    fillHeight: true,
                    child: IndexedStack(
                      index: state.current,
                      children: [
                        _loadedTabs.contains(0) ? Home() : SizedBox.shrink(),
                        _loadedTabs.contains(1)
                            ? Recommend(active: state.current == 1)
                            : SizedBox.shrink(),
                        _loadedTabs.contains(2)
                            ? MyList(load: state.current == 2)
                            : SizedBox.shrink(),
                        _loadedTabs.contains(3)
                            ? Profile(active: state.current == 3)
                            : SizedBox.shrink(),
                      ],
                    ),
                  ),
                  bottomNavigationBar: _AppViewportFrame(
                    child: _MainBottomNavigation(
                      currentIndex: state.current,
                      onTap: _handleChangeIndex,
                    ),
                  ),
                );
              },
            ),
    );
  }
}

class _MainBottomNavigation extends StatelessWidget {
  const _MainBottomNavigation({
    required this.currentIndex,
    required this.onTap,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final items = [
      _BottomTabData(icon: 1, label: t.home),
      _BottomTabData(icon: 2, label: t.for_you),
      _BottomTabData(icon: 3, label: t.my_list),
      _BottomTabData(icon: 4, label: t.profile),
    ];

    return ColoredBox(
      color: Colors.black,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 48,
          child: Row(
            children: List.generate(items.length, (index) {
              final item = items[index];
              final selected = index == currentIndex;
              return Expanded(
                child: InkWell(
                  onTap: () => onTap(index),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _BottomTabIcon(id: item.icon, active: selected),
                      SizedBox(height: 2),
                      Text(
                        item.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: selected
                              ? Color(0xffff3d5d)
                              : Color(0xff999999),
                          fontSize: 10,
                          height: 1,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

class _BottomTabData {
  const _BottomTabData({required this.icon, required this.label});

  final int icon;
  final String label;
}

class _BottomTabIcon extends StatelessWidget {
  const _BottomTabIcon({required this.id, this.active = false});

  final int id;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      'assets/images/android/main_tab_$id${active ? 1 : 0}.svg',
      width: 24,
      height: 24,
      fit: BoxFit.contain,
    );
  }
}

class _AppViewportFrame extends StatelessWidget {
  const _AppViewportFrame({required this.child, this.fillHeight = false});

  static const double maxWidth = 480.0;

  final Widget child;
  final bool fillHeight;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.maybeOf(context);
    if (media == null || media.size.width <= maxWidth) {
      return child;
    }

    final framedMedia = media.copyWith(size: Size(maxWidth, media.size.height));

    final framed = MediaQuery(
      data: framedMedia,
      child: SizedBox(
        width: maxWidth,
        height: fillHeight ? media.size.height : null,
        child: child,
      ),
    );

    return ColoredBox(
      color: Colors.black,
      child: Align(
        alignment: fillHeight ? Alignment.topCenter : Alignment.center,
        widthFactor: fillHeight ? null : 1,
        heightFactor: fillHeight ? null : 1,
        child: framed,
      ),
    );
  }
}

class _WebPreviewFrame extends StatelessWidget {
  const _WebPreviewFrame({required this.child, this.fillHeight = false});

  final Widget child;
  final bool fillHeight;

  @override
  Widget build(BuildContext context) {
    if (!Global.webPreview) {
      return child;
    }

    final size = MediaQuery.sizeOf(context);
    final width = size.width > _AppViewportFrame.maxWidth
        ? _AppViewportFrame.maxWidth
        : size.width;
    final framed = SizedBox(width: width, child: child);

    if (!fillHeight) {
      return ColoredBox(
        color: Colors.black,
        child: Align(
          alignment: Alignment.center,
          widthFactor: 1,
          heightFactor: 1,
          child: framed,
        ),
      );
    }

    return ColoredBox(
      color: Colors.black,
      child: Align(
        alignment: Alignment.topCenter,
        child: SizedBox(width: width, height: size.height, child: child),
      ),
    );
  }
}

extension EmailValidator on String {
  bool get isValidEmail {
    final RegExp emailRegex = RegExp(
      r'^[\w-]+(\.[\w-]+)*@([\w-]+\.)+[a-zA-Z]{2,7}$',
    );
    return emailRegex.hasMatch(this);
  }
}
