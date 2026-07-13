import 'dart:async';
import 'dart:convert';
import 'package:bot_toast/bot_toast.dart';
import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter/services.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';
import 'package:logger/logger.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yogotv/adjust_tracking.dart';
import 'package:yogotv/api.dart';
import 'package:yogotv/app_config.dart';
import 'package:yogotv/i18n/strings.g.dart';
import 'package:yogotv/states/user.dart';

class Global {
  static const bool webPreview =
      kIsWeb && bool.fromEnvironment('YOGO_WEB_PREVIEW');
  static const bool apiVerboseLogs = bool.fromEnvironment('API_VERBOSE_LOGS');
  static const MethodChannel _deviceChannel = MethodChannel(
    'yogotv.com/device',
  );
  static final GlobalKey appKey = GlobalKey();
  static final Logger logger = Logger(level: Level.debug);
  static final int time = DateTime.now().millisecondsSinceEpoch;
  static late final SharedPreferences sp;
  static late final Dio dio;
  static late final PackageInfo packageInfo;
  static Map<String, dynamic>? config;
  static bool tracking = false;
  static bool paused = false;
  static int _pauseAt = 0;
  static bool _blockedAd = false;
  static const String _userInfoKey = 'user_info';
  static const String _avatarUrlKey = 'avatar_url';
  static const String _apiBaseUrlKey = 'api_base_url';
  static const String _fallbackStaticBase = 'https://cos.yogoshort.com';

  static init() async {
    sp = await SharedPreferences.getInstance();
    await _resetSessionWhenApiBaseChanged();

    dio = Dio(
      BaseOptions(
        baseUrl: AppConfig.apiBaseUrl,
        responseType: ResponseType.json,
        connectTimeout: const Duration(seconds: 15),
        sendTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 20),
      ),
    );

    if (kDebugMode && apiVerboseLogs) {
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

    if (kIsWeb || webPreview) {
      await _ensureWebPreviewSession();
    }

    unawaited(refreshConfig());
  }

  static Future<void> _resetSessionWhenApiBaseChanged() async {
    final currentBase = AppConfig.apiBaseUrl;
    final cachedBase = sp.getString(_apiBaseUrlKey) ?? '';
    if (cachedBase.isNotEmpty && cachedBase != currentBase) {
      await sp.remove('token');
      await sp.remove('uid');
      await sp.remove(_userInfoKey);
      await sp.remove(_avatarUrlKey);
      logger.d('api base changed, cleared cached session');
    }
    if (cachedBase != currentBase) {
      await sp.setString(_apiBaseUrlKey, currentBase);
    }
  }

  static Future<void> initTracking() async {
    if (kIsWeb) {
      tracking = false;
    } else {
      final status = await Permission.appTrackingTransparency.request();
      logger.d(status);
      tracking = status.isGranted;
      logger.d('Tracking is $tracking');
    }
  }

  static Future<void> refreshConfig() async {
    final result = await api<Map<String, dynamic>>(
      'config',
      loading: false,
      showError: false,
    );
    if (result.c == 0 && result.d != null) {
      config = result.d;
    }
  }

  static Future<void> _ensureWebPreviewSession() async {
    final deviceUuid = await Global.deviceUuid();

    final token = sp.getString('token') ?? '';
    if (token.isNotEmpty) {
      final result = await api<Map<String, dynamic>>(
        'login/token',
        method: Method.post,
        data: {'token': token, 'device_uuid': deviceUuid},
        loading: false,
        showError: false,
      );
      if (result.c == 0) {
        await cacheUserInfo(result.d);
        return;
      }
      if (result.m == 'Authentication Failure.') {
        await sp.remove('token');
      } else if (cachedUserState() != null) {
        return;
      }
    }

    final result = await api<Map<String, dynamic>>(
      'login/anonymous',
      method: Method.post,
      data: {'device_uuid': deviceUuid},
      loading: false,
      showError: false,
    );
    final tokenValue = result.d?['token']?.toString() ?? '';
    if (result.c == 0 && tokenValue.isNotEmpty) {
      await cacheUserInfo(
        result.d?['info'],
        token: tokenValue,
        clearAvatar: true,
      );
    }
  }

  static Future<String> deviceUuid() async {
    final cached = sp.getString('device_uuid') ?? '';
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      try {
        final native = await _deviceChannel.invokeMethod<String>('deviceUuid', {
          'fallback': cached,
        });
        final value = _text(native);
        if (value.isNotEmpty) {
          if (cached != value) {
            await sp.setString('device_uuid', value);
          }
          return value;
        }
      } on Exception catch (error) {
        logger.d('ios device uuid failed: $error');
      }
    }

    final value = cached.isNotEmpty ? cached : _newDeviceUuid();
    if (cached != value) {
      await sp.setString('device_uuid', value);
    }
    return value;
  }

  static String _newDeviceUuid() {
    final raw = '${DateTime.now().millisecondsSinceEpoch}-${Object().hashCode}';
    return kIsWeb ? 'flutter-web-$raw' : raw;
  }

  static void blockAd() {
    _blockedAd = true;
  }

  static void allowAd() {
    _blockedAd = false;
  }

  static UserStateValue? cachedUserState() {
    final raw = sp.getString(_userInfoKey) ?? '';
    if (raw.isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(raw);
      return userStateFromInfo(
        decoded,
        avatarUrl: sp.getString(_avatarUrlKey) ?? '',
      );
    } on Exception catch (error) {
      logger.d('cached user decode failed: $error');
      return null;
    }
  }

  static UserStateValue userStateFromInfo(
    dynamic info, {
    String avatarUrl = '',
  }) {
    final map = _extractUserInfoMap(info);
    return UserStateValue(
      name: _text(map['name']).isEmpty ? 'No Name' : _text(map['name']),
      uid: _text(map['uid']),
      uniqueId: _text(map['unique_id'] ?? map['id']),
      password: _text(map['password']),
      vip: _intValue(map['vip']),
      admin: _intValue(map['admin']),
      anonymous: _intValue(map['anonymous']),
      avatarUrl: avatarUrl,
    );
  }

  static Future<UserStateValue?> cacheUserInfo(
    dynamic info, {
    String? token,
    String? avatarUrl,
    bool clearAvatar = false,
  }) async {
    final map = _extractUserInfoMap(info);
    if (map.isEmpty) {
      return null;
    }
    if (token != null && token.isNotEmpty) {
      await sp.setString('token', token);
    }
    await sp.setString(_userInfoKey, jsonEncode(map));
    final uid = _text(map['uid']);
    if (uid.isNotEmpty) {
      await sp.setString('uid', uid);
    }
    final uniqueId = _text(map['unique_id'] ?? map['id']);
    if (uniqueId.isNotEmpty) {
      await sp.setString('unique_id', uniqueId);
    }
    if (clearAvatar) {
      await sp.remove(_avatarUrlKey);
    } else if (avatarUrl != null) {
      if (avatarUrl.isEmpty) {
        await sp.remove(_avatarUrlKey);
      } else {
        await sp.setString(_avatarUrlKey, avatarUrl);
      }
    }
    return userStateFromInfo(map, avatarUrl: sp.getString(_avatarUrlKey) ?? '');
  }

  static Map<String, dynamic> _extractUserInfoMap(dynamic value) {
    final map = _normalizeMap(value);
    final nestedInfo = map['info'];
    if (nestedInfo is Map) {
      return _normalizeMap(nestedInfo);
    }
    return map;
  }

  static Map<String, dynamic> _normalizeMap(dynamic value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return value.map((key, item) => MapEntry(key.toString(), item));
    }
    return {};
  }

  static String _text(dynamic value) {
    return value?.toString() ?? '';
  }

  static int _intValue(dynamic value) {
    if (value is int) {
      return value;
    }
    return int.tryParse(_text(value)) ?? 0;
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

  static void payTrace(String message) {
    final entry = '[PAY] $message';
    logger.d(entry);
    // Keep payment diagnostics visible in Flutter, Xcode, and device log tools.
    // ignore: avoid_print
    print(entry);
  }

  static String static(String name) {
    final path = name.trim();
    if (path.isEmpty) {
      return '';
    }
    if (path.startsWith('http://') || path.startsWith('https://')) {
      return path;
    }
    if (path.startsWith('//')) {
      return 'https:$path';
    }
    final staticBase = (config?['static']?.toString() ?? _fallbackStaticBase)
        .replaceFirst(RegExp(r'/+$'), '');
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
                  Text(
                    message,
                    style: TextStyle(fontSize: 16, color: Colors.white),
                  ),
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
            ...AdjustTracking.loginParams(),
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

      final info = result.d['info'] as Map;
      final value = await cacheUserInfo(
        info,
        token: result.d['token']?.toString(),
        avatarUrl: FirebaseAuth.instance.currentUser?.photoURL ?? '',
      );

      if (context.mounted && value != null) {
        context.read<UserState>().set(value);
      }
      if (result.d['is_new'] == true) {
        AdjustTracking.trackRegister();
      }
      AdjustTracking.trackLogin();

      return true;
    } on Exception catch (e) {
      Global.logger.d(e);
      Global.error('Oops! Something went wrong.');
      return false;
    }
  }

  static Future<bool> restoreSession(BuildContext context) async {
    try {
      final deviceUuid = await Global.deviceUuid();
      final token = sp.getString('token') ?? '';
      final cached = cachedUserState();
      if (context.mounted && cached != null) {
        context.read<UserState>().set(cached);
      }
      Result<Map<String, dynamic>> result;
      if (token.isNotEmpty) {
        result = await api<Map<String, dynamic>>(
          'login/token',
          method: Method.post,
          data: {
            'token': token,
            'device_uuid': deviceUuid,
            'ad_attr_info': AdjustTracking.attributionInfo,
          },
          loading: false,
          showError: false,
        );
        if (result.c == 0) {
          final value = await cacheUserInfo(result.d);
          if (context.mounted && value != null) {
            context.read<UserState>().set(value);
          }
          return value != null;
        }
        if (result.m != 'Authentication Failure.' && cached != null) {
          Global.logger.d('keep cached session after token refresh failed');
          return true;
        }
        await sp.remove('token');
      }

      while (true) {
        result = await api<Map<String, dynamic>>(
          'login/anonymous',
          method: Method.post,
          data: {
            'device_uuid': deviceUuid,
            'ad_attr_info': AdjustTracking.attributionInfo,
          },
          loading: false,
          showError: false,
        );
        final value = await cacheUserInfo(
          result.d?['info'],
          token: result.d?['token']?.toString(),
          clearAvatar: true,
        );
        if (context.mounted && value != null) {
          context.read<UserState>().set(value);
        }
        if (result.c == 0 && value != null) {
          if (_boolValue(result.d?['is_new'] ?? result.d?['isNew'])) {
            AdjustTracking.trackRegister();
          } else {
            AdjustTracking.trackLogin();
          }
          return true;
        }
        await Future.delayed(const Duration(seconds: 2));
      }
    } on Exception catch (error) {
      Global.logger.d('restore session failed: $error');
      return false;
    }
  }

  static Future<bool> ensureAnonymousSession({bool force = false}) async {
    try {
      final token = sp.getString('token') ?? '';
      if (!force && token.isNotEmpty) {
        return true;
      }
      if (force) {
        await sp.remove('token');
      }
      final deviceUuid = await Global.deviceUuid();
      final result = await api<Map<String, dynamic>>(
        'login/anonymous',
        method: Method.post,
        data: {
          'device_uuid': deviceUuid,
          'ad_attr_info': AdjustTracking.attributionInfo,
        },
        loading: false,
        showError: false,
      );
      final tokenValue = result.d?['token']?.toString() ?? '';
      final value = await cacheUserInfo(
        result.d?['info'],
        token: tokenValue,
        clearAvatar: true,
      );
      if (result.c == 0 && tokenValue.isNotEmpty && value != null) {
        return true;
      }
      return false;
    } on Exception catch (error) {
      logger.d('ensure anonymous session failed: $error');
      return false;
    }
  }

  static Future<bool> loginWithGoogle(
    BuildContext context, {
    required String email,
    required String googleId,
    String name = '',
    String avatarUrl = '',
  }) async {
    try {
      final currentUser = cachedUserState();
      final anonymousId = _firstNotEmpty([
        currentUser?.uniqueId,
        sp.getString('unique_id'),
      ]);
      final result = await api<Map<String, dynamic>>(
        'login/signin',
        method: Method.post,
        data: {
          'anonymous': 0,
          'anonymous_id': anonymousId.isNotEmpty ? anonymousId : null,
          'email': email,
          'name': name.isNotEmpty ? name : (currentUser?.name ?? ''),
          'uid': googleId,
          'provider': 'google',
          'ad_attr_info': AdjustTracking.attributionInfo,
        },
      );

      if (result.c != 0) {
        return false;
      }

      final data = result.d ?? {};
      final value = await cacheUserInfo(
        data['info'],
        token: data['token']?.toString(),
        avatarUrl: avatarUrl,
      );
      if (value == null) {
        return false;
      }

      if (context.mounted) {
        context.read<UserState>().set(value);
      }
      if (_boolValue(data['is_new'] ?? data['isNew'])) {
        AdjustTracking.trackRegister();
      } else {
        AdjustTracking.trackLogin();
      }

      Global.success(t.login_success);
      return true;
    } on Exception catch (error) {
      Global.logger.d('google signin failed: $error');
      Global.error(t.login_failed);
      return false;
    }
  }

  static Future<bool> loginWithApple(
    BuildContext context, {
    required String email,
    required String appleId,
    String name = '',
  }) async {
    return loginWithProvider(
      context,
      provider: 'apple',
      uid: appleId,
      email: email,
      name: name,
    );
  }

  static Future<bool> loginWithProvider(
    BuildContext context, {
    required String provider,
    required String uid,
    String email = '',
    String name = '',
    String avatarUrl = '',
  }) async {
    try {
      final currentUser = cachedUserState();
      final anonymousId = _firstNotEmpty([
        currentUser?.uniqueId,
        sp.getString('unique_id'),
      ]);
      final result = await api<Map<String, dynamic>>(
        'login/signin',
        method: Method.post,
        data: {
          'anonymous': 0,
          'anonymous_id': anonymousId.isNotEmpty ? anonymousId : null,
          'email': email,
          'name': _loginName(name, email, currentUser),
          'uid': uid,
          'provider': provider,
          'ad_attr_info': AdjustTracking.attributionInfo,
        },
      );

      if (result.c != 0) {
        return false;
      }

      final data = result.d ?? {};
      final value = await cacheUserInfo(
        data['info'],
        token: data['token']?.toString(),
        avatarUrl: avatarUrl,
      );
      if (value == null) {
        return false;
      }

      if (context.mounted) {
        context.read<UserState>().set(value);
      }
      if (_boolValue(data['is_new'] ?? data['isNew'])) {
        AdjustTracking.trackRegister();
      } else {
        AdjustTracking.trackLogin();
      }

      Global.success(t.login_success);
      return true;
    } on Exception catch (error) {
      Global.logger.d('$provider signin failed: $error');
      Global.error(t.login_failed);
      return false;
    }
  }

  static Future<bool> logout(BuildContext context) async {
    try {
      final deviceUuid = await Global.deviceUuid();
      final result = await api<Map<String, dynamic>>(
        'login/anonymous',
        method: Method.post,
        data: {'device_uuid': deviceUuid, ...AdjustTracking.loginParams()},
        loading: false,
      );
      final token = result.d?['token']?.toString() ?? '';
      final value = await cacheUserInfo(
        result.d?['info'],
        token: token,
        clearAvatar: true,
      );
      if (result.c != 0 || token.isEmpty || value == null) {
        return false;
      }
      if (context.mounted) {
        context.read<UserState>().set(value);
      }
      Global.logger.d('logout switched to anonymous login');
      return true;
    } on Exception catch (error) {
      Global.logger.d('logout anonymous login failed: $error');
      return false;
    }
  }

  static String _firstNotEmpty(Iterable<String?> values) {
    for (final value in values) {
      if (value != null && value.isNotEmpty) {
        return value;
      }
    }
    return '';
  }

  static bool _boolValue(dynamic value) {
    if (value is bool) {
      return value;
    }
    if (value is num) {
      return value != 0;
    }
    return _text(value) == 'true' || _text(value) == '1';
  }

  static String firebaseDisplayName(User? user) {
    return _firstNotEmpty([
      user?.displayName,
      ...?user?.providerData.map((info) => info.displayName),
    ]);
  }

  static String _loginName(
    String name,
    String email,
    UserStateValue? currentUser,
  ) {
    final cachedName = currentUser?.anonymous == 1 ? '' : currentUser?.name;
    final emailName = email.contains('@') ? email.split('@').first : '';
    return _firstNotEmpty([name, cachedName, emailName]);
  }
}
