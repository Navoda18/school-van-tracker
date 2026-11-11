import 'package:supabase_flutter/supabase_flutter.dart';

String friendlyError(Object e) {
  final t = e.toString();
  if (t.contains('SocketException') ||
      t.contains('Failed host lookup') ||
      t.contains('ClientException')) {
    return 'No internet connection. Please try again.';
  }
  if (e is AuthException) return e.message;
  if (e is PostgrestException) {
    if (e.message.toLowerCase().contains('cut-off')) {
      return 'The cut-off time has passed. Please call the driver.';
    }
    if (e.code == '42501') return 'You do not have permission to do that.';
    if (e.code == '23505') return 'This is already saved.';
    return 'Something went wrong. Please try again.';
  }
  return 'Something went wrong. Please try again.';
}