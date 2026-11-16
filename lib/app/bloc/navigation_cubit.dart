import 'package:flutter_bloc/flutter_bloc.dart';

class NavigationCubit extends Cubit<int> {
  NavigationCubit() : super(0);

  // Select a tab while the shell keeps each page alive.
  void select(int index) => emit(index);
}
