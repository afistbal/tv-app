import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:yogotv/api_diagnostics.dart';
import 'package:yogotv/app_config.dart';
import 'package:yogotv/global.dart';
import 'package:yogotv/i18n/strings.g.dart';
import 'package:yogotv/network_retry_policy.dart';

enum Method { get, post }

int _apiRequestSequence = 0;

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
  int networkAttempt = 0,
}) async {
  Response response;
  final requestId = ++_apiRequestSequence;
  final requestTimer = Stopwatch()..start();
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
    _apiLog(
      requestId,
      '--> ${method.name.toUpperCase()} $path '
      'query=${_diagnosticValue(requestQuery)} '
      'data=${_diagnosticValue(requestData)}',
    );
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

    _apiLog(
      requestId,
      '<-- HTTP ${response.statusCode} ${requestTimer.elapsedMilliseconds}ms '
      'body=${_diagnosticValue(response.data)}',
    );
    final body = response.data;
    if (body is! Map) {
      throw FormatException('API response is not a JSON object');
    }
    result.c = _intValue(body['c'], fallback: 1);
    result.m = body['m']?.toString() ?? '';
    result.d = body['d'];
    if (result.c != 0) {
      _apiLog(
        requestId,
        '<-- BUSINESS ERROR c=${result.c} m=${result.m} '
        'data=${_diagnosticValue(result.d)}',
      );
    }
  } on DioException catch (e) {
    _apiLog(
      requestId,
      '<-- DIO ERROR ${requestTimer.elapsedMilliseconds}ms '
      'type=${e.type.name} status=${e.response?.statusCode} '
      'message=${e.message} error=${e.error} '
      'query=${_diagnosticValue(e.requestOptions.queryParameters)} '
      'data=${_diagnosticValue(e.requestOptions.data)} '
      'response=${_diagnosticValue(e.response?.data)}',
    );
    if (networkAttempt == 0 &&
        _isRetryableTransportError(e) &&
        isSafeNetworkRetry(
          path: path,
          isGet: method == Method.get,
          data: data,
        )) {
      _apiLog(requestId, '--> RETRY after transport error');
      await Future<void>.delayed(const Duration(milliseconds: 300));
      return api<T>(
        path,
        method: method,
        query: query,
        loading: false,
        showError: showError,
        data: data,
        retryOnAuthFailure: retryOnAuthFailure,
        networkAttempt: 1,
      );
    }
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
        result.m = e.response == null
            ? 'Network connection interrupted. Please try again.'
            : 'Unknown error [${e.response?.statusCode}]';
    }
  } catch (error, stackTrace) {
    result.m = 'Invalid server response.';
    _apiLog(
      requestId,
      '<-- PARSE ERROR ${requestTimer.elapsedMilliseconds}ms '
      'error=$error stack=$stackTrace',
    );
  } finally {
    requestTimer.stop();
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
    final diagnosticSuffix = Global.apiDiagnosticsEnabled
        ? '\nAPI #$requestId $path'
        : '';
    Global.error('${result.m}$diagnosticSuffix');
  }

  return result as Result<T>;
}

void _apiLog(int requestId, String message) {
  if (!Global.apiDiagnosticsEnabled) {
    return;
  }
  ApiDiagnostics.add(requestId, message);
  Global.logger.d('[API #$requestId] $message');
}

bool _isRetryableTransportError(DioException error) {
  return error.response == null &&
      (error.type == DioExceptionType.unknown ||
          error.type == DioExceptionType.connectionError);
}

int _intValue(dynamic value, {required int fallback}) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return int.tryParse(value?.toString() ?? '') ?? fallback;
}

String _diagnosticValue(Object? value) {
  String text;
  try {
    text = jsonEncode(_redactForLogs(value));
  } catch (_) {
    text = value?.toString() ?? 'null';
  }
  const maxLength = 16000;
  if (text.length <= maxLength) {
    return text;
  }
  return '${text.substring(0, maxLength)}...[truncated ${text.length - maxLength} chars]';
}

Object? _redactForLogs(Object? value) {
  if (value is Map) {
    return value.map((key, item) {
      final name = key.toString();
      return MapEntry(
        name,
        _sensitiveLogKeys.contains(name.toLowerCase())
            ? _redactedValue(item)
            : _redactForLogs(item),
      );
    });
  }
  if (value is Iterable) {
    return value.map(_redactForLogs).toList(growable: false);
  }
  if (value == null || value is num || value is bool || value is String) {
    return value;
  }
  return value.toString();
}

String _redactedValue(Object? value) {
  final text = value?.toString() ?? '';
  if (text.length <= 8) {
    return '<redacted>';
  }
  return '${text.substring(0, 4)}...${text.substring(text.length - 4)}';
}

const _sensitiveLogKeys = {
  'authorization',
  'token',
  'access_token',
  'refresh_token',
  'password',
  'credential',
  'id_token',
  'receipt',
  'signed_data',
  'jws',
};

bool _requiresAuth(String path) {
  return !path.startsWith('config') && !path.startsWith('login/');
}

Future<Map<String, dynamic>> _commonParams() async {
  final usesIosRequestParams = Global.webPreview || (!kIsWeb && Platform.isIOS);
  if (!usesIosRequestParams) {
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
