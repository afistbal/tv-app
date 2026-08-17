class VipContentRefresh {
  static bool _homePending = false;
  static bool _forYouPending = false;

  static void markVipChanged() {
    _homePending = true;
    _forYouPending = true;
  }

  static bool takeHome() {
    final pending = _homePending;
    _homePending = false;
    return pending;
  }

  static bool takeForYou() {
    final pending = _forYouPending;
    _forYouPending = false;
    return pending;
  }

  static bool statusChanged(int previousVip, int currentVip) {
    return (previousVip > 0) != (currentVip > 0);
  }

  static void reset() {
    _homePending = false;
    _forYouPending = false;
  }
}
