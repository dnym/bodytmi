import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:bodytmi_application/bodytmi_application.dart';
import 'package:bodytmi_core/bodytmi_core.dart';
import 'package:cryptography/dart.dart';
import 'package:cryptography/cryptography.dart';

import 'profile_key.dart';

const encryptedFileFormat = 'bodytmi-encrypted/1';

/// Default key derivation: Argon2id version 0x13 with 64 MiB, three passes
/// and one lane (RFC 9106 section 4, second recommended option, one lane).
const _memoryKiB = 65536, _iterations = 3, _parallelism = 1;

/// A passphrase-encrypted file (`bodytmi-encrypted/1`): JSON with the
/// content format, gzip compression, Argon2id parameters and a random
/// 16-byte salt, and ChaCha20-Poly1305 (RFC 8439) with a random 12-byte
/// nonce. The ciphertext is base64 of the encrypted gzip bytes followed by
/// the 16-byte tag; the additional authenticated data is the canonical JSON
/// of every other field, so no parameter can be altered unnoticed. Each
/// file has its own salt and therefore its own key.
abstract final class EncryptedFile {
  static Future<Uint8List> seal(
    List<int> plaintext, {
    required String content,
    required ProfileKey key,
  }) async {
    final random = Random.secure();
    List<int> bytes(int n) => [for (var i = 0; i < n; i++) random.nextInt(256)];
    final header = <String, Object?>{
      'format': encryptedFileFormat,
      'content': content,
      'compression': 'gzip',
      'kdf': {
        'algorithm': 'argon2id',
        'version': 19,
        'memoryKiB': _memoryKiB,
        'iterations': _iterations,
        'parallelism': _parallelism,
        'salt': base64.encode(bytes(16)),
      },
      'cipher': {
        'algorithm': 'chacha20-poly1305',
        'nonce': base64.encode(bytes(12)),
      },
    };
    final box = await DartChacha20.poly1305Aead().encrypt(
      gzip.encode(plaintext),
      secretKey: await _derive(header, key),
      nonce: base64.decode(_cipher(header)['nonce']! as String),
      aad: utf8.encode(canonicalJson(header)),
    );
    return utf8.encode(
      canonicalJson({
        ...header,
        'ciphertext': base64.encode([...box.cipherText, ...box.mac.bytes]),
      }),
    );
  }

  /// Whether a decoded JSON value is an encrypted file.
  static bool recognises(Object? decoded) =>
      decoded is Map<String, Object?> &&
      decoded['format'] == encryptedFileFormat;

  /// Decrypts and decompresses; at most [maxBytes] of plaintext.
  static Future<Uint8List> open(
    List<int> bytes, {
    required String content,
    required ProfileKey key,
    required int maxBytes,
  }) async {
    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(bytes));
    } on FormatException {
      invalid('The encrypted file is not valid JSON.');
    }
    return openDecoded(decoded, content: content, key: key, maxBytes: maxBytes);
  }

  /// [open] for an already decoded JSON value.
  static Future<Uint8List> openDecoded(
    Object? decoded, {
    required String content,
    required ProfileKey key,
    required int maxBytes,
  }) async {
    final input = jsonObject(decoded, 'encrypted file');
    checkKeys(input, {
      'format',
      'content',
      'compression',
      'kdf',
      'cipher',
      'ciphertext',
    });
    if (input['format'] != encryptedFileFormat)
      invalid('Unsupported encrypted file format.');
    if (input['content'] != content)
      invalid('The encrypted file holds ${input['content']}, not $content.');
    if (input['compression'] != 'gzip')
      invalid('Unsupported encrypted file compression.');
    final cipher = _cipher(input);
    checkKeys(cipher, {'algorithm', 'nonce'});
    if (cipher['algorithm'] != 'chacha20-poly1305')
      invalid('Unsupported encrypted file cipher.');
    final nonce = _bytes(cipher, 'nonce', 12);
    final List<int> sealed;
    try {
      sealed = base64.decode(requiredString(input, 'ciphertext'));
    } on FormatException {
      invalid('The encrypted file ciphertext is not base64.');
    }
    if (sealed.length < 16) invalid('The encrypted file is truncated.');
    final header = {...input}..remove('ciphertext');
    final List<int> compressed;
    try {
      compressed = await DartChacha20.poly1305Aead().decrypt(
        SecretBox(
          sealed.sublist(0, sealed.length - 16),
          nonce: nonce,
          mac: Mac(sealed.sublist(sealed.length - 16)),
        ),
        secretKey: await _derive(header, key),
        aad: utf8.encode(canonicalJson(header)),
      );
    } on SecretBoxAuthenticationError {
      throw const BodyTmiException(
        'validation',
        'Wrong passphrase, or the encrypted file was altered.',
      );
    }
    final out = BytesBuilder(copy: false);
    await for (final chunk in Stream.value(
      compressed,
    ).transform(gzip.decoder)) {
      if (out.length + chunk.length > maxBytes)
        invalid('Decrypted content exceeds the resource limit.');
      out.add(chunk);
    }
    return out.takeBytes();
  }

  static Map<String, Object?> _cipher(Map<String, Object?> j) =>
      jsonObject(j['cipher'], 'cipher');

  static List<int> _bytes(Map<String, Object?> j, String key, int length) {
    try {
      final v = base64.decode(requiredString(j, key));
      if (v.length == length) return v;
    } on FormatException {
      // Reported below.
    }
    invalid('$key is $length bytes of base64.');
  }

  static Future<SecretKey> _derive(
    Map<String, Object?> header,
    ProfileKey key,
  ) async {
    final kdf = jsonObject(header['kdf'], 'kdf');
    checkKeys(kdf, {
      'algorithm',
      'version',
      'memoryKiB',
      'iterations',
      'parallelism',
      'salt',
    });
    int bounded(String name, int min, int max) {
      final v = kdf[name];
      if (v is! int || v < min || v > max)
        invalid('kdf $name is an integer from $min to $max.');
      return v;
    }

    if (kdf['algorithm'] != 'argon2id' || kdf['version'] != 19)
      invalid('Unsupported key derivation; expected Argon2id version 19.');
    final memory = bounded('memoryKiB', 8192, 1048576);
    final iterations = bounded('iterations', 1, 16);
    final parallelism = bounded('parallelism', 1, 8);
    if (memory < 8 * parallelism) invalid('kdf memoryKiB is too small.');
    return DartArgon2id(
      memory: memory,
      iterations: iterations,
      parallelism: parallelism,
      hashLength: 32,
    ).deriveKeyFromPassword(
      password: key.passphrase,
      nonce: _bytes(kdf, 'salt', 16),
    );
  }
}
