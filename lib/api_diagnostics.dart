class ApiDiagnostics {
  static const int _maxEntries = 60;
  static const int _maxCharacters = 120000;
  static final List<String> _entries = [];

  static bool get hasEntries => _entries.isNotEmpty;

  static void add(int requestId, String message) {
    final timestamp = DateTime.now().toIso8601String();
    _entries.add('$timestamp [API #$requestId] $message');
    while (_entries.length > _maxEntries || _characterCount > _maxCharacters) {
      _entries.removeAt(0);
    }
  }

  static String export({required String version, required String buildNumber}) {
    return [
      'YogoShort $version ($buildNumber)',
      'Exported: ${DateTime.now().toIso8601String()}',
      ..._entries,
    ].join('\n');
  }

  static void clear() => _entries.clear();

  static int get _characterCount =>
      _entries.fold<int>(0, (total, entry) => total + entry.length);
}
