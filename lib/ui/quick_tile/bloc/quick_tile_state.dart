import 'package:equatable/equatable.dart';

class QuickTileState extends Equatable {
  final bool available;
  final bool busy;
  final int openScenesVersion;

  const QuickTileState({this.available = false, this.busy = false, this.openScenesVersion = 0});

  @override
  List<Object?> get props => [available, busy, openScenesVersion];
}
