import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';

void main() => runApp(const LubricentroApp());

const _storage = FlutterSecureStorage();
const _defaultApiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://10.0.2.2:8000',
);

class ApiClient {
  ApiClient(this.baseUrl, {this.token});
  final String baseUrl;
  final String? token;

  Map<String, String> get _headers => {
        'Accept': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

  Future<Map<String, dynamic>> login(String email, String password) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/token'),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {'username': email, 'password': password},
    );
    final body = _decode(response);
    return Map<String, dynamic>.from(body as Map);
  }

  Future<dynamic> get(String path) async {
    final response = await http.get(Uri.parse('$baseUrl$path'), headers: _headers);
    return _decode(response);
  }

  Future<dynamic> post(String path) async {
    final response = await http.post(Uri.parse('$baseUrl$path'), headers: _headers);
    return _decode(response);
  }

  Future<dynamic> postJson(String path, Map<String, dynamic> data) async {
    final response = await http.post(
      Uri.parse('$baseUrl$path'),
      headers: {..._headers, 'Content-Type': 'application/json'},
      body: jsonEncode(data),
    );
    return _decode(response);
  }

  Future<dynamic> patchJson(String path, Map<String, dynamic> data) async {
    final response = await http.patch(
      Uri.parse('$baseUrl$path'),
      headers: {..._headers, 'Content-Type': 'application/json'},
      body: jsonEncode(data),
    );
    return _decode(response);
  }

  Future<dynamic> putJson(String path, Map<String, dynamic> data) async {
    final response = await http.put(
      Uri.parse('$baseUrl$path'),
      headers: {..._headers, 'Content-Type': 'application/json'},
      body: jsonEncode(data),
    );
    return _decode(response);
  }

  Future<dynamic> uploadBytes(String path, List<int> bytes, String filename, {String? contentType}) async {
    final request = http.MultipartRequest('POST', Uri.parse('$baseUrl$path'));
    request.headers.addAll(_headers);
    request.files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename));
    final streamed = await request.send();
    final response = await http.Response.fromStream(streamed);
    return _decode(response);
  }

  dynamic _decode(http.Response response) {
    final body = response.body.isEmpty ? null : jsonDecode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final message = body is Map ? body['detail'] : null;
      throw Exception(message?.toString() ?? 'Error HTTP ${response.statusCode}');
    }
    return body;
  }
}

class LubricentroApp extends StatelessWidget {
  const LubricentroApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Lubricentro',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0E7490)),
          useMaterial3: true,
          inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
        ),
        home: const SessionGate(),
      );
}

class SessionGate extends StatefulWidget {
  const SessionGate({super.key});

  @override
  State<SessionGate> createState() => _SessionGateState();
}

class _SessionGateState extends State<SessionGate> {
  String? _token;
  String? _role;
  String? _name;
  String? _baseUrl;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    final token = await _storage.read(key: 'access_token');
    final role = await _storage.read(key: 'role');
    final name = await _storage.read(key: 'full_name');
    final baseUrl = await _storage.read(key: 'api_base_url');
    if (!mounted) return;
    setState(() {
      _token = token;
      _role = role;
      _name = name;
      _baseUrl = baseUrl;
      _loading = false;
    });
  }

  Future<void> _signedIn(Map<String, dynamic> session) async {
    await _storage.write(key: 'access_token', value: session['access_token'] as String);
    await _storage.write(key: 'role', value: session['role'] as String);
    await _storage.write(key: 'full_name', value: session['full_name'] as String);
    await _storage.write(key: 'api_base_url', value: session['api_base_url'] as String);
    if (!mounted) return;
    setState(() {
      _token = session['access_token'] as String;
      _role = session['role'] as String;
      _name = session['full_name'] as String;
      _baseUrl = session['api_base_url'] as String;
    });
  }

  Future<void> _signOut() async {
    await _storage.deleteAll();
    if (!mounted) return;
    setState(() {
      _token = null;
      _role = null;
      _name = null;
      _baseUrl = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_token == null || _role == null) return LoginPage(onSignedIn: _signedIn);
    return HomePage(
      token: _token!, baseUrl: _baseUrl ?? 'http://10.0.2.2:8000', role: _role!, name: _name ?? 'Usuario', onSignOut: _signOut,
    );
  }
}

class LoginPage extends StatefulWidget {
  const LoginPage({required this.onSignedIn, super.key});
  final ValueChanged<Map<String, dynamic>> onSignedIn;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _baseUrl = TextEditingController(text: _defaultApiBaseUrl);
  bool _busy = false;
  String? _error;

  Future<void> _submit() async {
    setState(() { _busy = true; _error = null; });
    try {
      final base = _baseUrl.text.trim().replaceAll(RegExp(r'/$'), '');
      final session = await ApiClient(base).login(_email.text.trim(), _password.text);
      session['api_base_url'] = base;
      widget.onSignedIn(session);
    } catch (error) {
      setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _baseUrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const Icon(Icons.build_circle_outlined, size: 64),
                const SizedBox(height: 12),
                Text('Gestión del lubricentro', textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 28),
                TextField(controller: _baseUrl, decoration: const InputDecoration(labelText: 'Dirección de la API')),
                const SizedBox(height: 12),
                TextField(controller: _email, keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: 'Correo')),
                const SizedBox(height: 12),
                TextField(controller: _password, obscureText: true,
                    decoration: const InputDecoration(labelText: 'Contraseña'),
                    onSubmitted: (_) => _submit()),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ],
                const SizedBox(height: 20),
                FilledButton(onPressed: _busy ? null : _submit,
                    child: _busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator()) : const Text('Ingresar')),
              ]),
            ),
          ),
        ),
      );
}

class _Module {
  const _Module(this.title, this.path, {this.keyName});
  final String title;
  final String path;
  final String? keyName;
}

class HomePage extends StatefulWidget {
  const HomePage({required this.token, required this.baseUrl, required this.role, required this.name, required this.onSignOut, super.key});
  final String token;
  final String baseUrl;
  final String role;
  final String name;
  final VoidCallback onSignOut;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _selected = 0;

  List<_Module> get _modules {
    if (widget.role == 'customer') {
      return const [
        _Module('Mis vehículos', '/api/v1/portal/profile', keyName: 'vehicles'),
        _Module('Trabajos anteriores', '/api/v1/portal/work-orders'),
        _Module('Cotizaciones', '/api/v1/portal/quotes'),
        _Module('Mis citas', '/api/v1/portal/appointments'),
      ];
    }
    if (widget.role == 'mechanic') {
      return const [
        _Module('Órdenes de trabajo', '/api/v1/work-orders'),
        _Module('Inventario', '/api/v1/products'),
        _Module('Agenda', '/api/v1/appointments'),
      ];
    }
    return const [
      _Module('Órdenes de trabajo', '/api/v1/work-orders'),
      _Module('Clientes', '/api/v1/customers'),
      _Module('Inventario', '/api/v1/products'),
      _Module('Agenda', '/api/v1/appointments'),
      _Module('POS', '/api/v1/sales'),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final modules = _modules;
    final selected = _selected.clamp(0, modules.length - 1).toInt();
    final api = ApiClient(widget.baseUrl, token: widget.token);
    return Scaffold(
      appBar: AppBar(title: const Text('Lubricentro'), actions: [
        IconButton(onPressed: widget.onSignOut, tooltip: 'Cerrar sesión', icon: const Icon(Icons.logout)),
      ]),
      body: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding: const EdgeInsets.fromLTRB(18, 14, 18, 8), child: Text(
          'Hola, ${widget.name}', style: Theme.of(context).textTheme.titleLarge,
        )),
        Expanded(
          child: modules[selected].path == '/api/v1/sales'
              ? _PosScreen(api: api)
              : modules[selected].path == '/api/v1/products'
                  ? _InventoryScreen(api: api, canManage: widget.role == 'admin')
              : {'/api/v1/work-orders', '/api/v1/customers'}.contains(modules[selected].path)
                  ? _WorkshopScreen(api: api, module: modules[selected], role: widget.role)
                  : _ModuleList(api: api, module: modules[selected], role: widget.role),
        ),
      ]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: selected,
        onDestinationSelected: (index) => setState(() => _selected = index),
        destinations: [for (final module in modules.take(5)) NavigationDestination(
          icon: Icon(_iconFor(module.title)), label: module.title,
        )],
      ),
    );
  }

  IconData _iconFor(String title) {
    if (title.toLowerCase().contains('orden') || title.toLowerCase().contains('trabajos')) return Icons.assignment_outlined;
    if (title.contains('Inventario')) return Icons.inventory_2_outlined;
    if (title.toLowerCase().contains('cliente') || title.toLowerCase().contains('vehículos')) return Icons.directions_car_outlined;
    if (title.contains('Cotizaciones')) return Icons.request_quote_outlined;
    return Icons.calendar_month_outlined;
  }
}

class _ModuleList extends StatefulWidget {
  const _ModuleList({required this.api, required this.module, required this.role});
  final ApiClient api;
  final _Module module;
  final String role;

  @override
  State<_ModuleList> createState() => _ModuleListState();
}

class _ModuleListState extends State<_ModuleList> {
  late Future<List<dynamic>> _items;

  @override
  void initState() {
    super.initState();
    _items = _load();
  }

  @override
  void didUpdateWidget(covariant _ModuleList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.module.path != widget.module.path) _items = _load();
  }

  Future<List<dynamic>> _load() async {
    final data = await widget.api.get(widget.module.path);
    if (data is List) return data;
    if (data is Map && widget.module.keyName != null) {
      final value = data[widget.module.keyName];
      return value is List ? value : <dynamic>[];
    }
    return <dynamic>[];
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<dynamic>>(
        future: _items,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          if (snapshot.hasError) return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(
            'No se pudieron cargar los datos.\n${snapshot.error}', textAlign: TextAlign.center,
          )));
          final items = snapshot.data ?? [];
          if (items.isEmpty) return RefreshIndicator(
            onRefresh: () async => setState(() => _items = _load()),
            child: ListView(children: [SizedBox(height: 340, child: Center(child: Text('No hay ${widget.module.title.toLowerCase()} para mostrar.')))]),
          );
          return RefreshIndicator(
            onRefresh: () async => setState(() => _items = _load()),
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 20),
              itemCount: items.length,
              itemBuilder: (context, index) {
                final data = Map<String, dynamic>.from(items[index] as Map);
                final canApprove = widget.module.path == '/api/v1/portal/quotes' && data['status'] == 'sent' && data['id'] is int;
                return _RecordCard(
                  data: data,
                  onApprove: canApprove ? () => _answerQuote(data['id'] as int, true) : null,
                  onReject: canApprove ? () => _answerQuote(data['id'] as int, false) : null,
                  onOpen: widget.module.path == '/api/v1/portal/work-orders' && data['id'] is int
                      ? () => _showInspectionReport(data['id'] as int)
                      : null,
                );
              },
            ),
          );
        },
      );

  Future<void> _answerQuote(int id, bool approved) async {
    try {
      await widget.api.post('/api/v1/portal/quotes/$id/approval?approved=$approved');
      if (!mounted) return;
      setState(() => _items = _load());
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Respuesta registrada')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _showInspectionReport(int orderId) async {
    try {
      final raw = await widget.api.get('/api/v1/portal/work-orders/$orderId/inspection-report');
      final report = Map<String, dynamic>.from(raw as Map);
      final summary = Map<String, dynamic>.from(report['summary'] as Map? ?? {});
      final inspections = report['inspections'] is List ? report['inspections'] as List : const [];
      final scanner = report['scanner_reports'] is List ? report['scanner_reports'] as List : const [];
      if (!mounted) return;
      await showDialog<void>(context: context, builder: (context) => AlertDialog(
        title: Text('Informe ${report['order']?['code'] ?? ''}'),
        content: SizedBox(width: 520, child: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text('Normales: ${summary['normal'] ?? 0} · Observaciones: ${summary['observation'] ?? 0} · Fallas: ${summary['failed'] ?? 0}'),
          Text('Pendientes: ${summary['not_inspected'] ?? 0} · Informes LAUNCH: ${scanner.length}'),
          const Divider(),
          for (final rawItem in inspections)
            ListTile(contentPadding: EdgeInsets.zero, dense: true,
              leading: Icon(rawItem['result'] == 'normal' ? Icons.check_circle_outline : Icons.info_outline),
              title: Text('${rawItem['category']}: ${rawItem['item']}'),
              subtitle: Text('${rawItem['result']}${rawItem['notes'] == null ? '' : ' · ${rawItem['notes']}'}')),
        ]))),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar'))],
      ));
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }
}

class _InventoryScreen extends StatefulWidget {
  const _InventoryScreen({required this.api, required this.canManage});
  final ApiClient api;
  final bool canManage;

  @override
  State<_InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<_InventoryScreen> {
  final _search = TextEditingController();
  List<Map<String, dynamic>> _products = [];
  bool _loading = true;
  bool _lowStockOnly = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (!mounted) return;
    setState(() { _loading = true; _error = null; });
    try {
      final result = await widget.api.get('/api/v1/products');
      if (!mounted) return;
      setState(() => _products = result is List
          ? result.whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList()
          : <Map<String, dynamic>>[]);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  double _quantity(dynamic value) => value is num ? value.toDouble() : double.tryParse('$value') ?? 0;
  int _amount(dynamic value) => value is num ? value.round() : int.tryParse('$value') ?? 0;
  String _qtyText(double value) => value.toStringAsFixed(value % 1 == 0 ? 0 : 2);

  List<Map<String, dynamic>> get _visibleProducts {
    final query = _search.text.trim().toLowerCase();
    return _products.where((product) {
      final low = _quantity(product['stock_quantity']) <= _quantity(product['minimum_quantity']);
      final matchesSearch = query.isEmpty || '${product['name']} ${product['sku'] ?? ''} ${product['category'] ?? ''}'.toLowerCase().contains(query);
      return matchesSearch && (!_lowStockOnly || low);
    }).toList();
  }

  Future<void> _createProduct() async {
    final form = GlobalKey<FormState>();
    final sku = TextEditingController();
    final name = TextEditingController();
    final category = TextEditingController();
    final unit = TextEditingController(text: 'unidad');
    final stock = TextEditingController(text: '0');
    final minimum = TextEditingController(text: '0');
    final cost = TextEditingController(text: '0');
    final price = TextEditingController(text: '0');
    try {
      final data = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Agregar producto'),
          content: Form(key: form, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextFormField(controller: name, decoration: const InputDecoration(labelText: 'Nombre *'), validator: (v) => (v == null || v.trim().isEmpty) ? 'Campo obligatorio' : null),
            const SizedBox(height: 10),
            TextFormField(controller: sku, decoration: const InputDecoration(labelText: 'SKU / código (opcional)')),
            const SizedBox(height: 10),
            TextFormField(controller: category, decoration: const InputDecoration(labelText: 'Categoría')),
            const SizedBox(height: 10),
            TextFormField(controller: unit, decoration: const InputDecoration(labelText: 'Unidad (unidad, litro, etc.)'), validator: (v) => (v == null || v.trim().isEmpty) ? 'Campo obligatorio' : null),
            const SizedBox(height: 10),
            TextFormField(controller: stock, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Stock inicial'), validator: _validQuantity),
            const SizedBox(height: 10),
            TextFormField(controller: minimum, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Alerta de stock mínimo'), validator: _validQuantity),
            const SizedBox(height: 10),
            TextFormField(controller: cost, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Costo unitario (CLP)'), validator: _validMoney),
            const SizedBox(height: 10),
            TextFormField(controller: price, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Precio de venta (CLP)'), validator: _validMoney),
          ]))),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
            FilledButton(onPressed: () {
              if (!form.currentState!.validate()) return;
              Navigator.pop(context, {
                'name': name.text.trim(),
                'unit': unit.text.trim(),
                'stock_quantity': double.parse(stock.text.trim().replaceAll(',', '.')),
                'minimum_quantity': double.parse(minimum.text.trim().replaceAll(',', '.')),
                'cost_clp': int.parse(cost.text.trim()),
                'price_clp': int.parse(price.text.trim()),
                if (sku.text.trim().isNotEmpty) 'sku': sku.text.trim(),
                if (category.text.trim().isNotEmpty) 'category': category.text.trim(),
              });
            }, child: const Text('Guardar producto')),
          ],
        ),
      );
      if (data == null) return;
      try {
        await widget.api.postJson('/api/v1/products', data);
        await _refresh();
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Producto agregado al inventario')));
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
      }
    } finally {
      sku.dispose(); name.dispose(); category.dispose(); unit.dispose(); stock.dispose(); minimum.dispose(); cost.dispose(); price.dispose();
    }
  }

  String? _validQuantity(String? value) {
    final quantity = double.tryParse((value ?? '').trim().replaceAll(',', '.'));
    return quantity == null || !quantity.isFinite || quantity < 0 ? 'Ingresa una cantidad igual o mayor que cero' : null;
  }

  String? _validMoney(String? value) {
    final amount = int.tryParse((value ?? '').trim());
    return amount == null || amount < 0 ? 'Ingresa un monto CLP válido' : null;
  }

  Future<void> _adjustStock(Map<String, dynamic> product) async {
    final form = GlobalKey<FormState>();
    final quantity = TextEditingController();
    final reason = TextEditingController();
    String movement = 'in';
    try {
      final data = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (context) => StatefulBuilder(builder: (context, updateDialog) => AlertDialog(
          title: Text('Ajustar stock · ${product['name']}'),
          content: Form(key: form, child: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<String>(
              value: movement,
              decoration: const InputDecoration(labelText: 'Movimiento'),
              items: const [
                DropdownMenuItem(value: 'in', child: Text('Ingreso / recepción')),
                DropdownMenuItem(value: 'out', child: Text('Salida / merma')),
              ],
              onChanged: (value) { if (value != null) updateDialog(() => movement = value); },
            ),
            const SizedBox(height: 12),
            TextFormField(controller: quantity, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: 'Cantidad (${product['unit'] ?? 'unidad'})'), validator: (value) {
              final parsed = double.tryParse((value ?? '').trim().replaceAll(',', '.'));
              return parsed == null || !parsed.isFinite || parsed <= 0 ? 'Ingresa una cantidad mayor que cero' : null;
            }),
            const SizedBox(height: 12),
            TextFormField(controller: reason, decoration: const InputDecoration(labelText: 'Motivo *'), validator: (value) => (value == null || value.trim().length < 3) ? 'Describe el motivo del movimiento' : null),
          ])),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
            FilledButton(onPressed: () {
              if (!form.currentState!.validate()) return;
              final parsed = double.parse(quantity.text.trim().replaceAll(',', '.'));
              Navigator.pop(context, {
                'quantity_change': movement == 'in' ? parsed : -parsed,
                'reason': reason.text.trim(),
              });
            }, child: const Text('Registrar movimiento')),
          ],
        )),
      );
      if (data == null) return;
      await widget.api.postJson('/api/v1/products/${product['id']}/stock-movements', data);
      await _refresh();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Movimiento de stock registrado')));
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString().replaceFirst('Exception: ', ''))));
    } finally {
      quantity.dispose(); reason.dispose();
    }
  }

  Future<void> _showMovements(Map<String, dynamic> product) async {
    try {
      final result = await widget.api.get('/api/v1/products/${product['id']}/stock-movements');
      if (!mounted) return;
      final movements = result is List
          ? result.whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList()
          : <Map<String, dynamic>>[];
      await showModalBottomSheet<void>(
        context: context,
        useSafeArea: true,
        builder: (context) => Padding(
          padding: const EdgeInsets.all(16),
          child: ListView(shrinkWrap: true, children: [
            Text('Movimientos · ${product['name']}', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            if (movements.isEmpty) const Text('Todavía no hay movimientos para este producto.'),
            ...movements.take(50).map((movement) {
              final delta = _quantity(movement['quantity_change']);
              final date = DateTime.tryParse('${movement['created_at'] ?? ''}');
              final dateText = date == null ? '' : '${date.toLocal()}'.split('.').first;
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(delta >= 0 ? Icons.arrow_downward : Icons.arrow_upward, color: delta >= 0 ? Colors.green : Theme.of(context).colorScheme.error),
                title: Text('${delta >= 0 ? '+' : ''}${_qtyText(delta)} ${product['unit'] ?? 'unidad'} · ${movement['reason'] ?? 'movimiento'}'),
                subtitle: Text([dateText, movement['reference']].where((value) => value != null && '$value'.isNotEmpty).join(' · ')),
              );
            }),
          ]),
        ),
      );
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString().replaceFirst('Exception: ', ''))));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
      Text('No se pudo cargar el inventario.\n$_error', textAlign: TextAlign.center),
      const SizedBox(height: 12),
      OutlinedButton.icon(onPressed: _refresh, icon: const Icon(Icons.refresh), label: const Text('Reintentar')),
    ])));

    final visible = _visibleProducts;
    return Stack(children: [
      Column(children: [
        Padding(padding: const EdgeInsets.fromLTRB(12, 8, 12, 4), child: TextField(
          controller: _search,
          decoration: InputDecoration(labelText: 'Buscar producto', prefixIcon: const Icon(Icons.search), suffixIcon: IconButton(onPressed: () { _search.clear(); setState(() {}); }, icon: const Icon(Icons.clear))),
          onChanged: (_) => setState(() {}),
        )),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Mostrar solo stock bajo'),
          value: _lowStockOnly,
          onChanged: (value) => setState(() => _lowStockOnly = value),
        )),
        Expanded(child: visible.isEmpty
            ? RefreshIndicator(onRefresh: _refresh, child: ListView(children: [SizedBox(height: 280, child: Center(child: Text(_products.isEmpty ? 'No hay productos registrados.' : 'No hay productos que coincidan.')))]))
            : RefreshIndicator(onRefresh: _refresh, child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 2, 12, 88),
                itemCount: visible.length,
                itemBuilder: (context, index) => _productCard(visible[index]),
              ))),
      ]),
      if (widget.canManage) Positioned(right: 18, bottom: 18, child: FloatingActionButton.extended(
        onPressed: _createProduct,
        icon: const Icon(Icons.add),
        label: const Text('Nuevo producto'),
      )),
    ]);
  }

  Widget _productCard(Map<String, dynamic> product) {
    final stock = _quantity(product['stock_quantity']);
    final minimum = _quantity(product['minimum_quantity']);
    final low = stock <= minimum;
    return Card(child: ListTile(
      leading: CircleAvatar(
        backgroundColor: low ? Theme.of(context).colorScheme.errorContainer : Theme.of(context).colorScheme.secondaryContainer,
        child: Icon(low ? Icons.warning_amber_outlined : Icons.inventory_2_outlined),
      ),
      title: Text('${product['name'] ?? 'Producto'}'),
      subtitle: Text('${product['sku'] == null ? '' : '${product['sku']} · '}${product['category'] == null ? '' : '${product['category']} · '}Stock ${_qtyText(stock)} ${product['unit'] ?? 'unidad'} (mín. ${_qtyText(minimum)})\nCosto ${_amount(product['cost_clp'])} · Venta ${_amount(product['price_clp'])} CLP${low ? ' · STOCK BAJO' : ''}'),
      isThreeLine: true,
      trailing: widget.canManage ? IconButton(onPressed: () => _adjustStock(product), icon: const Icon(Icons.tune), tooltip: 'Ajustar stock') : null,
      onTap: () => _showMovements(product),
    ));
  }
}

class _WorkshopScreen extends StatefulWidget {
  const _WorkshopScreen({required this.api, required this.module, required this.role});
  final ApiClient api;
  final _Module module;
  final String role;

  @override
  State<_WorkshopScreen> createState() => _WorkshopScreenState();
}

class _WorkshopScreenState extends State<_WorkshopScreen> {
  List<Map<String, dynamic>> _records = [];
  List<Map<String, dynamic>> _customers = [];
  List<Map<String, dynamic>> _vehicles = [];
  int _customerSection = 0;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  bool get _isOrders => widget.module.path == '/api/v1/work-orders';
  bool get _canCreate => widget.role == 'admin';

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    if (!mounted) return;
    setState(() { _loading = true; _error = null; });
    try {
      if (_isOrders) {
        final values = await Future.wait([
          widget.api.get('/api/v1/work-orders'),
          widget.api.get('/api/v1/customers'),
          widget.api.get('/api/v1/vehicles'),
        ]);
        _records = _maps(values[0]);
        _customers = _maps(values[1]);
        _vehicles = _maps(values[2]);
      } else {
        final values = await Future.wait([
          widget.api.get('/api/v1/customers'),
          widget.api.get('/api/v1/vehicles'),
        ]);
        _customers = _maps(values[0]);
        _vehicles = _maps(values[1]);
        _records = _customerSection == 0 ? _customers : _vehicles;
      }
    } catch (error) {
      _error = error.toString().replaceFirst('Exception: ', '');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> _maps(dynamic value) => value is List
      ? value.whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList()
      : <Map<String, dynamic>>[];

  Future<void> _createCustomer() async {
    final form = GlobalKey<FormState>();
    final name = TextEditingController();
    final email = TextEditingController();
    final phone = TextEditingController();
    final rut = TextEditingController();
    try {
      final data = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Registrar cliente'),
          content: Form(key: form, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextFormField(controller: name, decoration: const InputDecoration(labelText: 'Nombre completo *'), validator: (v) => (v == null || v.trim().length < 2) ? 'Ingresa el nombre' : null),
            const SizedBox(height: 10),
            TextFormField(controller: rut, decoration: const InputDecoration(labelText: 'RUT (opcional)')),
            const SizedBox(height: 10),
            TextFormField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Teléfono')),
            const SizedBox(height: 10),
            TextFormField(controller: email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Correo')),
          ]))),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
            FilledButton(onPressed: () {
              if (!form.currentState!.validate()) return;
              Navigator.pop(context, {
                'full_name': name.text.trim(),
                if (rut.text.trim().isNotEmpty) 'rut': rut.text.trim(),
                if (phone.text.trim().isNotEmpty) 'phone': phone.text.trim(),
                if (email.text.trim().isNotEmpty) 'email': email.text.trim(),
              });
            }, child: const Text('Guardar')),
          ],
        ),
      );
      if (data != null) await _save('/api/v1/customers', data, 'Cliente registrado');
    } finally {
      name.dispose(); email.dispose(); phone.dispose(); rut.dispose();
    }
  }

  Future<void> _createVehicle() async {
    if (_customers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Registra un cliente antes de agregar su vehículo.')));
      return;
    }
    final form = GlobalKey<FormState>();
    final plate = TextEditingController();
    final make = TextEditingController();
    final model = TextEditingController();
    final year = TextEditingController();
    final vin = TextEditingController();
    final engine = TextEditingController();
    final mileage = TextEditingController();
    int customerId = _customers.first['id'] as int;
    try {
      final data = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (context) => StatefulBuilder(builder: (context, updateDialog) => AlertDialog(
          title: const Text('Registrar vehículo'),
          content: Form(key: form, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<int>(
              value: customerId,
              decoration: const InputDecoration(labelText: 'Cliente *'),
              items: _customers.map((item) => DropdownMenuItem<int>(value: item['id'] as int, child: Text('${item['full_name']}'))).toList(),
              onChanged: (value) { if (value != null) updateDialog(() => customerId = value); },
            ),
            const SizedBox(height: 10),
            TextFormField(controller: plate, textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(labelText: 'Patente *'), validator: (v) => (v == null || v.trim().isEmpty) ? 'Ingresa la patente' : null),
            const SizedBox(height: 10),
            TextFormField(controller: make, decoration: const InputDecoration(labelText: 'Marca *'), validator: (v) => (v == null || v.trim().isEmpty) ? 'Ingresa la marca' : null),
            const SizedBox(height: 10),
            TextFormField(controller: model, decoration: const InputDecoration(labelText: 'Modelo *'), validator: (v) => (v == null || v.trim().isEmpty) ? 'Ingresa el modelo' : null),
            const SizedBox(height: 10),
            TextFormField(controller: year, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Año'), validator: (v) => v == null || v.trim().isEmpty || int.tryParse(v.trim()) != null ? null : 'Ingresa un año válido'),
            const SizedBox(height: 10),
            TextFormField(controller: vin, decoration: const InputDecoration(labelText: 'VIN')),
            const SizedBox(height: 10),
            TextFormField(controller: engine, decoration: const InputDecoration(labelText: 'Motor')),
            const SizedBox(height: 10),
            TextFormField(controller: mileage, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Kilometraje'), validator: (v) => v == null || v.trim().isEmpty || int.tryParse(v.trim()) != null ? null : 'Ingresa un kilometraje válido'),
          ]))),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
            FilledButton(onPressed: () {
              if (!form.currentState!.validate()) return;
              final parsedYear = int.tryParse(year.text.trim());
              final parsedMileage = int.tryParse(mileage.text.trim());
              Navigator.pop(context, {
                'customer_id': customerId,
                'plate': plate.text.trim().toUpperCase(),
                'make': make.text.trim(),
                'model': model.text.trim(),
                if (parsedYear != null) 'year': parsedYear,
                if (vin.text.trim().isNotEmpty) 'vin': vin.text.trim().toUpperCase(),
                if (engine.text.trim().isNotEmpty) 'engine': engine.text.trim(),
                if (parsedMileage != null) 'current_mileage_km': parsedMileage,
              });
            }, child: const Text('Guardar')),
          ],
        )),
      );
      if (data != null) await _save('/api/v1/vehicles', data, 'Vehículo registrado');
    } finally {
      plate.dispose(); make.dispose(); model.dispose(); year.dispose(); vin.dispose(); engine.dispose(); mileage.dispose();
    }
  }

  Future<void> _createWorkOrder() async {
    if (_customers.isEmpty || _vehicles.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Registra primero un cliente y su vehículo.')));
      return;
    }
    final form = GlobalKey<FormState>();
    final mileage = TextEditingController();
    final symptoms = TextEditingController();
    final notes = TextEditingController();
    int customerId = _customers.first['id'] as int;
    int? vehicleId = _vehicles.firstWhere((v) => v['customer_id'] == customerId, orElse: () => _vehicles.first)['id'] as int;
    try {
      final data = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (context) => StatefulBuilder(builder: (context, updateDialog) {
          final customerVehicles = _vehicles.where((v) => v['customer_id'] == customerId).toList();
          if (customerVehicles.isNotEmpty && !customerVehicles.any((v) => v['id'] == vehicleId)) vehicleId = customerVehicles.first['id'] as int;
          return AlertDialog(
            title: const Text('Abrir orden de trabajo'),
            content: Form(key: form, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
              DropdownButtonFormField<int>(
                value: customerId,
                decoration: const InputDecoration(labelText: 'Cliente *'),
                items: _customers.map((item) => DropdownMenuItem<int>(value: item['id'] as int, child: Text('${item['full_name']}'))).toList(),
                onChanged: (value) { if (value != null) updateDialog(() { customerId = value; vehicleId = null; }); },
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<int>(
                value: customerVehicles.any((v) => v['id'] == vehicleId) ? vehicleId : null,
                decoration: const InputDecoration(labelText: 'Vehículo *'),
                items: customerVehicles.map((item) => DropdownMenuItem<int>(value: item['id'] as int, child: Text('${item['plate']} · ${item['make']} ${item['model']}'))).toList(),
                onChanged: (value) { if (value != null) updateDialog(() => vehicleId = value); },
                validator: (value) => value == null ? 'Selecciona un vehículo del cliente' : null,
              ),
              const SizedBox(height: 10),
              TextFormField(controller: mileage, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Kilometraje de recepción'), validator: (v) => v == null || v.trim().isEmpty || int.tryParse(v.trim()) != null ? null : 'Ingresa un kilometraje válido'),
              const SizedBox(height: 10),
              TextFormField(controller: symptoms, maxLines: 2, decoration: const InputDecoration(labelText: 'Síntomas informados')),
              const SizedBox(height: 10),
              TextFormField(controller: notes, maxLines: 2, decoration: const InputDecoration(labelText: 'Notas de recepción')),
            ]))),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
              FilledButton(onPressed: () {
                if (!form.currentState!.validate() || vehicleId == null) return;
                final parsedMileage = int.tryParse(mileage.text.trim());
                Navigator.pop(context, {
                  'customer_id': customerId,
                  'vehicle_id': vehicleId,
                  if (parsedMileage != null) 'mileage_km': parsedMileage,
                  if (symptoms.text.trim().isNotEmpty) 'reported_symptoms': symptoms.text.trim(),
                  if (notes.text.trim().isNotEmpty) 'initial_notes': notes.text.trim(),
                });
              }, child: const Text('Crear orden')),
            ],
          );
        }),
      );
      if (data != null) await _save('/api/v1/work-orders', data, 'Orden de trabajo creada');
    } finally {
      mileage.dispose(); symptoms.dispose(); notes.dispose();
    }
  }

  Future<void> _save(String path, Map<String, dynamic> data, String success) async {
    setState(() => _saving = true);
    try {
      await widget.api.postJson(path, data);
      if (!mounted) return;
      await _refresh();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(success)));
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString().replaceFirst('Exception: ', ''))));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _openOrder(Map<String, dynamic> order) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => _WorkOrderDetails(api: widget.api, order: order, onChanged: _refresh),
    );
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
      Text('No se pudieron cargar los datos.\n$_error', textAlign: TextAlign.center),
      const SizedBox(height: 12),
      OutlinedButton.icon(onPressed: _refresh, icon: const Icon(Icons.refresh), label: const Text('Reintentar')),
    ])));

    final isCustomerPage = !_isOrders;
    final label = _isOrders ? 'órdenes de trabajo' : (_customerSection == 0 ? 'clientes' : 'vehículos');
    return Stack(children: [
      Column(children: [
        if (isCustomerPage)
          Padding(padding: const EdgeInsets.fromLTRB(12, 4, 12, 2), child: SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 0, label: Text('Clientes'), icon: Icon(Icons.people_outline)),
              ButtonSegment(value: 1, label: Text('Vehículos'), icon: Icon(Icons.directions_car_outlined)),
            ],
            selected: {_customerSection},
            onSelectionChanged: (value) => setState(() { _customerSection = value.first; _records = _customerSection == 0 ? _customers : _vehicles; }),
          )),
        Expanded(child: _records.isEmpty
            ? RefreshIndicator(onRefresh: _refresh, child: ListView(children: [SizedBox(height: 300, child: Center(child: Text('No hay $label registrados.')))]))
            : RefreshIndicator(onRefresh: _refresh, child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 88),
                itemCount: _records.length,
                itemBuilder: (context, index) {
                  final item = _records[index];
                  if (_isOrders) return _workOrderTile(item);
                  if (_customerSection == 0) return _customerTile(item);
                  return _vehicleTile(item);
                },
              ))),
      ]),
      if (_canCreate) Positioned(
        right: 18, bottom: 18,
        child: FloatingActionButton.extended(
          onPressed: _saving ? null : _isOrders ? _createWorkOrder : _customerSection == 0 ? _createCustomer : _createVehicle,
          icon: Icon(_isOrders ? Icons.add_task : _customerSection == 0 ? Icons.person_add_alt_1 : Icons.add),
          label: Text(_isOrders ? 'Nueva orden' : _customerSection == 0 ? 'Nuevo cliente' : 'Nuevo vehículo'),
        ),
      ),
    ]);
  }

  Widget _customerTile(Map<String, dynamic> item) {
    final owned = _vehicles.where((vehicle) => vehicle['customer_id'] == item['id']).length;
    return Card(child: ListTile(
      leading: const CircleAvatar(child: Icon(Icons.person_outline)),
      title: Text('${item['full_name'] ?? 'Cliente'}'),
      subtitle: Text([item['phone'], item['email'], '$owned vehículo(s)'].where((value) => value != null && '$value'.isNotEmpty).join(' · ')),
    ));
  }

  Widget _vehicleTile(Map<String, dynamic> item) {
    final owner = _customers.where((customer) => customer['id'] == item['customer_id']);
    final customerName = owner.isEmpty ? 'Cliente no disponible' : '${owner.first['full_name']}';
    return Card(child: ListTile(
      leading: const CircleAvatar(child: Icon(Icons.directions_car_outlined)),
      title: Text('${item['plate']} · ${item['make']} ${item['model']}'),
      subtitle: Text('$customerName${item['year'] == null ? '' : ' · ${item['year']}'}${item['current_mileage_km'] == null ? '' : ' · ${item['current_mileage_km']} km'}'),
    ));
  }

  Widget _workOrderTile(Map<String, dynamic> item) {
    final vehicle = _vehicles.where((v) => v['id'] == item['vehicle_id']);
    final customer = _customers.where((c) => c['id'] == item['customer_id']);
    final vehicleLabel = vehicle.isEmpty ? 'Vehículo #${item['vehicle_id']}' : '${vehicle.first['plate']} · ${vehicle.first['make']} ${vehicle.first['model']}';
    final customerLabel = customer.isEmpty ? 'Cliente #${item['customer_id']}' : '${customer.first['full_name']}';
    return Card(child: ListTile(
      leading: const CircleAvatar(child: Icon(Icons.build_outlined)),
      title: Text('${item['code'] ?? 'Orden'} · $vehicleLabel'),
      subtitle: Text('$customerLabel\nEstado: ${'${item['status'] ?? 'received'}'.replaceAll('_', ' ')}${item['reported_symptoms'] == null ? '' : '\n${item['reported_symptoms']}'}'),
      isThreeLine: true,
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _openOrder(item),
    ));
  }
}

class _WorkOrderDetails extends StatefulWidget {
  const _WorkOrderDetails({required this.api, required this.order, required this.onChanged});
  final ApiClient api;
  final Map<String, dynamic> order;
  final Future<void> Function() onChanged;

  @override
  State<_WorkOrderDetails> createState() => _WorkOrderDetailsState();
}

class _WorkOrderDetailsState extends State<_WorkOrderDetails> {
  late final TextEditingController _diagnosis;
  late String _status;
  late Future<List<Map<String, dynamic>>> _inspections;
  late Future<List<Map<String, dynamic>>> _quotes;
  late Future<List<Map<String, dynamic>>> _templates;
  late Future<List<Map<String, dynamic>>> _evidence;
  late Future<Map<String, dynamic>> _report;
  bool _saving = false;
  String? _error;

  static const _statuses = [
    'received', 'inspecting', 'quoted', 'awaiting_approval', 'quote_rejected',
    'approved', 'in_progress', 'ready', 'delivered', 'cancelled',
  ];

  @override
  void initState() {
    super.initState();
    _diagnosis = TextEditingController(text: '${widget.order['diagnosis'] ?? ''}');
    _status = '${widget.order['status'] ?? 'received'}';
    _inspections = _loadInspections();
    _quotes = _loadQuotes();
    _templates = _loadList('/api/v1/inspection-templates');
    _evidence = _loadList('/api/v1/work-orders/${widget.order['id']}/evidence');
    _report = _loadReport();
  }

  @override
  void dispose() {
    _diagnosis.dispose();
    super.dispose();
  }

  Future<List<Map<String, dynamic>>> _loadInspections() async {
    final result = await widget.api.get('/api/v1/work-orders/${widget.order['id']}/inspections');
    return result is List ? result.whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList() : [];
  }

  Future<List<Map<String, dynamic>>> _loadQuotes() async {
    final result = await widget.api.get('/api/v1/work-orders/${widget.order['id']}/quotes');
    return result is List ? result.whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList() : [];
  }

  Future<List<Map<String, dynamic>>> _loadList(String path) async {
    final result = await widget.api.get(path);
    return result is List ? result.whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList() : [];
  }

  Future<Map<String, dynamic>> _loadReport() async {
    final result = await widget.api.get('/api/v1/work-orders/${widget.order['id']}/inspection-report');
    return result is Map ? Map<String, dynamic>.from(result) : <String, dynamic>{};
  }

  Future<void> _saveOrder() async {
    setState(() { _saving = true; _error = null; });
    try {
      await widget.api.patchJson('/api/v1/work-orders/${widget.order['id']}', {
        'status': _status,
        'diagnosis': _diagnosis.text.trim(),
      });
      if (!mounted) return;
      await widget.onChanged();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Orden actualizada')));
    } catch (error) {
      if (mounted) setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _addInspection() async {
    final form = GlobalKey<FormState>();
    final category = TextEditingController();
    final item = TextEditingController();
    final notes = TextEditingController();
    final measured = TextEditingController();
    String result = 'normal';
    try {
      final data = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (context) => StatefulBuilder(builder: (context, updateDialog) => AlertDialog(
          title: const Text('Nueva inspección'),
          content: Form(key: form, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextFormField(controller: category, decoration: const InputDecoration(labelText: 'Sistema / categoría *'), validator: (v) => (v == null || v.trim().isEmpty) ? 'Campo obligatorio' : null),
            const SizedBox(height: 10),
            TextFormField(controller: item, decoration: const InputDecoration(labelText: 'Punto inspeccionado *'), validator: (v) => (v == null || v.trim().isEmpty) ? 'Campo obligatorio' : null),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              value: result,
              decoration: const InputDecoration(labelText: 'Resultado'),
              items: const [
                DropdownMenuItem(value: 'normal', child: Text('Normal')),
                DropdownMenuItem(value: 'observation', child: Text('Requiere atención')),
                DropdownMenuItem(value: 'failed', child: Text('Falla detectada')),
              ],
              onChanged: (value) { if (value != null) updateDialog(() => result = value); },
            ),
            const SizedBox(height: 10),
            TextFormField(controller: measured, decoration: const InputDecoration(labelText: 'Medición (opcional)')),
            const SizedBox(height: 10),
            TextFormField(controller: notes, maxLines: 3, decoration: const InputDecoration(labelText: 'Observaciones')),
          ]))),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
            FilledButton(onPressed: () {
              if (!form.currentState!.validate()) return;
              Navigator.pop(context, {
                'category': category.text.trim(), 'item': item.text.trim(), 'result': result,
                if (measured.text.trim().isNotEmpty) 'measured_value': measured.text.trim(),
                if (notes.text.trim().isNotEmpty) 'notes': notes.text.trim(),
              });
            }, child: const Text('Guardar')),
          ],
        )),
      );
      if (data == null) return;
      setState(() { _saving = true; _error = null; });
      await widget.api.postJson('/api/v1/work-orders/${widget.order['id']}/inspections', data);
      if (!mounted) return;
      setState(() => _inspections = _loadInspections());
      await widget.onChanged();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Inspección guardada')));
    } catch (error) {
      if (mounted) setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
    } finally {
      category.dispose(); item.dispose(); notes.dispose(); measured.dispose();
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _applyTemplate() async {
    try {
      final templates = await _templates;
      if (!mounted) return;
      final selected = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (context) => SimpleDialog(
          title: const Text('Aplicar lista de inspección'),
          children: templates.map((template) => SimpleDialogOption(
            onPressed: () => Navigator.pop(context, template),
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.checklist_outlined),
              title: Text('${template['name']}'),
              subtitle: Text('${template['description'] ?? ''}'),
            ),
          )).toList(),
        ),
      );
      if (selected == null) return;
      setState(() => _saving = true);
      final response = await widget.api.post('/api/v1/work-orders/${widget.order['id']}/inspection-templates/${selected['id']}/apply');
      if (!mounted) return;
      setState(() {
        _inspections = _loadInspections();
        _report = _loadReport();
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${response['created_count']} puntos agregados')));
    } catch (error) {
      if (mounted) setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _editInspection(Map<String, dynamic> inspection) async {
    final notes = TextEditingController(text: '${inspection['notes'] ?? ''}');
    final measured = TextEditingController(text: '${inspection['measured_value'] ?? ''}');
    String result = '${inspection['result'] ?? 'not_inspected'}';
    try {
      final data = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (context) => StatefulBuilder(builder: (context, update) => AlertDialog(
          title: Text('${inspection['item']}'),
          content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<String>(
              value: result,
              decoration: const InputDecoration(labelText: 'Resultado'),
              items: const [
                DropdownMenuItem(value: 'not_inspected', child: Text('No inspeccionado')),
                DropdownMenuItem(value: 'normal', child: Text('Normal')),
                DropdownMenuItem(value: 'observation', child: Text('Observación')),
                DropdownMenuItem(value: 'failed', child: Text('Falla')),
                DropdownMenuItem(value: 'not_applicable', child: Text('No aplica')),
              ],
              onChanged: (value) { if (value != null) update(() => result = value); },
            ),
            const SizedBox(height: 10),
            TextField(controller: measured, decoration: const InputDecoration(labelText: 'Medición')),
            const SizedBox(height: 10),
            TextField(controller: notes, maxLines: 3, decoration: const InputDecoration(labelText: 'Observaciones')),
          ])),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(context, {
              'result': result, 'measured_value': measured.text.trim(), 'notes': notes.text.trim(),
            }), child: const Text('Guardar')),
          ],
        )),
      );
      if (data == null) return;
      await widget.api.patchJson('/api/v1/inspections/${inspection['id']}', data);
      if (!mounted) return;
      setState(() { _inspections = _loadInspections(); _report = _loadReport(); });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
    } finally {
      notes.dispose(); measured.dispose();
    }
  }

  Future<void> _editReception() async {
    final currentRaw = await widget.api.get('/api/v1/work-orders/${widget.order['id']}/reception');
    final current = currentRaw is Map ? Map<String, dynamic>.from(currentRaw) : <String, dynamic>{};
    final damage = TextEditingController(text: '${current['visible_damage'] ?? ''}');
    final accessories = TextEditingController(text: '${current['accessories'] ?? ''}');
    final observations = TextEditingController(text: '${current['customer_observations'] ?? ''}');
    final acceptedBy = TextEditingController(text: '${current['accepted_by_name'] ?? ''}');
    int? fuel = current['fuel_level_percent'] as int?;
    bool accepted = current['terms_accepted'] == true;
    try {
      final data = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (context) => StatefulBuilder(builder: (context, update) => AlertDialog(
          title: const Text('Recepción del vehículo'),
          content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<int>(value: fuel, decoration: const InputDecoration(labelText: 'Combustible'),
              items: [0, 25, 50, 75, 100].map((v) => DropdownMenuItem(value: v, child: Text('$v%'))).toList(),
              onChanged: (value) => update(() => fuel = value)),
            const SizedBox(height: 10),
            TextField(controller: damage, maxLines: 2, decoration: const InputDecoration(labelText: 'Daños visibles')),
            const SizedBox(height: 10),
            TextField(controller: accessories, maxLines: 2, decoration: const InputDecoration(labelText: 'Accesorios entregados')),
            const SizedBox(height: 10),
            TextField(controller: observations, maxLines: 2, decoration: const InputDecoration(labelText: 'Observaciones del cliente')),
            CheckboxListTile(contentPadding: EdgeInsets.zero, value: accepted, title: const Text('Cliente conforme con el registro'), onChanged: (v) => update(() => accepted = v ?? false)),
            TextField(controller: acceptedBy, decoration: const InputDecoration(labelText: 'Nombre de quien acepta')),
          ])),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(context, {
              'fuel_level_percent': fuel, 'visible_damage': damage.text.trim(), 'accessories': accessories.text.trim(),
              'customer_observations': observations.text.trim(), 'terms_accepted': accepted,
              'accepted_by_name': acceptedBy.text.trim(),
            }), child: const Text('Guardar recepción')),
          ],
        )),
      );
      if (data == null) return;
      await widget.api.putJson('/api/v1/work-orders/${widget.order['id']}/reception', data);
      if (!mounted) return;
      setState(() => _report = _loadReport());
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Recepción actualizada')));
    } catch (error) {
      if (mounted) setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
    } finally {
      damage.dispose(); accessories.dispose(); observations.dispose(); acceptedBy.dispose();
    }
  }

  Future<void> _attachEvidence() async {
    final source = await showModalBottomSheet<String>(context: context, builder: (context) => SafeArea(child: Wrap(children: [
      ListTile(leading: const Icon(Icons.photo_camera_outlined), title: const Text('Tomar fotografía'), onTap: () => Navigator.pop(context, 'camera')),
      ListTile(leading: const Icon(Icons.photo_library_outlined), title: const Text('Elegir fotografía'), onTap: () => Navigator.pop(context, 'gallery')),
      ListTile(leading: const Icon(Icons.picture_as_pdf_outlined), title: const Text('Adjuntar archivo o PDF'), onTap: () => Navigator.pop(context, 'file')),
    ])));
    if (source == null) return;
    try {
      List<int>? bytes;
      String? name;
      if (source == 'file') {
        final picked = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['jpg', 'jpeg', 'png', 'webp', 'pdf'], withData: true);
        if (picked == null) return;
        bytes = picked.files.single.bytes;
        name = picked.files.single.name;
      } else {
        final picked = await ImagePicker().pickImage(source: source == 'camera' ? ImageSource.camera : ImageSource.gallery, imageQuality: 85);
        if (picked == null) return;
        bytes = await picked.readAsBytes();
        name = picked.name;
      }
      if (bytes == null || name == null) throw Exception('No fue posible leer el archivo');
      await widget.api.uploadBytes('/api/v1/work-orders/${widget.order['id']}/evidence', bytes, name);
      if (!mounted) return;
      setState(() { _evidence = _loadList('/api/v1/work-orders/${widget.order['id']}/evidence'); _report = _loadReport(); });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Evidencia adjuntada')));
    } catch (error) {
      if (mounted) setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _createQuote() async {
    final form = GlobalKey<FormState>();
    final description = TextEditingController();
    final labor = TextEditingController(text: '0');
    final parts = TextEditingController(text: '0');
    final notes = TextEditingController();
    try {
      final data = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Preparar cotización'),
          content: Form(key: form, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextFormField(controller: description, maxLines: 2, decoration: const InputDecoration(labelText: 'Trabajo propuesto *'), validator: (v) => (v == null || v.trim().isEmpty) ? 'Describe el trabajo' : null),
            const SizedBox(height: 10),
            TextFormField(controller: labor, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Mano de obra (CLP)', prefixText: '\$'), validator: _nonNegativeInteger),
            const SizedBox(height: 10),
            TextFormField(controller: parts, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Repuestos (CLP)', prefixText: '\$'), validator: _nonNegativeInteger),
            const SizedBox(height: 10),
            TextFormField(controller: notes, maxLines: 3, decoration: const InputDecoration(labelText: 'Observaciones / alcance')),
          ]))),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
            FilledButton(onPressed: () {
              if (!form.currentState!.validate()) return;
              Navigator.pop(context, {
                'description': description.text.trim(),
                'labor_clp': int.parse(labor.text.trim()),
                'parts_clp': int.parse(parts.text.trim()),
                if (notes.text.trim().isNotEmpty) 'notes': notes.text.trim(),
              });
            }, child: const Text('Guardar borrador')),
          ],
        ),
      );
      if (data == null) return;
      setState(() { _saving = true; _error = null; });
      await widget.api.postJson('/api/v1/work-orders/${widget.order['id']}/quotes', data);
      if (!mounted) return;
      setState(() => _quotes = _loadQuotes());
      await widget.onChanged();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cotización guardada como borrador')));
    } catch (error) {
      if (mounted) setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
    } finally {
      description.dispose(); labor.dispose(); parts.dispose(); notes.dispose();
      if (mounted) setState(() => _saving = false);
    }
  }

  String? _nonNegativeInteger(String? value) {
    final amount = int.tryParse((value ?? '').trim());
    return amount == null || amount < 0 ? 'Ingresa un monto válido en CLP' : null;
  }

  Future<void> _publishQuote(Map<String, dynamic> quote) async {
    final total = (_asInt(quote['labor_clp']) + _asInt(quote['parts_clp']));
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Publicar cotización'),
        content: Text('Se enviará al portal del cliente la propuesta “${quote['description']}” por ${_currency(total)}. Confirma que el alcance y los valores estén revisados.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Seguir revisando')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Publicar')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() { _saving = true; _error = null; });
    try {
      await widget.api.post('/api/v1/quotes/${quote['id']}/publish');
      if (!mounted) return;
      setState(() => _quotes = _loadQuotes());
      await widget.onChanged();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cotización publicada para el cliente')));
    } catch (error) {
      if (mounted) setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  int _asInt(dynamic value) => value is num ? value.round() : int.tryParse('$value') ?? 0;
  String _currency(int amount) => '\$${amount.toString()} CLP';

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
        child: ListView(shrinkWrap: true, children: [
          Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Theme.of(context).colorScheme.outlineVariant, borderRadius: BorderRadius.circular(4)))),
          const SizedBox(height: 18),
          Text('${widget.order['code'] ?? 'Orden de trabajo'}', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text('Síntomas informados: ${widget.order['reported_symptoms'] ?? 'Sin síntomas registrados'}'),
          if (widget.order['initial_notes'] != null) ...[
            const SizedBox(height: 4),
            Text('Recepción: ${widget.order['initial_notes']}'),
          ],
          const SizedBox(height: 18),
          DropdownButtonFormField<String>(
            value: _statuses.contains(_status) ? _status : 'received',
            decoration: const InputDecoration(labelText: 'Estado del trabajo'),
            items: _statuses.map((value) => DropdownMenuItem(value: value, child: Text(value.replaceAll('_', ' ')))).toList(),
            onChanged: (value) { if (value != null) setState(() => _status = value); },
          ),
          const SizedBox(height: 12),
          TextField(controller: _diagnosis, maxLines: 4, decoration: const InputDecoration(labelText: 'Diagnóstico / pruebas pendientes', alignLabelWithHint: true)),
          const SizedBox(height: 12),
          if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          FilledButton.icon(onPressed: _saving ? null : _saveOrder, icon: const Icon(Icons.save_outlined), label: Text(_saving ? 'Guardando…' : 'Guardar cambios')),
          const SizedBox(height: 10),
          OutlinedButton.icon(onPressed: _saving ? null : _editReception, icon: const Icon(Icons.assignment_outlined), label: const Text('Completar recepción')),
          const Divider(height: 28),
          Row(children: [
            Expanded(child: Text('Inspecciones', style: Theme.of(context).textTheme.titleLarge)),
            IconButton(onPressed: _saving ? null : _applyTemplate, icon: const Icon(Icons.playlist_add_check), tooltip: 'Aplicar plantilla'),
            IconButton(onPressed: _saving ? null : _addInspection, icon: const Icon(Icons.add_circle_outline), tooltip: 'Agregar inspección'),
          ]),
          FutureBuilder<List<Map<String, dynamic>>>(
            future: _inspections,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) return const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()));
              if (snapshot.hasError) return Text('No se pudieron cargar las inspecciones: ${snapshot.error}');
              final records = snapshot.data ?? [];
              if (records.isEmpty) return const Text('Todavía no hay puntos de inspección registrados.');
              return Column(children: records.map((inspection) => Card(child: ListTile(
                leading: Icon(inspection['result'] == 'normal' ? Icons.check_circle_outline : Icons.warning_amber_outlined),
                title: Text('${inspection['category']}: ${inspection['item']}'),
                subtitle: Text('${inspection['result']}${inspection['measured_value'] == null ? '' : ' · ${inspection['measured_value']}'}${inspection['notes'] == null ? '' : '\n${inspection['notes']}'}'),
                isThreeLine: inspection['notes'] != null,
                trailing: const Icon(Icons.edit_outlined),
                onTap: () => _editInspection(inspection),
              ))).toList());
            },
          ),
          const Divider(height: 28),
          Row(children: [
            Expanded(child: Text('Evidencias', style: Theme.of(context).textTheme.titleLarge)),
            IconButton(onPressed: _saving ? null : _attachEvidence, icon: const Icon(Icons.attach_file), tooltip: 'Adjuntar foto o archivo'),
          ]),
          FutureBuilder<List<Map<String, dynamic>>>(future: _evidence, builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) return const LinearProgressIndicator();
            final records = snapshot.data ?? [];
            if (records.isEmpty) return const Text('No hay fotografías o archivos adjuntos.');
            return Column(children: records.map((item) => ListTile(
              leading: Icon('${item['content_type']}'.startsWith('image/') ? Icons.image_outlined : Icons.picture_as_pdf_outlined),
              title: Text('${item['filename']}'), subtitle: Text('${item['caption'] ?? 'Evidencia de la orden'}'),
            )).toList());
          }),
          const Divider(height: 28),
          Text('Resumen para el cliente', style: Theme.of(context).textTheme.titleLarge),
          FutureBuilder<Map<String, dynamic>>(future: _report, builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) return const LinearProgressIndicator();
            if (snapshot.hasError) return Text('No se pudo generar el resumen: ${snapshot.error}');
            final summary = snapshot.data?['summary'] is Map ? Map<String, dynamic>.from(snapshot.data!['summary'] as Map) : <String, dynamic>{};
            final scanners = snapshot.data?['scanner_reports'] is List ? snapshot.data!['scanner_reports'] as List : const [];
            return Card(child: Padding(padding: const EdgeInsets.all(14), child: Text(
              'Normales: ${summary['normal'] ?? 0} · Observaciones: ${summary['observation'] ?? 0} · Fallas: ${summary['failed'] ?? 0}\n'
              'Pendientes: ${summary['not_inspected'] ?? 0} · Informes LAUNCH: ${scanners.length}',
            )));
          }),
          const Divider(height: 28),
          Row(children: [
            Expanded(child: Text('Cotizaciones', style: Theme.of(context).textTheme.titleLarge)),
            IconButton(onPressed: _saving ? null : _createQuote, icon: const Icon(Icons.add_circle_outline), tooltip: 'Preparar cotización'),
          ]),
          FutureBuilder<List<Map<String, dynamic>>>(
            future: _quotes,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) return const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()));
              if (snapshot.hasError) return Text('No se pudieron cargar las cotizaciones: ${snapshot.error}');
              final records = snapshot.data ?? [];
              if (records.isEmpty) return const Text('Todavía no hay cotizaciones para esta orden.');
              return Column(children: records.map((quote) {
                final amount = _asInt(quote['labor_clp']) + _asInt(quote['parts_clp']);
                final isDraft = quote['status'] == 'draft';
                return Card(child: ListTile(
                  leading: Icon(isDraft ? Icons.edit_note : Icons.request_quote_outlined),
                  title: Text('${quote['description']}'),
                  subtitle: Text('${_currency(amount)} · ${'${quote['status'] ?? 'draft'}'.replaceAll('_', ' ')}${quote['notes'] == null ? '' : '\n${quote['notes']}'}'),
                  isThreeLine: quote['notes'] != null,
                  trailing: isDraft ? IconButton(onPressed: _saving ? null : () => _publishQuote(quote), icon: const Icon(Icons.send_outlined), tooltip: 'Publicar para cliente') : null,
                ));
              }).toList());
            },
          ),
        ]),
      );
}

class _PosScreen extends StatefulWidget {
  const _PosScreen({required this.api});
  final ApiClient api;

  @override
  State<_PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends State<_PosScreen> {
  final _discountController = TextEditingController(text: '0');
  List<Map<String, dynamic>> _products = [];
  List<Map<String, dynamic>> _customers = [];
  List<Map<String, dynamic>> _sales = [];
  final Map<int, double> _cart = {};
  int? _customerId;
  String _paymentMethod = 'cash';
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _discountController.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() { _loading = true; _error = null; });
    try {
      final results = await Future.wait([
        widget.api.get('/api/v1/products'),
        widget.api.get('/api/v1/customers'),
        widget.api.get('/api/v1/sales'),
      ]);
      if (!mounted) return;
      setState(() {
        _products = _asMaps(results[0]);
        _customers = _asMaps(results[1]);
        _sales = _asMaps(results[2]);
        _cart.removeWhere((id, quantity) {
          final product = _findProduct(id);
          return product == null || quantity > _number(product['stock_quantity']);
        });
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> _asMaps(dynamic value) => value is List
      ? value.whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList()
      : <Map<String, dynamic>>[];

  Map<String, dynamic>? _findProduct(int id) {
    for (final product in _products) {
      if (product['id'] == id) return product;
    }
    return null;
  }

  double _number(dynamic value) => value is num ? value.toDouble() : double.tryParse('$value') ?? 0;
  int _money(dynamic value) => value is num ? value.round() : int.tryParse('$value') ?? 0;

  int get _subtotal => _cart.entries.fold(0, (total, entry) {
        final product = _findProduct(entry.key);
        if (product == null) return total;
        return total + (entry.value * _money(product['price_clp'])).round();
      });

  int get _discount => int.tryParse(_discountController.text.trim()) ?? 0;
  int get _total => (_subtotal - _discount).clamp(0, _subtotal).toInt();

  void _changeQuantity(Map<String, dynamic> product, double delta) {
    final id = product['id'] as int?;
    if (id == null) return;
    final next = (_cart[id] ?? 0) + delta;
    if (next <= 0) {
      setState(() => _cart.remove(id));
    } else if (next > _number(product['stock_quantity'])) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('La cantidad supera el stock disponible.')));
    } else {
      setState(() => _cart[id] = next);
    }
  }

  Future<void> _checkout() async {
    if (_cart.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Agrega al menos un producto a la venta.')));
      return;
    }
    if (_discount < 0 || _discount > _subtotal) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('El descuento debe estar entre cero y el subtotal.')));
      return;
    }
    final total = _total;
    final method = _paymentMethod;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar venta'),
        content: Text(method == 'mercado_pago'
            ? 'Se registrará la venta por ${_formatMoney(total)}. Mercado Pago quedará pendiente; esta versión no inicia el cobro.'
            : 'Se registrará la venta por ${_formatMoney(total)} y se descontarán los productos del inventario.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Confirmar')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _saving = true);
    Map<String, dynamic>? sale;
    try {
      final result = await widget.api.postJson('/api/v1/sales', {
        if (_customerId != null) 'customer_id': _customerId,
        'discount_clp': _discount,
        'lines': _cart.entries.map((entry) {
          final product = _products.firstWhere((item) => item['id'] == entry.key);
          return {
            'product_id': entry.key,
            'description': product['name'],
            'quantity': entry.value,
            'unit_price_clp': _money(product['price_clp']),
          };
        }).toList(),
      });
      sale = Map<String, dynamic>.from(result as Map);
      setState(() {
        _cart.clear();
        _discountController.text = '0';
      });

      if (total > 0) {
        await widget.api.postJson('/api/v1/sales/${sale['id']}/payments', {
          'method': method,
          'amount_clp': total,
        });
      }
      await _refresh();
      if (!mounted) return;
      final message = method == 'mercado_pago' && total > 0
          ? 'Venta ${sale['receipt_code']} registrada; pago Mercado Pago pendiente.'
          : 'Venta ${sale['receipt_code']} registrada correctamente.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    } catch (error) {
      if (sale != null) {
        await _refresh();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Venta ${sale['receipt_code']} creada, pero no se pudo registrar el pago: ${error.toString().replaceFirst('Exception: ', '')}'),
          duration: const Duration(seconds: 7),
        ));
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString().replaceFirst('Exception: ', ''))));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _formatMoney(int amount) => '\$${amount.toString()} CLP';

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('No se pudo cargar el POS.\n$_error', textAlign: TextAlign.center),
          const SizedBox(height: 12),
          OutlinedButton.icon(onPressed: _refresh, icon: const Icon(Icons.refresh), label: const Text('Reintentar')),
        ]),
      ));
    }
    final available = _products.where((product) => product['active'] != false).toList();
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(padding: const EdgeInsets.fromLTRB(12, 8, 12, 28), children: [
        Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Nueva venta', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            if (available.isEmpty)
              const Text('No hay productos disponibles en el inventario.')
            else
              ...available.map(_productTile),
            const Divider(height: 28),
            Text('Detalle', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (_cart.isEmpty) const Text('Agrega productos para comenzar.')
            else ..._cart.entries.map(_cartTile),
            const SizedBox(height: 12),
            DropdownButtonFormField<int?>(
              value: _customerId,
              decoration: const InputDecoration(labelText: 'Cliente (opcional)'),
              items: [
                const DropdownMenuItem<int?>(value: null, child: Text('Venta sin cliente')),
                ..._customers.map((customer) => DropdownMenuItem<int?>(
                  value: customer['id'] as int?, child: Text('${customer['full_name']}'),
                )),
              ],
              onChanged: (value) => setState(() => _customerId = value),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _discountController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Descuento (CLP)', prefixText: '\$'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _paymentMethod,
              decoration: const InputDecoration(labelText: 'Medio de pago'),
              items: const [
                DropdownMenuItem(value: 'cash', child: Text('Efectivo')),
                DropdownMenuItem(value: 'card', child: Text('Tarjeta / terminal externa')),
                DropdownMenuItem(value: 'transfer', child: Text('Transferencia')),
                DropdownMenuItem(value: 'mercado_pago', child: Text('Mercado Pago (pendiente)')),
              ],
              onChanged: (value) { if (value != null) setState(() => _paymentMethod = value); },
            ),
            const SizedBox(height: 16),
            _totalRow('Subtotal', _subtotal),
            _totalRow('Descuento', _discount.clamp(0, _subtotal).toInt()),
            const Divider(),
            _totalRow('Total', _total, emphasize: true),
            const SizedBox(height: 12),
            SizedBox(width: double.infinity, child: FilledButton.icon(
              onPressed: _saving ? null : _checkout,
              icon: _saving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.point_of_sale),
              label: Text(_saving ? 'Guardando…' : 'Confirmar venta'),
            )),
          ],
        ))),
        const SizedBox(height: 12),
        Text('Ventas recientes', style: Theme.of(context).textTheme.titleLarge),
        if (_sales.isEmpty)
          const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('Todavía no hay ventas.')))
        else
          ..._sales.take(10).map((sale) => _RecordCard(data: sale)),
      ]),
    );
  }

  Widget _productTile(Map<String, dynamic> product) {
    final id = product['id'] as int?;
    final stock = _number(product['stock_quantity']);
    final quantity = id == null ? 0 : (_cart[id] ?? 0);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text('${product['name'] ?? 'Producto'}'),
      subtitle: Text('Stock: ${stock.toStringAsFixed(stock % 1 == 0 ? 0 : 2)} ${product['unit'] ?? ''} · ${_formatMoney(_money(product['price_clp']))}'),
      trailing: stock <= 0
          ? const Chip(label: Text('Sin stock'))
          : quantity == 0
              ? IconButton(onPressed: () => _changeQuantity(product, 1), icon: const Icon(Icons.add_shopping_cart), tooltip: 'Agregar')
              : TextButton.icon(onPressed: () => _changeQuantity(product, 1), icon: const Icon(Icons.add), label: Text(quantity.toStringAsFixed(quantity % 1 == 0 ? 0 : 2))),
    );
  }

  Widget _cartTile(MapEntry<int, double> entry) {
    final product = _products.firstWhere((item) => item['id'] == entry.key);
    final lineTotal = (entry.value * _money(product['price_clp'])).round();
    return Row(children: [
      Expanded(child: Text('${product['name']} × ${entry.value.toStringAsFixed(entry.value % 1 == 0 ? 0 : 2)}')),
      IconButton(onPressed: () => _changeQuantity(product, -1), icon: const Icon(Icons.remove_circle_outline), tooltip: 'Quitar una unidad'),
      Text(_formatMoney(lineTotal)),
    ]);
  }

  Widget _totalRow(String label, int value, {bool emphasize = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(label, style: emphasize ? const TextStyle(fontWeight: FontWeight.bold) : null),
          Text(_formatMoney(value), style: emphasize ? Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold) : null),
        ]),
      );
}

class _RecordCard extends StatelessWidget {
  const _RecordCard({required this.data, this.onApprove, this.onReject, this.onOpen});
  final Map<String, dynamic> data;
  final VoidCallback? onApprove;
  final VoidCallback? onReject;
  final VoidCallback? onOpen;

  String _displayValue(String key, dynamic value) {
    if (value == null || value is Map || value is List) return '';
    if (key.endsWith('_clp')) return '\$${value.toString()}';
    return value.toString().replaceAll('_', ' ');
  }

  @override
  Widget build(BuildContext context) {
    final entries = data.entries.where((entry) =>
        !{'id', 'customer_id', 'vehicle_id', 'work_order_id', 'storage_path', 'google_event_id'}.contains(entry.key) &&
        _displayValue(entry.key, entry.value).isNotEmpty).take(4).toList();
    final title = (data['code'] ?? data['plate'] ?? data['full_name'] ?? data['name'] ?? data['description'] ?? data['service_type'] ?? 'Registro').toString();
    return Card(margin: const EdgeInsets.symmetric(vertical: 6), child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        for (final entry in entries)
          Padding(padding: const EdgeInsets.only(top: 5), child: Text('${entry.key.replaceAll('_', ' ')}: ${_displayValue(entry.key, entry.value)}')),
        if (onApprove != null || onReject != null || onOpen != null) ...[
          const SizedBox(height: 12),
          Wrap(spacing: 8, children: [
            if (onOpen != null) OutlinedButton.icon(onPressed: onOpen, icon: const Icon(Icons.fact_check_outlined), label: const Text('Ver inspección')),
            if (onReject != null) OutlinedButton(onPressed: onReject, child: const Text('Rechazar')),
            if (onApprove != null) FilledButton(onPressed: onApprove, child: const Text('Aprobar')),
          ]),
        ],
      ]),
    ));
  }
}
