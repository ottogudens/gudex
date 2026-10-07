import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lubricentro_mobile/core/theme.dart';
import 'package:lubricentro_mobile/screens/inventory_screen.dart';
import 'package:lubricentro_mobile/screens/widgets/inventory_editor.dart';
import 'package:lubricentro_mobile/screens/pos_screen.dart';
import 'package:lubricentro_mobile/services/api_client.dart';

class FakeApi extends ApiClient {
  FakeApi() : super('https://example.invalid');
  final calls = <Uri>[];
  int count = 251;
  int? failOffset;
  bool failSave = false;
  bool noStock = false;
  bool unpaidSale = false;
  final writePaths = <String>[];
  int writes = 0;
  Map<String, dynamic>? saved;

  @override
  Future<dynamic> get(String path) async {
    final uri = Uri.parse(path);
    calls.add(uri);
    if (uri.path == '/api/v1/sales' && unpaidSale) return [{'id': 42, 'receipt_code': 'V-42', 'total_clp': 2000, 'status': 'open', 'payments': []}];
    if (uri.path != '/api/v1/products') return <Map<String, dynamic>>[];
    final offset = int.parse(uri.queryParameters['offset'] ?? '0');
    if (offset == failOffset) throw Exception('Error de red');
    // Also exercises an API that caps requests below the requested page size.
    final end = (offset + 50).clamp(0, count);
    return [
      for (var i = offset; i < end; i++)
        {
          'id': i + 1,
          'name': 'Producto ${i + 1}',
          'sku': 'SKU-$i',
          'category': 'Aceites',
          'unit': 'unidad',
          'stock_quantity': noStock ? 0 : 5,
          'minimum_quantity': 1,
          'cost_clp': 1000,
          'price_clp': 2000,
        }
    ];
  }

  @override
  Future<dynamic> postJson(String path, Map<String, dynamic> data) async {
    writes++;
    writePaths.add(path);
    if (failSave) throw Exception('SKU ya existe');
    saved = Map.of(data);
    return {'id': 9, ...data};
  }

  @override
  Future<dynamic> patchJson(String path, Map<String, dynamic> data) =>
      postJson(path, data);
}

Future<void> mount(WidgetTester tester, Widget child,
    {Size size = const Size(1280, 900)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ProviderScope(
      child:
          MaterialApp(theme: gudexLightTheme(), home: Scaffold(body: child))));
  await tester.pumpAndSettle();
}

void main() {
  test('pagination includes record 251 and preserves filters', () async {
    final api = FakeApi();
    final rows = await api.getAll('/api/v1/products?low_stock=true');
    expect(rows.length, 251);
    expect(rows.last['id'], 251);
    expect(api.calls.every((uri) => uri.queryParameters['low_stock'] == 'true'),
        isTrue);
    expect(api.calls.last.queryParameters['offset'], '251');
  });

  test('page failure never returns a partial catalog', () async {
    final api = FakeApi()..failOffset = 100;
    await expectLater(api.getAll('/api/v1/products'), throwsException);
  });

  testWidgets('inventory search finds a record beyond the first page on mobile',
      (tester) async {
    await mount(tester, InventoryScreen(api: FakeApi(), canManage: true),
        size: const Size(360, 800));
    await tester.enterText(find.byType(TextField), 'SKU-250');
    await tester.pumpAndSettle();
    expect(find.text('Producto 251'), findsOneWidget);
    expect(find.text('1 productos'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed save retains fields and retry saves the same product',
      (tester) async {
    final api = FakeApi()..failSave = true;
    await mount(tester, InventoryScreen(api: api, canManage: true));
    await tester.tap(find.text('Nuevo producto'));
    await tester.pumpAndSettle();
    final name = find.widgetWithText(TextFormField, 'Nombre *');
    await tester.enterText(name, 'Aceite conservado');
    await tester.tap(find.text('Guardar producto'));
    await tester.pumpAndSettle();
    expect(find.byType(InventoryEditor), findsOneWidget);
    expect(find.text('Aceite conservado'), findsOneWidget);
    expect(find.textContaining('SKU ya existe'), findsOneWidget);
    api.failSave = false;
    await tester.tap(find.text('Guardar producto'));
    await tester.pumpAndSettle();
    expect(find.byType(InventoryEditor), findsNothing);
    expect(api.saved?['name'], 'Aceite conservado');
    expect(api.writes, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile stock editor retains quantity and reason after failure',
      (tester) async {
    final api = FakeApi()..failSave = true;
    await mount(tester, InventoryScreen(api: api, canManage: true),
        size: const Size(360, 800));
    await tester.tap(find.byTooltip('Ajustar stock').first);
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Cantidad (unidad)'), '2,5');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Motivo *'), 'Recepción');
    await tester.tap(find.text('Registrar movimiento'));
    await tester.pumpAndSettle();
    expect(find.text('2,5'), findsOneWidget);
    expect(find.text('Recepción'), findsOneWidget);
    expect(find.byType(InventoryEditor), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('POS preserves stock conflict and disables checkout',
      (tester) async {
    final api = FakeApi()..count = 1;
    await mount(tester, PosScreen(api: api), size: const Size(1280, 1100));
    await tester.tap(find.text('Agregar').first);
    await tester.pumpAndSettle();
    api.noStock = true;
    await tester.tap(find.byTooltip('Actualizar datos'));
    await tester.pumpAndSettle();
    expect(
        find.textContaining('Producto 1 × 1 · Revisar stock'), findsOneWidget);
    final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Cobrar \$2.000 CLP'));
    expect(button.onPressed, isNull);
    expect(tester.takeException(), isNull);
  });
  testWidgets('POS recovery records payment against the existing sale only', (tester) async {
    final api = FakeApi()..count = 1..unpaidSale = true;
    await mount(tester, PosScreen(api: api), size: const Size(1280, 1100));
    await tester.tap(find.byTooltip('Ver ventas y recuperar cobro'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Continuar cobro'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Registrar efectivo recibido'));
    await tester.pumpAndSettle();
    expect(api.writePaths, ['/api/v1/sales/42/payments']);
    expect(api.saved?['amount_clp'], 2000);
    expect(find.textContaining('pago registrado.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('archived product remains removable in cart after refresh', (tester) async {
    final api = FakeApi()..count = 1;
    await mount(tester, PosScreen(api: api), size: const Size(1280, 1100));
    await tester.tap(find.text('Agregar').first);
    await tester.pumpAndSettle();
    api.count = 0;
    await tester.tap(find.byTooltip('Actualizar datos'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Producto 1 × 1 · Revisar stock'), findsOneWidget);
    await tester.tap(find.byTooltip('Quitar producto'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Producto 1 × 1'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('inventory retains searchable data after refresh failure', (tester) async {
    final api = FakeApi();
    await mount(tester, InventoryScreen(api: api, canManage: false));
    await tester.enterText(find.byType(TextField), 'SKU-250');
    await tester.pumpAndSettle();
    api.failOffset = 0;
    await tester.tap(find.byTooltip('Actualizar inventario'));
    await tester.pumpAndSettle();
    expect(find.text('Producto 251'), findsOneWidget);
    expect(find.text('Se muestran los últimos datos disponibles.'), findsOneWidget);
    expect(find.text('Nuevo producto'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('POS keeps cart and persistent summary when resized to mobile', (tester) async {
    final api = FakeApi()..count = 1;
    await mount(tester, PosScreen(api: api), size: const Size(1280, 1100));
    await tester.tap(find.text('Agregar').first);
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(360, 800);
    await tester.pumpAndSettle();
    expect(find.text(r'Revisar venta · $2.000 CLP'), findsOneWidget);
    await tester.tap(find.text(r'Revisar venta · $2.000 CLP'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Producto 1 × 1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

}
