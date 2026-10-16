import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lubricentro_mobile/providers/auth_provider.dart';
import 'package:lubricentro_mobile/screens/vehicle_history_screen.dart';
import 'package:lubricentro_mobile/services/api_client.dart';

class CardAuth extends AuthNotifier {
  @override
  AuthState build() => const AuthState(role: 'admin', isLoading: false);
}

class CardApi extends ApiClient {
  CardApi() : super('https://example.invalid');
  Map<String, dynamic>? saved;
  bool hasPlan = false;
  bool failOnce = false;
  final requestKeys = <String>[];
  @override
  Future<dynamic> get(String path) async => {
        'vehicle': {
          'plate': 'ABCD12',
          'make': 'Marca',
          'model': 'Modelo',
          'year': 2020,
          'current_mileage_km': 30000
        },
        'technical': {
          'fields': [
            {
              'group': 'filters',
              'key': 'filter_oil_mann',
              'label': 'Filtro aceite · Mann'
            },
          ],
          'values': <String, dynamic>{},
        },
        'work_orders': [
          {
            'id': 9,
            'code': 'OT-TEST',
            'status': 'delivered',
            'opened_at': '2026-01-01',
            'mileage_km': 20000
          }
        ],
        'maintenance_plans': hasPlan
            ? [
                {
                  'id': 3,
                  'name': 'Aceite',
                  'active': true,
                  'interval_km': 10000,
                  'last_service_km': 20000
                }
              ]
            : [],
        'scanner_reports': [],
        'appointments': [],
      };
  @override
  Future<dynamic> putJson(String path, Map<String, dynamic> body) async {
    saved = body;
    return {};
  }

  @override
  Future<dynamic> postJson(String path, Map<String, dynamic> body) async {
    saved = body;
    if (body['request_key'] is String)
      requestKeys.add(body['request_key'] as String);
    if (failOnce) {
      failOnce = false;
      throw Exception('Error temporal de prueba');
    }
    return {};
  }
}

void main() {
  testWidgets('Mantención conserva campos y clave de solicitud al reintentar',
      (tester) async {
    final api = CardApi()
      ..hasPlan = true
      ..failOnce = true;
    await tester.pumpWidget(ProviderScope(
        overrides: [authProvider.overrideWith(CardAuth.new)],
        child: MaterialApp(
            home:
                VehicleHistoryScreen(api: api, vehicleId: 1, portal: false))));
    await tester.pumpAndSettle();
    DefaultTabController.of(tester.element(find.byType(TabBar))).animateTo(4);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Registrar mantención'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(1), 'Filtro documentado');
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Error temporal'), findsOneWidget);
    expect(find.text('Filtro documentado'), findsOneWidget);
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(api.saved?['mileage_km'], 30000);
    expect(api.requestKeys.length, 2);
    expect(api.requestKeys[0], api.requestKeys[1]);
    expect(tester.takeException(), isNull);
  });
  testWidgets('Administrador crea un plan desde la ficha', (tester) async {
    final api = CardApi();
    await tester.pumpWidget(ProviderScope(
        overrides: [authProvider.overrideWith(CardAuth.new)],
        child: MaterialApp(
            home:
                VehicleHistoryScreen(api: api, vehicleId: 1, portal: false))));
    await tester.pumpAndSettle();
    DefaultTabController.of(tester.element(find.byType(TabBar))).animateTo(4);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Crear plan'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Aceite motor');
    await tester.enterText(find.byType(TextField).at(1), '10000');
    await tester.enterText(find.byType(TextField).at(2), '365');
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(api.saved?['vehicle_id'], 1);
    expect(api.saved?['interval_km'], 10000);
    expect(api.saved?['interval_days'], 365);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'Ficha móvil: pestañas, validación de fuente y guardado versionado',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = CardApi();
    await tester.pumpWidget(ProviderScope(
        overrides: [authProvider.overrideWith(CardAuth.new)],
        child: MaterialApp(
            home:
                VehicleHistoryScreen(api: api, vehicleId: 1, portal: false))));
    await tester.pumpAndSettle();
    expect(find.text('Editar información'), findsOneWidget);
    final context = tester.element(find.byType(TabBar));
    DefaultTabController.of(context).animateTo(2);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Editar Filtro aceite · Mann'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'TEST-PART');
    await tester.tap(find.byType(CheckboxListTile));
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(find.text('Completa el dato y su fuente antes de verificar.'),
        findsOneWidget);
    expect(api.saved, isNull);
    await tester.enterText(
        find.byType(TextField).last, 'Catálogo oficial, variante de prueba');
    await tester.ensureVisible(find.text('Guardar'));
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(api.saved?['status'], 'verified');
    expect(api.saved?['revision'], 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Portal presenta ficha de solo lectura y conserva trabajos',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
        overrides: [authProvider.overrideWith(CardAuth.new)],
        child: MaterialApp(
            home: VehicleHistoryScreen(
                api: CardApi(), vehicleId: 1, portal: true))));
    await tester.pumpAndSettle();
    expect(find.text('Editar información'), findsNothing);
    DefaultTabController.of(tester.element(find.byType(TabBar))).animateTo(4);
    await tester.pumpAndSettle();
    expect(find.textContaining('OT-TEST'), findsOneWidget);
    expect(find.byTooltip('Historial de cambios'), findsNothing);
    expect(find.text('Crear plan'), findsNothing);
    expect(find.byTooltip('Registrar mantención'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
