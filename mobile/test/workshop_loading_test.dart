import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lubricentro_mobile/screens/workshop_screen.dart';
import 'package:lubricentro_mobile/services/api_client.dart';

class PartialWorkshopApi extends ApiClient {
  PartialWorkshopApi() : super('https://example.invalid');
  bool failVehicles = true;
  @override
  Future<List<Map<String, dynamic>>> getAll(String path) async {
    if (path.contains('vehicles')) {
      if (failVehicles) throw Exception('Error de vehículos');
      return [
        {
          'id': 2,
          'customer_id': 1,
          'plate': 'TEST01',
          'make': 'Toyota',
          'model': 'Yaris'
        }
      ];
    }
    return [
      {'id': 1, 'full_name': 'Cliente visible'}
    ];
  }
}

void main() {
  testWidgets('Un fallo de vehículos no oculta clientes y permite reintento',
      (tester) async {
    final api = PartialWorkshopApi();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: WorkshopScreen(
                api: api, modulePath: '/api/v1/customers', role: 'admin'))));
    await tester.pumpAndSettle();
    expect(find.text('Cliente visible'), findsOneWidget);
    expect(find.textContaining('Carga incompleta'), findsOneWidget);
    api.failVehicles = false;
    await tester.tap(find.text('Reintentar'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Carga incompleta'), findsNothing);
    await tester.tap(find.text('Vehículos'));
    await tester.pumpAndSettle();
    expect(find.textContaining('TEST01'), findsWidgets);
  });
}
