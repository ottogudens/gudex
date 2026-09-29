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
        Expanded(child: _ModuleList(api: api, module: modules[selected], role: widget.role)),
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
