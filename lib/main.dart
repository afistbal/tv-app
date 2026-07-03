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
import 'package:internet_connection_checker_plus/internet_connection_checker_plus.dart';
import 'package:tiktok_events_sdk/tiktok_events_sdk.dart';
import 'package:yogotv/api.dart';
import 'package:yogotv/pages/alert.dart';
import 'package:yogotv/firebase_options.dart' show DefaultFirebaseOptions;
import 'package:yogotv/global.dart';
import 'package:yogotv/i18n/strings.g.dart';
import 'package:yogotv/pages/about.dart';
import 'package:yogotv/pages/admin.dart';
import 'package:yogotv/pages/airwallex.dart';
import 'package:yogotv/pages/earn_detail.dart';
import 'package:yogotv/pages/earn_withdraw.dart';
import 'package:yogotv/pages/home.dart';
import 'package:yogotv/pages/language.dart';
import 'package:yogotv/pages/login.dart';
import 'package:yogotv/pages/membership.dart';
import 'package:yogotv/pages/my_list.dart';
import 'package:yogotv/pages/profile.dart';
import 'package:yogotv/pages/recommend.dart';
import 'package:yogotv/pages/search.dart';
import 'package:yogotv/pages/play.dart';
import 'package:yogotv/pages/help.dart';
import 'package:yogotv/purchase.dart';
import 'package:yogotv/splash.dart';
import 'package:yogotv/states/main.dart';
import 'package:yogotv/states/restart.dart';
import 'package:yogotv/states/user.dart';

Future main() async {
  WidgetsBinding widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(
    SystemUiMode.manual,
    overlays: [SystemUiOverlay.top],
  );
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

  while (!await InternetConnection().hasInternetAccess) {
    await Future.delayed(Duration(seconds: 1));
  }

  await Global.init();
  final savedLocale = Global.sp.getString('locale');
  if (savedLocale == null) {
    await LocaleSettings.setLocale(AppLocale.en);
  } else {
    await LocaleSettings.setLocaleRaw(savedLocale);
  }
  if (!Global.webPreview) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }

  runApp(TranslationProvider(child: App()));
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
        return Play(id: data['id'], watchTo: data['watchTo']);
      },
    ),
    GoRoute(
      path: '/search',
      builder: (context, state) {
        return Search();
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
      path: '/help',
      builder: (context, state) {
        return Help();
      },
    ),
    GoRoute(
      path: '/membership',
      builder: (context, state) {
        return _previewRoute(Membership());
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
      path: '/admin',
      builder: (context, state) {
        return Admin();
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

class App extends StatelessWidget {
  const App({super.key});

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
            return UserState();
          },
        ),
      ],
      child: MaterialApp.router(
        key: Global.appKey,
        debugShowCheckedModeBanner: false,
        builder: (context, child) {
          child = BotToastInit()(context, child);
          return child;
        },
        theme: ThemeData(
          splashColor: Color(0x05ffffff),
          hintColor: Colors.transparent,
          highlightColor: Colors.transparent,
          scaffoldBackgroundColor: Color(0xff151515),
          colorScheme: ColorScheme.dark(
            primary: Color.fromARGB(255, 239, 68, 68),
            secondaryContainer: Color(0xff666666),
            onSecondaryContainer: Colors.white,
            onPrimary: Colors.white,
          ),
          appBarTheme: AppBarTheme(
            backgroundColor: Color(0xff111111),
            foregroundColor: Colors.white,
            surfaceTintColor: Colors.transparent,
            systemOverlayStyle: SystemUiOverlayStyle(
              statusBarBrightness: Brightness.dark,
              // statusBarColor: Colors.white,
            ),
          ),
          bottomNavigationBarTheme: BottomNavigationBarThemeData(
            selectedItemColor: Color.fromARGB(255, 239, 68, 68),
            backgroundColor: Color(0xff111111),
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
            fillColor: Color(0x10ffffff),
            filled: true,
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
  bool _loading = true;
  // bool _initialized = false;

  late final AppLifecycleListener _lifecycleListener;

  @override
  void dispose() {
    _restartListener?.cancel();
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
      },
      onPause: () {
        Global.logger.d('pause');
        Global.pause();
      },
      onResume: () {
        Global.logger.d('resume');
        Global.resume();
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
    if (Global.webPreview) {
      setState(() {
        _loading = false;
      });
      return;
    }
    MobileAds.instance.initialize().then((status) async {
      Global.elapsed('Mobile Ads initialized');
      await MobileAds.instance.updateRequestConfiguration(
        RequestConfiguration(
          testDeviceIds: ['6AC6039CD7E9873F6F9A0B635B9434A1'],
        ),
      );
      Global.elapsed('Mobile Ads configuration finished');
      // splashAd((status) {
      //   Global.login(context).then((signed) {
      //     if (!signed) {
      //       return;
      //     }
      //     setState(() {
      //       _loading = false;
      //       _initialized = true;
      //     });
      //   });
      // });

      if (mounted) {
        Global.login(context)
            .then((signed) {
              if (!signed) {
                return;
              }
              setState(() {
                _loading = false;
                // _initialized = true;
              });
            })
            .then((_) async {
              await Purchase.init();
              api('config').then((res) async {
                if (res.d['tiktok_event']['enable'] != true) {
                  return;
                }

                await TikTokEventsSdk.initSdk(
                  androidAppId: res.d['tiktok_event']['android_app_id'],
                  tikTokAndroidId: res.d['tiktok_event']['tiktok_android_id'],
                  iosAppId: res.d['tiktok_event']['ios_app_id'],
                  tiktokIosId: res.d['tiktok_event']['tiktok_ios_id'],
                  isDebugMode: kDebugMode,
                  logLevel: kDebugMode
                      ? TikTokLogLevel.debug
                      : TikTokLogLevel.info,
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
                // TikTokEventsSdk.logEvent(
                //   event: TikTokEvent(eventName: 'launch_app'),
                // );
              });
            });
      }
    });

    _restartListener = context.read<RestartState>().stream.listen((
      value,
    ) async {
      if (!mounted) {
        return;
      }
      while (context.canPop()) {
        context.pop();
      }
      setState(() {
        _loading = true;
      });
      context.read<MainState>().setIndex(0);
      await Future.delayed(Duration(seconds: 1));
      setState(() {
        _loading = false;
      });
    });
  }

  void _handleChangeIndex(int value) {
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
                  body: _WebPreviewFrame(
                    fillHeight: true,
                    child: IndexedStack(
                      index: state.current,
                      children: [
                        Home(),
                        Recommend(),
                        MyList(load: state.current == 2),
                        Profile(),
                      ],
                    ),
                  ),
                  bottomNavigationBar: _WebPreviewFrame(
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
    final width = size.width > 480 ? 480.0 : size.width;
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
