import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:yogotv/app_config.dart';
import 'package:yogotv/global.dart';
import 'package:yogotv/i18n/strings.g.dart';

enum Method { get, post }

class Result<T> {
  int c;
  String m;
  T? d;

  Result(this.c, this.m, this.d);
}

Future<Result<T>> api<T>(
  String path, {
  Method method = Method.get,
  Map<String, dynamic>? query,
  bool loading = false,
  bool showError = true,
  Object? data,
  bool retryOnAuthFailure = true,
}) async {
  Response response;
  final webAndroidPreview = kIsWeb && !Global.webPreview;
  final webIosPreview = Global.webPreview;
  final os = webIosPreview
      ? 'ios'
      : webAndroidPreview
      ? 'android'
      : Platform.operatingSystem;
  final source = webAndroidPreview
      ? 'A100APPANDROID'
      : 'A100APP${(webIosPreview || Platform.isIOS) ? 'IOS' : 'ANDROID'}';
  final platform = webAndroidPreview
      ? 'Android'
      : webIosPreview || Platform.isIOS
      ? 'IOS'
      : 'Android';
  final requiresAuth = _requiresAuth(path);
  if (requiresAuth && (Global.sp.getString('token') ?? '').isEmpty) {
    await Global.ensureAnonymousSession();
  }

  Map<String, String> headers = {
    'Accept-Language': LocaleSettings.currentLocale.languageCode,
    'Accept': 'application/json',
    'X-Platform': platform,
    'X-OS': os,
    'X-Test': Global.sp.getString('test') ?? '123456789',
    'X-Source': source,
    'X-App-Flag': AppConfig.current.flag,
  };

  String token = Global.sp.getString('token') ?? '';

  if (token != '') {
    headers['Authorization'] = 'Bearer $token';
  }
  final adjustAdid = Global.sp.getString('adjust_adid') ?? '';
  final adjustAttribution = Global.sp.getString('adjust_attribution') ?? '';
  if (adjustAdid.isNotEmpty) {
    headers['X-Adjust-Adid'] = adjustAdid;
  }
  if (adjustAttribution.isNotEmpty) {
    headers['X-Adjust-Attribution'] = adjustAttribution;
  }

  Result result = Result<T>(1, '', null);

  void Function()? close;

  if (loading) {
    close = Global.loading();
  }

  try {
    if (method == Method.get) {
      response = await Global.dio.get(
        path,
        queryParameters: query,
        options: Options(headers: headers),
      );
    } else {
      response = await Global.dio.post(
        path,
        data: data,
        options: Options(
          headers: {'Content-Type': 'application/json', ...headers},
        ),
      );
    }

    result.c = response.data['c'];
    result.m = response.data['m'];
    result.d = response.data['d'];
  } on DioException catch (e) {
    Global.logger.d(e.message);
    switch (e.response?.statusCode) {
      case 502:
      case 503:
      case 500:
        result.m = 'Server error.';
        break;
      case 401:
        result.m = 'Authentication Failure.';
        break;
      case 403:
        result.m = 'Forbidden.';
        break;
      case 404:
        result.m = 'Page not found.';
        break;
      case 422:
        result.m = 'Invalid data.';
        break;
      default:
        result.m = 'Unknown error [${e.response?.statusCode}]';
    }
  } finally {
    if (close != null) {
      close();
    }
  }

  if (retryOnAuthFailure &&
      requiresAuth &&
      result.m == 'Authentication Failure.') {
    await Global.sp.remove('token');
    final refreshed = await Global.ensureAnonymousSession(force: true);
    if (refreshed) {
      return api<T>(
        path,
        method: method,
        query: query,
        loading: false,
        showError: showError,
        data: data,
        retryOnAuthFailure: false,
      );
    }
  }

  if (showError && result.c != 0 && result.m != '') {
    Global.error(result.m);
  }

  return result as Result<T>;
}

bool _requiresAuth(String path) {
  return !path.startsWith('config') && !path.startsWith('login/');
}
