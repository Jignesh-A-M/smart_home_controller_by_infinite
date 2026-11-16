import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class EditorNavigationState extends Equatable {
  const EditorNavigationState({this.asking = false, this.allowPop = false});

  final bool asking, allowPop;

  @override
  List<Object?> get props => [asking, allowPop];
}

class EditorNavigationCubit extends Cubit<EditorNavigationState> {
  EditorNavigationCubit() : super(const EditorNavigationState());

  // Prevent duplicate discard dialogs while waiting for an answer.
  void asking(bool value) => emit(EditorNavigationState(asking: value, allowPop: state.allowPop));

  // Permit navigation after a successful save or confirmed discard.
  void finish() => emit(const EditorNavigationState(allowPop: true));
}
