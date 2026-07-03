class AppConfig {
  static const String flavor = String.fromEnvironment(
    'APP_FLAVOR',
    defaultValue: 'prod',
  );

  static const String apiBaseUrlOverride = String.fromEnvironment(
    'API_BASE_URL',
  );

  static const Map<String, AppFlavorConfig> _flavors = {
    'prod': AppFlavorConfig(
      flag: 'prod',
      apiBaseUrl: 'https://i.yogoshort.com/api/',
      shareOrigin: 'https://yogoshort.com',
      brandDisplayName: 'YogoShort',
      brandDomainDisplay: 'YogoShort.com',
      brandDescription: 'Watch short dramas on YogoShort.',
      brandContactEmail: 'cs@yogoshort.net',
      brandCopyrightCompany: 'WEISHOW LIMITED',
    ),
    'prod1': AppFlavorConfig(
      flag: 'prod1',
      apiBaseUrl: 'https://i.soulshort.com/api/',
      shareOrigin: 'https://www.soulshort.com',
      brandDisplayName: 'SoulShort',
      brandDomainDisplay: 'SoulShort.com',
      brandDescription: 'Watch short dramas on SoulShort.',
      brandContactEmail: 'cs@soulshort.com',
      brandCopyrightCompany: 'SOULSHORT LIMITED',
    ),
  };

  static AppFlavorConfig get current => _flavors[flavor] ?? _flavors['prod']!;

  static String get apiBaseUrl {
    final value = apiBaseUrlOverride.isNotEmpty
        ? apiBaseUrlOverride
        : current.apiBaseUrl;
    return value.endsWith('/') ? value : '$value/';
  }
}

class AppFlavorConfig {
  const AppFlavorConfig({
    required this.flag,
    required this.apiBaseUrl,
    required this.shareOrigin,
    required this.brandDisplayName,
    required this.brandDomainDisplay,
    required this.brandDescription,
    required this.brandContactEmail,
    required this.brandCopyrightCompany,
  });

  final String flag;
  final String apiBaseUrl;
  final String shareOrigin;
  final String brandDisplayName;
  final String brandDomainDisplay;
  final String brandDescription;
  final String brandContactEmail;
  final String brandCopyrightCompany;
}
