import 'package:flutter_bloc/flutter_bloc.dart';

class DevicePreviewCubit extends Cubit<double?> {
  DevicePreviewCubit() : super(null);

  // Preview a drag without sending a device command.
  void preview(double value) => emit(value);

  // Return to the pending or confirmed value after release.
  void clear() => emit(null);
}
