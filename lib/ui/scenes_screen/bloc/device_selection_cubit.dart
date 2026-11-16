import 'package:flutter_bloc/flutter_bloc.dart';

class DeviceSelectionCubit extends Cubit<Set<String>> {
  DeviceSelectionCubit(Set<String> selected) : super(Set.unmodifiable(selected));

  // Keep picker changes isolated until the user confirms the device list.
  void select(String id, bool selected) {
    final ids = {...state};
    selected ? ids.add(id) : ids.remove(id);
    emit(Set.unmodifiable(ids));
  }
}
