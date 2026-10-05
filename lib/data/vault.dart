import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Local encrypted key-value store.
///
/// Decision: a random 256-bit master key lives in the OS keystore
/// (Android Keystore / iOS-macOS Keychain / Windows DPAPI / libsecret on Linux
/// via flutter_secure_storage). Data files are AES-256-GCM encrypted blobs,
/// so a copied app folder is useless without the keystore.
class Vault {
  static const _keyName = 'kuputun.master.v1';
  final Directory dir;
  final FlutterSecureStorage _secure;
  final _aes = AesGcm.with256bits();
  SecretKey? _key;

  Vault(this.dir, {FlutterSecureStorage? secure})
      : _secure = secure ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
              mOptions: MacOsOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
            );

  Future<SecretKey> _masterKey() async {
    if (_key != null) return _key!;
    final b64 = await _secure.read(key: _keyName);
    if (b64 != null) {
      try {
        final bytes = base64.decode(b64);
        if (bytes.length == 32) return _key = SecretKey(bytes);
      } on FormatException {
        // Corrupt keystore entry: fall through and mint a fresh key instead of
        // bricking every read for the rest of the install's life.
      }
    }
    final r = Random.secure();
    final fresh = base64.encode(List<int>.generate(32, (_) => r.nextInt(256)));
    await _secure.write(key: _keyName, value: fresh);
    return _key = SecretKey(base64.decode(fresh));
  }

  File _file(String name) => File('${dir.path}/$name.kv');

  /// Serialises reads and writes on this vault.
  ///
  /// AppState persists `data` and `settings` from several futures at once
  /// (e.g. three due stock subscriptions refreshing in parallel), all of them
  /// going through the same fixed temp path and the same target file. Without
  /// a lock one writer renames the temp file out from under another and the
  /// entry is lost or left torn.
  Future<void> _lock = Future.value();

  Future<T> _serialize<T>(Future<T> Function() op) {
    final run = _lock.then((_) => op());
    // Keep the chain alive even when this operation fails.
    _lock = run.then((_) {}, onError: (Object _) {});
    return run;
  }

  /// Moves an unreadable entry aside instead of retrying it forever.
  Future<void> _quarantine(File f) async {
    try {
      final aside = File('${f.path}.corrupt');
      if (await aside.exists()) await aside.delete();
      await f.rename(aside.path);
    } on Object {
      // Best effort: a stuck file must never stop the app from starting.
    }
  }

  Future<void> write(String name, String plaintext) => _serialize(() async {
        final box = await _aes.encrypt(utf8.encode(plaintext), secretKey: await _masterKey());
        await dir.create(recursive: true);
        final target = _file(name);
        final tmp = File('${target.path}.${_tmpCounter++}.tmp');
        try {
          await tmp.writeAsBytes(box.concatenation(), flush: true);
          // rename replaces atomically on POSIX and with MoveFileEx on Windows;
          // deleting first would lose the entry if the process died in between.
          await tmp.rename(target.path);
        } on Object {
          try {
            if (await tmp.exists()) await tmp.delete();
          } on Object {
            // ignore
          }
          rethrow;
        }
      });

  static int _tmpCounter = 0;

  Future<String?> read(String name) => _serialize(() async {
        final f = _file(name);
        if (!await f.exists()) return null;
        try {
          final bytes = await f.readAsBytes();
          final box = SecretBox.fromConcatenation(bytes, nonceLength: 12, macLength: 16);
          final clear = await _aes.decrypt(box, secretKey: await _masterKey());
          return utf8.decode(clear);
        } on SecretBoxAuthenticationError {
          // Master key rotated/lost (keystore reset, device restore) or a torn
          // file: the entry is unrecoverable, so drop it rather than crashing
          // the app before it can even render.
          await _quarantine(f);
          return null;
        } on ArgumentError {
          await _quarantine(f);
          return null;
        } on FormatException {
          await _quarantine(f);
          return null;
        }
      });

  Future<Map<String, dynamic>?> readJson(String name) async {
    final s = await read(name);
    if (s == null) return null;
    try {
      final j = jsonDecode(s);
      return j is Map ? Map<String, dynamic>.from(j) : null;
    } on FormatException {
      return null;
    }
  }

  Future<void> writeJson(String name, Object json) => write(name, jsonEncode(json));

  Future<List<String>> names() async {
    if (!await dir.exists()) return const [];
    return dir
        .list()
        .where((e) => e is File && e.path.endsWith('.kv'))
        .map((e) => e.uri.pathSegments.last.replaceAll('.kv', ''))
        .toList();
  }
}

/// Password-protected portable backup of every vault entry.
/// Format: "KTBK1" | salt(16) | nonce(12) | ciphertext | mac(16)
/// KDF: PBKDF2-HMAC-SHA256, 310 000 iterations (OWASP 2023 guidance).
class BackupService {
  static const _magic = 'KTBK1';
  static const _iterations = 310000;
  final Vault vault;
  BackupService(this.vault);

  Future<SecretKey> _derive(String password, List<int> salt) => Pbkdf2(
        macAlgorithm: Hmac.sha256(),
        iterations: _iterations,
        bits: 256,
      ).deriveKeyFromPassword(password: password, nonce: salt);

  Future<Uint8List> export(String password) async {
    final all = <String, String>{};
    for (final n in await vault.names()) {
      final v = await vault.read(n);
      if (v != null) all[n] = v;
    }
    final r = Random.secure();
    final salt = List<int>.generate(16, (_) => r.nextInt(256));
    final key = await _derive(password, salt);
    final box = await AesGcm.with256bits().encrypt(utf8.encode(jsonEncode({'v': 1, 'data': all})), secretKey: key);
    return Uint8List.fromList([...ascii.encode(_magic), ...salt, ...box.concatenation()]);
  }

  /// Throws [SecretBoxAuthenticationError] on wrong password / corrupted file.
  Future<int> restore(Uint8List file, String password) async {
    if (file.length < 5 + 16 + 12 + 16 || ascii.decode(file.sublist(0, 5)) != _magic) {
      throw const FormatException('Not a KupuTUN backup');
    }
    final salt = file.sublist(5, 21);
    final box = SecretBox.fromConcatenation(file.sublist(21), nonceLength: 12, macLength: 16);
    final clear = await AesGcm.with256bits().decrypt(box, secretKey: await _derive(password, salt));
    final j = jsonDecode(utf8.decode(clear)) as Map<String, dynamic>;
    final data = Map<String, String>.from(j['data'] as Map);
    for (final e in data.entries) {
      await vault.write(e.key, e.value);
    }
    return data.length;
  }
}
