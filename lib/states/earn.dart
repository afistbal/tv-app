import 'package:flutter_bloc/flutter_bloc.dart';

class EarnStateValue {
  int total;
  int owned;

  EarnStateValue({this.total = 0, this.owned = 0});
}

class EarnState extends Cubit<EarnStateValue> {
  EarnState() : super(EarnStateValue());

  void update(int total, int owned) {
    emit(EarnStateValue(total: total, owned: owned));
  }
}
