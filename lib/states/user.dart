import 'package:flutter_bloc/flutter_bloc.dart';

class UserStateValue {
  String name;
  String uid;
  String uniqueId;
  String password;
  int vip;
  int admin;
  int anonymous;
  String avatarUrl;
  String provider;

  UserStateValue({
    required this.name,
    required this.uid,
    required this.uniqueId,
    required this.password,
    required this.vip,
    required this.admin,
    required this.anonymous,
    this.avatarUrl = '',
    this.provider = '',
  });

  UserStateValue clone() {
    return UserStateValue(
      name: name,
      uid: uid,
      uniqueId: uniqueId,
      password: password,
      vip: vip,
      admin: admin,
      anonymous: anonymous,
      avatarUrl: avatarUrl,
      provider: provider,
    );
  }
}

class UserState extends Cubit<UserStateValue?> {
  UserState([super.initialState]);

  get signed => state != null && state!.anonymous != 1;
  get isAdmin => (state?.admin ?? 0) > 0;
  get isVip => (state?.vip ?? 0) > 0;

  void set(UserStateValue value) {
    emit(value);
  }

  void signout() {
    emit(null);
  }

  void setVip(int value) {
    state?.vip = value;
    emit(state?.clone());
  }
}
