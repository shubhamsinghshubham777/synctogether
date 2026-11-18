import 'package:supabase_flutter/supabase_flutter.dart';

/// The words a person sees when sign-in fails, never GoTrue's own text
/// ("captcha protection: request disallowed (invalid-input-response)" reached
/// the login screen verbatim). The raw code still goes to `reportNonFatal` at
/// the call site; this only decides the copy.
String friendlyAuthMessage(AuthException e) {
  final code = e.code ?? '';
  final message = e.message.toLowerCase();
  if (code == 'captcha_failed' || message.contains('captcha')) {
    return "We couldn't confirm you're a person. Give it another try.";
  }
  if (e.statusCode == '429' || code.startsWith('over_') || message.contains('rate limit')) {
    return 'Too many tries in a row. Wait a minute, then try again.';
  }
  if (code == 'otp_expired' || message.contains('expired')) {
    return 'That code has expired. Ask for a new one.';
  }
  if (code == 'email_address_invalid' || message.contains('invalid email')) {
    return "Hmm, that email address doesn't look right.";
  }
  if (code == 'email_not_confirmed') {
    return 'Check your inbox first: confirm your email, then sign in.';
  }
  if (code == 'user_banned') {
    return "This account can't sign in right now.";
  }
  return "Couldn't sign you in. Give it another try.";
}
