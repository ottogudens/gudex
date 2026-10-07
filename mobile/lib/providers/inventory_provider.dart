import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/api_client.dart';

// Scoped to the API session. Refresh keeps the last successful list visible.
final inventoryProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, ApiClient>((ref, api) {
      return api.getAll('/api/v1/products');
    });
