import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yogotv/i18n/strings.g.dart';

void main() {
  testWidgets('Translations render in widget tests', (WidgetTester tester) async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await LocaleSettings.setLocale(AppLocale.en);

    await tester.pumpWidget(
      TranslationProvider(
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Builder(builder: (context) => Text(t.membership)),
        ),
      ),
    );

    expect(find.text('Membership'), findsOneWidget);
  });
}
