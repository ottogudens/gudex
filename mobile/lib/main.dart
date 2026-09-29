import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

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
  const _RecordCard({required this.data, this.onApprove, this.onReject});
  final Map<String, dynamic> data;
  final VoidCallback? onApprove;
  final VoidCallback? onReject;

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
        if (onApprove != null || onReject != null) ...[
          const SizedBox(height: 12),
          Wrap(spacing: 8, children: [
            OutlinedButton(onPressed: onReject, child: const Text('Rechazar')),
            FilledButton(onPressed: onApprove, child: const Text('Aprobar')),
          ]),
        ],
      ]),
    ));
  }
}
