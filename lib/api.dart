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
    'X-App-Flag': AppConfig.current.flag,
  };

  String token = Global.sp.getString('token') ?? '';

  if (token != '') {
    headers['Authorization'] = 'Bearer $token';
  }
  final commonParams = await _commonParams();
  final requestQuery = _withCommonQueryParams(
    query,
    commonParams,
    includeCommonParams: method == Method.get || data is! Map,
  );
  final requestData = method == Method.post
      ? _withCommonDataParams(data, commonParams)
      : data;

  Result result = Result<T>(1, '', null);

  void Function()? close;

  if (loading) {
    close = Global.loading();
  }

  try {
    if (method == Method.get) {
      response = await Global.dio.get(
        path,
        queryParameters: requestQuery,
        options: Options(headers: headers),
      );
    } else {
      response = await Global.dio.post(
        path,
        data: requestData,
        queryParameters: requestQuery,
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

Future<Map<String, dynamic>> _commonParams() async {
  if (kIsWeb || Global.webPreview || !Platform.isIOS) {
    return {};
  }
  return {
    'device_uuid': await Global.deviceUuid(),
    'package_name': 'com.yogotv.app',
    'app_version': Global.packageInfo.version,
    'app_code': Global.packageInfo.buildNumber,
    'ad_id': Global.sp.getString('adjustId') ?? '',
  };
}

Map<String, dynamic>? _withCommonQueryParams(
  Map<String, dynamic>? value,
  Map<String, dynamic> commonParams, {
  required bool includeCommonParams,
}) {
  if (!includeCommonParams || commonParams.isEmpty) {
    return value;
  }
  return {...?value, ...commonParams};
}

Object? _withCommonDataParams(
  Object? value,
  Map<String, dynamic> commonParams,
) {
  if (commonParams.isEmpty || value is! Map) {
    return value;
  }
  return {...value, ...commonParams};
}
