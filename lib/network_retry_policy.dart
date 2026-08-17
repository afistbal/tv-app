bool isSafeNetworkRetry({
  required String path,
  required bool isGet,
  Object? data,
}) {
  if (isGet) {
    return true;
  }

  final normalizedPath = path.split('?').first;
  if (normalizedPath == 'user/config') {
    return data == null;
  }
  if (normalizedPath == 'movie/episode') {
    return data is Map && data['auto_unlock']?.toString() == '0';
  }

  return _safePostPaths.contains(normalizedPath);
}

const _safePostPaths = {
  'login/token',
  'foryou',
  'movie',
  'movie/discover',
  'movie/info',
  'movie/episodes/batch',
  'movie/history',
  'movie/my-list',
  'movie/tag-labels',
  'movie/tag-list',
  'feed/membership',
  'feed/search_feed',
  'user/balance',
  'user/balance/transactions',
  'user/membership',
  'applePay/products',
  'product',
};
