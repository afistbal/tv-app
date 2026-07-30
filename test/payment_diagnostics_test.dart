import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yogotv/payment_diagnostics.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('payment diagnostics redact credentials and Apple JWS values', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    await PaymentDiagnostics.initialize(
      preferences: preferences,
      appVersion: '1.0.5',
      buildNumber: 'test',
      flavor: 'test',
      apiHost: 'https://example.test/api/',
    );
    await PaymentDiagnostics.clear();

    PaymentDiagnostics.beginAttempt(
      localProductId: '1',
      appleProductId: 'coin2000',
      type: 2,
    );
    PaymentDiagnostics.add(
      'Authorization=Bearer secret-token '
      'receipt=eyJ123456789012345678901234.abcdefghijklmnopqrstuvwxyz123456.'
      'signature1234567890',
    );

    final exported = PaymentDiagnostics.exportText();
    expect(exported, contains('Bearer <redacted>'));
    expect(exported, contains('<redacted-jws>'));
    expect(exported, isNot(contains('secret-token')));
    expect(exported, isNot(contains('eyJ123456789012345678901234')));
  });
}
