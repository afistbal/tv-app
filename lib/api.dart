import 'dart:io';

import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
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
  Object? data,
}) async {
  Response response;
  Map<String, String> headers = {
    'Accept-Language': LocaleSettings.currentLocale.languageCode,
    'Accept': 'application/json',
    'X-Platform': 'app',
    'X-OS': Platform.operatingSystem,
    'X-Test': Global.sp.getString('test') ?? '123456789',
    'X-Source': 'A100APP${Platform.isIOS ? 'IOS' : 'ANDROID'}',
    'X-Version':
        '${Global.packageInfo.version}.${Global.packageInfo.buildNumber}',
  };

  String token = Global.sp.getString('token') ?? '';

  if (token != '') {
    headers['Authorization'] = 'Bearer $token';
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
        await Global.sp.remove('token');
        await FirebaseAuth.instance.signOut();
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

  if (result.c != 0 && result.m != '') {
    Global.error(result.m);
  }

  return result as Result<T>;
}
