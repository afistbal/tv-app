class FromSourceValue {
  const FromSourceValue({required this.raw, required this.source});

  static const int maxRawLength = 8192;

  final String raw;
  final String source;

  /// 对齐 slot-TV：首次有效来源写入；已有来源只允许新的 A100 FB/TikTok
  /// source 覆盖。解析只用于校验，返回和上报始终使用原始 query 字符串。
  static FromSourceValue? selectForLogin({
    required String? incoming,
    required String? cached,
    required String? cachedSourceAnchor,
  }) {
    final cachedValue = tryParse(cached);
    final incomingValue = tryParse(incoming);
    if (cachedValue == null) return incomingValue;
    if (incomingValue == null) return cachedValue;

    final anchor = (cachedSourceAnchor ?? '').trim().isNotEmpty
        ? cachedSourceAnchor!.trim()
        : cachedValue.source;
    final sourceChanged =
        incomingValue.source.isNotEmpty && incomingValue.source != anchor;
    final isA100Campaign = RegExp(
      r'^A100',
      caseSensitive: false,
    ).hasMatch(incomingValue.source);
    final haystack = incomingValue.raw.toLowerCase();
    final containsFbOrTiktok =
        haystack.contains('fb') || haystack.contains('tiktok');

    return sourceChanged && isA100Campaign && containsFbOrTiktok
        ? incomingValue
        : cachedValue;
  }

  static FromSourceValue? tryParse(String? value) {
    final raw = value ?? '';
    if (raw.trim().isEmpty ||
        raw.length > maxRawLength ||
        raw.startsWith('?') ||
        raw.contains('#')) {
      return null;
    }

    try {
      final params = Uri.splitQueryString(raw);
      final movieId = int.tryParse(
        (params['movieId'] ?? params['id'] ?? '').trim(),
      );
      if (movieId == null || movieId <= 0) return null;

      final token = _adjustToken(params);
      if (!RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(token)) return null;

      return FromSourceValue(raw: raw, source: (params['s'] ?? '').trim());
    } on FormatException {
      return null;
    }
  }

  static String _adjustToken(Map<String, String> params) {
    final direct =
        (params['p0'] ??
                params['adjust_token'] ??
                params['adj_t'] ??
                params['adjust_t'] ??
                '')
            .trim();
    if (direct.isNotEmpty) return direct;

    final trackerUrl =
        (params['adjust_tracker_url'] ?? params['adjust_url'] ?? '').trim();
    final uri = Uri.tryParse(trackerUrl);
    if (uri == null ||
        !(uri.host == 'app.adjust.com' ||
            uri.host.endsWith('.app.adjust.com'))) {
      return '';
    }
    final parts = uri.pathSegments.where((part) => part.isNotEmpty).toList();
    return parts.isEmpty ? '' : parts.last;
  }
}
