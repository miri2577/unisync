import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Secure credential storage using OS-native encryption.
///
/// Windows: Credential Manager (DPAPI)
/// macOS: Keychain
/// Linux: libsecret
///
/// Passwords are NEVER stored in profile (.prf) files — they live in the
/// OS keyring and are only decryptable by the current user account.
class Credentials {
  static const _storage = FlutterSecureStorage(
    wOptions: WindowsOptions(useBackwardCompatibility: false),
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  /// Store a password for a profile.
  static Future<void> setPassword(String profileName, String password) async {
    await _storage.write(key: 'unisync.$profileName.password', value: password);
  }

  /// Retrieve a password for a profile.
  static Future<String?> getPassword(String profileName) async {
    return _storage.read(key: 'unisync.$profileName.password');
  }

  /// Delete a stored password.
  static Future<void> deletePassword(String profileName) async {
    await _storage.delete(key: 'unisync.$profileName.password');
  }

  /// Check if a password is stored for a profile.
  static Future<bool> hasPassword(String profileName) async {
    final value = await _storage.read(key: 'unisync.$profileName.password');
    return value != null && value.isNotEmpty;
  }
}
