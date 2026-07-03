import 'dart:async';
import 'package:app_tracking_transparency/app_tracking_transparency.dart';
import 'package:bot_toast/bot_toast.dart';
import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';
import 'package:logger/logger.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yogotv/api.dart';
import 'package:yogotv/app_config.dart';
import 'package:yogotv/states/user.dart';

class Global {
  static const bool webPreview =
      kIsWeb && bool.fromEnvironment('YOGO_WEB_PREVIEW');
  static final GlobalKey appKey = GlobalKey();
  static final Logger logger = Logger(level: Level.debug);
  static final int time = DateTime.now().millisecondsSinceEpoch;
  static late final SharedPreferences sp;
  static late final Dio dio;
  static late final PackageInfo packageInfo;
  static late final Map<String, dynamic>? config;
  static late final bool tracking;
  static bool paused = false;
  static int _pauseAt = 0;
  static bool _blockedAd = false;

  static init() async {
    sp = await SharedPreferences.getInstance();

    if (webPreview) {
      tracking = false;
    } else {
      if (await AppTrackingTransparency.trackingAuthorizationStatus ==
          TrackingStatus.notDetermined) {
        final authorization =
            await AppTrackingTransparency.requestTrackingAuthorization();
        logger.d(authorization);
      }
      final status = await Permission.appTrackingTransparency.request();
      logger.d(status);
      tracking = status.isGranted;
      logger.d('Tracking is $tracking');
      logger.d(
        'IDFA is ${await AppTrackingTransparency.getAdvertisingIdentifier()}',
      );
    }

    dio = Dio(
      BaseOptions(
        baseUrl: AppConfig.apiBaseUrl,
        responseType: ResponseType.json,
      ),
    );

    if (kDebugMode) {
      dio.interceptors.add(
        LogInterceptor(
          requestHeader: true,
          requestBody: true,
          responseHeader: true,
          responseBody: true,
        ),
      );
    }

    packageInfo = await PackageInfo.fromPlatform();

    if (webPreview) {
      await _ensureWebPreviewSession();
    }

    while (true) {
      try {
        if ((await dio.get('ping')).data == 'ok') {
          break;
        }
      } on Exception catch (e) {
        logger.d(e);
      }
      await Future.delayed(Duration(seconds: 1));
    }

    final result = await api<Map<String, dynamic>>('config', loading: false);
    config = result.d;
  }

  static Future<void> _ensureWebPreviewSession() async {
    var deviceUuid = sp.getString('device_uuid') ?? '';
    if (deviceUuid.isEmpty) {
      deviceUuid =
          'flutter-web-${DateTime.now().millisecondsSinceEpoch}-${Object().hashCode}';
      await sp.setString('device_uuid', deviceUuid);
    }

    final token = sp.getString('token') ?? '';
    if (token.isNotEmpty) {
      final result = await api<Map<String, dynamic>>(
        'login/token',
        method: Method.post,
        data: {'token': token, 'device_uuid': deviceUuid},
        loading: false,
      );
      if (result.c == 0) {
        return;
      }
      await sp.remove('token');
    }

    final result = await api<Map<String, dynamic>>(
      'login/anonymous',
      method: Method.post,
      data: {'device_uuid': deviceUuid},
      loading: false,
    );
    final tokenValue = result.d?['token']?.toString() ?? '';
    if (result.c == 0 && tokenValue.isNotEmpty) {
      await sp.setString('token', tokenValue);
    }
  }

  static void blockAd() {
    _blockedAd = true;
  }

  static void allowAd() {
    _blockedAd = false;
  }

  static void pause() {
    paused = true;
    _pauseAt = DateTime.now().millisecondsSinceEpoch;
  }

  static void resume() {
    paused = false;
  }

  static bool canShowAd() {
    return paused &&
        !_blockedAd &&
        _pauseAt + 10000 < DateTime.now().millisecondsSinceEpoch;
  }

  static void elapsed(String message) {
    logger.d(
      '${((DateTime.now().millisecondsSinceEpoch - time) / 1000).toStringAsFixed(2)}s, $message',
    );
  }

  static String static(String name) {
    final path = name.trim();
    if (path.startsWith('http://') || path.startsWith('https://')) {
      return path;
    }
    if (path.startsWith('//')) {
      return 'https:$path';
    }
    final staticBase = '${config!['static']}'.replaceFirst(RegExp(r'/+$'), '');
    final normalizedBase = staticBase.startsWith('//')
        ? 'https:$staticBase'
        : staticBase;
    return '$normalizedBase/${path.replaceFirst(RegExp(r'^/+'), '')}';
  }

  static void Function() loading() {
    return BotToast.showCustomLoading(
      backButtonBehavior: BackButtonBehavior.ignore,
      toastBuilder: (cancel) {
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            LoadingAnimationWidget.discreteCircle(color: Colors.red, size: 32),
          ],
        );
      },
    );
  }

  static void Function() info(String message, {Icon? icon}) {
    return BotToast.showCustomText(
      toastBuilder: (cancel) {
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              padding: EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.black87,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                spacing: 8,
                children: [
                  if (icon != null) icon,
                  Text(message, style: TextStyle(fontSize: 16)),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  static void Function() success(String message) {
    return BotToast.showCustomText(
      toastBuilder: (cancel) {
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              padding: EdgeInsets.symmetric(vertical: 16, horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.black87,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                spacing: 8,
                children: [
                  Icon(
                    LucideIcons.circleCheck200,
                    size: 48,
                    color: Colors.green,
                  ),
                  Text(message, style: TextStyle(fontSize: 16)),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  static void Function() error(String message) {
    return BotToast.showCustomText(
      toastBuilder: (cancel) {
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              padding: EdgeInsets.symmetric(vertical: 16, horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.black87,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                spacing: 8,
                children: [
                  Icon(LucideIcons.circleX200, size: 48, color: Colors.red),
                  Text(message, style: TextStyle(fontSize: 16)),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  static void Function() warning(String message) {
    return BotToast.showCustomText(
      toastBuilder: (cancel) {
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              padding: EdgeInsets.symmetric(vertical: 16, horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.black87,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                spacing: 8,
                children: [
                  Icon(
                    LucideIcons.circleAlert200,
                    size: 48,
                    color: Colors.amber,
                  ),
                  Text(message, style: TextStyle(fontSize: 16)),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  static Future<bool> login(BuildContext context) async {
    try {
      if (FirebaseAuth.instance.currentUser == null) {
        await FirebaseAuth.instance.signInAnonymously();
      }

      Global.logger.d('${FirebaseAuth.instance.currentUser}');

      Future<Result<dynamic>> uidLogin() async {
        return await api(
          'login/uid',
          method: Method.post,
          data: {
            'uid': FirebaseAuth.instance.currentUser?.uid,
            'anonymous':
                (FirebaseAuth.instance.currentUser?.isAnonymous ?? true)
                ? 1
                : 0,
            'name': FirebaseAuth.instance.currentUser?.displayName,
            'email': FirebaseAuth.instance.currentUser?.email,
          },
        );
      }

      Result<dynamic>? result;
      var count = 0;

      do {
        if (count > 1) {
          break;
        }
        count += 1;
        result = await uidLogin();
      } while (result.c != 0);

      if (result == null || result.c != 0) {
        Global.info('${FirebaseAuth.instance.currentUser}');
        return false;
      }

      Global.sp.setString('uid', FirebaseAuth.instance.currentUser!.uid);
      await Global.sp.setString('token', result.d['token']);

      if (context.mounted) {
        context.read<UserState>().set(
          UserStateValue(
            name: result.d['info']['name'] ?? 'No Name',
            uniqueId: result.d['info']['unique_id'],
            password: result.d['info']['password'],
            vip: result.d['info']['vip'],
            admin: result.d['info']['admin'],
            anonymous: result.d['info']['anonymous'],
          ),
        );
      }

      return true;
    } on Exception catch (e) {
      Global.logger.d(e);
      Global.error('Oops! Something went wrong.');
      return false;
    }
  }

  static Future<bool> logout(BuildContext context) async {
    sp.remove('token');
    sp.remove('uid');
    context.read<UserState>().signout();
    await FirebaseAuth.instance.signOut();
    if (context.mounted) {
      await login(context);
    }

    return true;
  }
}
