import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const _storage = FlutterSecureStorage();

/// Persistent local drafts for work-order editing.
///
/// Uses [FlutterSecureStorage] so draft data survives app restarts
/// but remains encrypted at rest.
class WorkOrderDraftStore {
  static String _key(int orderId) => 'work_order_draft_$orderId';
  static String _receptionKey(int orderId) => 'work_order_reception_draft_$orderId';
  static String _inspectionKey(int orderId, int inspectionId) => 'work_order_inspection_draft_${orderId}_$inspectionId';

  static Future<Map<String, dynamic>?> _load(String key) async {
    final stored = await _storage.read(key: key);
    if (stored == null) return null;
    try {
      final decoded = jsonDecode(stored);
      return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
    } on FormatException {
      await _storage.delete(key: key);
      return null;
    }
  }

  static Future<Map<String, dynamic>?> load(int orderId) => _load(_key(orderId));

  static Future<void> save(int orderId, {required String status, required String diagnosis}) => _storage.write(
        key: _key(orderId),
        value: jsonEncode({
          'status': status,
          'diagnosis': diagnosis,
          'saved_at': DateTime.now().toUtc().toIso8601String(),
        }),
      );

  static Future<void> clear(int orderId) => _storage.delete(key: _key(orderId));

  static Future<Map<String, dynamic>?> loadReception(int orderId) => _load(_receptionKey(orderId));

  static Future<void> saveReception(int orderId, Map<String, dynamic> data) => _storage.write(
        key: _receptionKey(orderId),
        value: jsonEncode({...data, 'saved_at': DateTime.now().toUtc().toIso8601String()}),
      );

  static Future<void> clearReception(int orderId) => _storage.delete(key: _receptionKey(orderId));

  static Future<Map<String, dynamic>?> loadInspection(int orderId, int inspectionId) => _load(_inspectionKey(orderId, inspectionId));

  static Future<void> saveInspection(int orderId, int inspectionId, Map<String, dynamic> data) => _storage.write(
        key: _inspectionKey(orderId, inspectionId),
        value: jsonEncode({...data, 'saved_at': DateTime.now().toUtc().toIso8601String()}),
      );

  static Future<void> clearInspection(int orderId, int inspectionId) => _storage.delete(key: _inspectionKey(orderId, inspectionId));
}
