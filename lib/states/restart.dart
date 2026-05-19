import 'package:flutter_bloc/flutter_bloc.dart';

class RestartStateValue {
  int version;

  RestartStateValue({this.version = 0});
}

class RestartState extends Cubit<RestartStateValue> {
  RestartState() : super(RestartStateValue());

  void restart() {
    emit(RestartStateValue(version: state.version + 1));
  }
}
