import 'dart:convert';

/// Tolerant base64: accepts std/url alphabets, missing padding, line breaks.
/// Returns null if the input is not valid base64 or not UTF-8 text.
String? tryDecodeBase64(String input) {
  var s = input.trim().replaceAll(RegExp(r'\s+'), '');
  if (s.isEmpty) return null;
  if (!RegExp(r'^[A-Za-z0-9+/=_-]+$').hasMatch(s)) return null;
  s = s.replaceAll('-', '+').replaceAll('_', '/').replaceAll('=', '');
  final pad = s.length % 4;
  if (pad == 1) return null;
  if (pad > 0) s += '=' * (4 - pad);
  try {
    return utf8.decode(base64.decode(s));
  } on FormatException {
    return null;
  }
}

String encodeBase64(String s, {bool urlSafe = false, bool padding = true}) {
  var out = urlSafe ? base64Url.encode(utf8.encode(s)) : base64.encode(utf8.encode(s));
  if (!padding) out = out.replaceAll('=', '');
  return out;
}

/// Happ-style values may be prefixed with `base64:`.
String decodeMaybeBase64Value(String v) {
  final t = v.trim();
  if (t.toLowerCase().startsWith('base64:')) {
    return tryDecodeBase64(t.substring(7)) ?? t;
  }
  return t;
}

String safeDecodeComponent(String s) {
  try {
    return Uri.decodeComponent(s);
  } catch (_) {
    return s;
  }
}
