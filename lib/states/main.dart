import 'package:flutter_bloc/flutter_bloc.dart';

class MainStateValue {
  int current;

  MainStateValue({this.current = 0});
}

class MainState extends Cubit<MainStateValue> {
  MainState() : super(MainStateValue());

  void setIndex(int index) {
    emit(MainStateValue(current: index));
  }
}
