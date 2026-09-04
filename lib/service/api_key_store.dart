import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class ApiKeyStore {
  static final _storage = FlutterSecureStorage();
  static const _deepSeekKeyName = 'deepseek_api_key';

  static Future<void> saveDeepSeekKey(String key) =>
      _storage.write(key: _deepSeekKeyName, value: key.trim());

  static Future<String?> readDeepSeekKey() =>
      _storage.read(key: _deepSeekKeyName);

  static Future<void> clearDeepSeekKey() =>
      _storage.delete(key: _deepSeekKeyName);
}