import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:yogotv/components/android_toolbar.dart';
import 'package:yogotv/global.dart';
import 'package:yogotv/i18n/strings.g.dart';
import 'package:yogotv/states/restart.dart';

const Map<String, String> languages = {
  'en': 'English',
  'zh-Hant': '繁體中文',
  'ja': '日本語',
  'pt': 'Português',
  'vi': 'Tiếng Việt',
  'th': 'ภาษาไทย',
  'ko': '한국어',
  'id': 'Bahasa Indonesia',
  'de': 'Deutsch',
  'ms': 'Bahasa Malaysia',
  'tr': 'Türkçe',
  'ar': 'العربية',
};

class Language extends StatefulWidget {
  const Language({super.key});

  @override
  State<Language> createState() => _LanguageState();
}

class _LanguageState extends State<Language> {
  late String _language;

  @override
  void initState() {
    super.initState();
    _language = _localeKey(LocaleSettings.currentLocale);
  }

  Future<void> _changeLanguage(String languageCode) async {
    final locale = _appLocaleFromKey(languageCode);
    setState(() {
      _language = languageCode;
    });
    await LocaleSettings.setLocale(locale);
    await Global.sp.setString('locale', languageCode);
    if (mounted) {
      context.read<RestartState>().restart();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            AndroidToolbar(title: t.language, onBack: context.pop),
            Expanded(
              child: ListView.builder(
                padding: EdgeInsets.zero,
                itemCount: languages.length,
                itemBuilder: (context, index) {
                  final languageCode = languages.keys.elementAt(index);
                  final active = _language == languageCode;
                  return InkWell(
                    onTap: () => _changeLanguage(languageCode),
                    child: SizedBox(
                      height: 56,
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 15),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                languages.values.elementAt(index),
                                textAlign: TextAlign.start,
                                style: TextStyle(
                                  color: active
                                      ? Color(0xffff3d5d)
                                      : Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w400,
                                  height: 1.2,
                                ),
                              ),
                            ),
                            SizedBox(width: 10),
                            SizedBox(
                              width: 24,
                              height: 24,
                              child: active
                                  ? SvgPicture.asset(
                                      'assets/images/android/ic_select.svg',
                                    )
                                  : null,
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _localeKey(AppLocale locale) {
  if (locale == AppLocale.zhHant) {
    return 'zh-Hant';
  }
  return locale.languageCode == 'id' ? 'id' : locale.languageCode;
}

AppLocale _appLocaleFromKey(String key) {
  if (key == 'zh-Hant') {
    return AppLocale.zhHant;
  }
  return AppLocale.values.firstWhere(
    (locale) => locale.languageCode == key,
    orElse: () => AppLocale.en,
  );
}
