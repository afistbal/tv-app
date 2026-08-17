import 'package:flutter_test/flutter_test.dart';
import 'package:yogotv/api_diagnostics.dart';

void main() {
  tearDown(ApiDiagnostics.clear);

  test('exports recent API messages with app version', () {
    ApiDiagnostics.add(7, '--> POST movie/info data={"id":2835506157225355}');
    ApiDiagnostics.add(7, '<-- HTTP 500 body={"m":"failed"}');

    final text = ApiDiagnostics.export(version: '1.0.12', buildNumber: '3');

    expect(text, contains('YogoShort 1.0.12 (3)'));
    expect(text, contains('[API #7] --> POST movie/info'));
    expect(text, contains('[API #7] <-- HTTP 500'));
  });
}
