import 'dart:async';
import 'dart:io';

// Keep recoverable messages readable and hide internal exception details.
String feedbackMessage(Object error, {String fallback = 'Could not complete this action. Please retry.'}) {
  if (error is TimeoutException) return error.message ?? 'Device did not respond. Retry.';
  if (error is FormatException) return error.message;
  if (error is StateError) return error.message;
  if (error is SocketException) return 'Connection lost. Reconnect and retry.';
  return fallback;
}
