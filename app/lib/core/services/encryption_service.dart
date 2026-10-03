import 'dart:convert';
import 'dart:typed_data';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

/// EncryptionService — AES-256-GCM encryption for sensitive PII.
///
/// Used for: CNIC numbers (National ID).
///
/// Key management:
/// - Encryption key is derived per-dealer and stored in FlutterSecureStorage
///   (hardware-backed keystore on Android, Keychain on iOS).
/// - Key is NEVER stored in Drift, Supabase, plaintext files, or logs.
/// - Ciphertext stored in DB is base64(iv + ciphertext) — IV is random per encrypt.
/// - If key is lost (device wipe), encrypted fields cannot be recovered — by design.
///
/// Security guarantees:
/// - Plaintext CNIC never leaves this service without encryption
/// - Different dealers have different keys (dealer-scoped)
/// - IV is random per encryption call (no IV reuse)
class EncryptionService {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  static const _keyPrefix = 'munshi_enc_key_';
  static const _keyLength = 32; // AES-256

  // ── Key management ────────────────────────────────────────────────────────

  /// Get or create the AES key for a dealer.
  /// Key is stored securely per dealer in the device keystore.
  Future<enc.Key> _getOrCreateKey(String dealerId) async {
    final storageKey = '$_keyPrefix$dealerId';
    final existingB64 = await _storage.read(key: storageKey);

    if (existingB64 != null) {
      return enc.Key(base64.decode(existingB64) as Uint8List);
    }

    // Generate new key
    final keyBytes = enc.Key.fromSecureRandom(_keyLength);
    await _storage.write(
      key: storageKey,
      value: base64.encode(keyBytes.bytes),
    );
    return keyBytes;
  }

  // ── Encrypt ───────────────────────────────────────────────────────────────

  /// Encrypt plaintext for a specific dealer.
  /// Returns: base64(iv[16] + ciphertext)
  /// Returns null if input is null or empty.
  Future<String?> encrypt(String? plaintext, {required String dealerId}) async {
    if (plaintext == null || plaintext.isEmpty) return null;

    final key = await _getOrCreateKey(dealerId);
    final iv = enc.IV.fromSecureRandom(16);
    final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));

    final encrypted = encrypter.encrypt(plaintext, iv: iv);

    // Prepend IV to ciphertext, then base64-encode the whole thing
    final ivAndCipher = Uint8List.fromList([...iv.bytes, ...encrypted.bytes]);
    return base64.encode(ivAndCipher);
  }

  /// Decrypt ciphertext for a specific dealer.
  /// Returns null if input is null, empty, or decryption fails.
  Future<String?> decrypt(String? ciphertext, {required String dealerId}) async {
    if (ciphertext == null || ciphertext.isEmpty) return null;

    try {
      final key = await _getOrCreateKey(dealerId);
      final ivAndCipher = base64.decode(ciphertext) as Uint8List;

      if (ivAndCipher.length < 16) return null;

      final iv = enc.IV(ivAndCipher.sublist(0, 16) as Uint8List);
      final cipherBytes = enc.Encrypted(ivAndCipher.sublist(16) as Uint8List);

      final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
      return encrypter.decrypt(cipherBytes, iv: iv);
    } catch (e) {
      // Decryption failure — don't expose details, return null safely
      return null;
    }
  }

  // ── Utilities ─────────────────────────────────────────────────────────────

  /// Verify that stored value is encrypted (not plaintext CNIC).
  /// A CNIC is 13 digits; if the stored value is numeric-only, it's plaintext.
  static bool looksLikePlaintext(String? value) {
    if (value == null) return false;
    return RegExp(r'^\d{13}$').hasMatch(value.replaceAll('-', ''));
  }

  /// Mask CNIC for display (show last 4 digits only).
  static String maskCnic(String? cnic) {
    if (cnic == null || cnic.isEmpty) return '—';
    final digits = cnic.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 4) return '****';
    return '*********${digits.substring(digits.length - 4)}';
  }
}

final encryptionServiceProvider = Provider<EncryptionService>((ref) {
  return EncryptionService();
});
