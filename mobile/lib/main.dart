import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:printing/printing.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'services/api_client.dart';
import 'services/draft_store.dart';
import 'core/constants.dart';
import 'core/theme.dart';
import 'providers/auth_provider.dart';
import 'screens/auth/customer_access_page.dart';
import 'screens/auth/login_page.dart';
import 'screens/customer_appointments_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/inventory_screen.dart';
import 'screens/users_screen.dart';
import 'screens/agenda_screen.dart';
import 'screens/scanner_screen.dart';
import 'screens/vehicle_history_screen.dart';

part 'quotes_screen.dart';

// ---------------------------------------------------------------------------
// Backward-compatible aliases so the existing screen code (below) continues
// to compile without changes.  These will be removed incrementally as each
// screen is extracted into its own file.
// ---------------------------------------------------------------------------
const _storage = FlutterSecureStorage();
const _apiBaseUrl = apiBaseUrl;

// Keep the global ValueNotifier alive for screens that still reference it
// directly.  New code should use [themeModeProvider] instead.
final _themeMode = ValueNotifier<ThemeMode>(ThemeMode.light);

Future<void> toggleGudexTheme() async {
  final next = _themeMode.value == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
  _themeMode.value = next;
  await _storage.write(key: 'theme_mode', value: next == ThemeMode.dark ? 'dark' : 'light');
}

IconButton gudexThemeButton(BuildContext context) => IconButton(
      tooltip: Theme.of(context).brightness == Brightness.dark ? 'Cambiar a modo claro' : 'Cambiar a modo oscuro',
      icon: Icon(Theme.of(context).brightness == Brightness.dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined),
      onPressed: toggleGudexTheme,
    );

// Re-export helpers under their old private names so the rest of the file
// keeps compiling.
const _statusLabels = statusLabels;
const _fieldLabels = fieldLabels;

// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _themeMode.value = await loadThemeMode();
  runApp(const ProviderScope(child: LubricentroApp()));
}


class LubricentroApp extends StatelessWidget {
  const LubricentroApp({super.key});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<ThemeMode>(
        valueListenable: _themeMode,
        builder: (context, themeMode, _) => MaterialApp(
        title: 'Gudex',
        debugShowCheckedModeBanner: false,
        theme: gudexLightTheme(),
        darkTheme: gudexDarkTheme(),
        themeMode: themeMode,
        home: const SessionGate(),
      ));
}

class SessionGate extends ConsumerStatefulWidget {
  const SessionGate({super.key});

  @override
  ConsumerState<SessionGate> createState() => _SessionGateState();
}

class _SessionGateState extends ConsumerState<SessionGate> {
  @override
  void initState() {
    super.initState();
    final invite = Uri.base.queryParameters['invite'];
    final reset = Uri.base.queryParameters['reset'];
    final accessToken = invite ?? reset;
    final isPasswordReset = Uri.base.queryParameters.containsKey('reset');

    if (accessToken != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(authProvider.notifier).setDeepLinkParams(
              accessToken: accessToken,
              isPasswordReset: isPasswordReset,
            );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);

    if (authState.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (authState.accessToken != null) {
      return CustomerAccessPage(
        token: authState.accessToken!,
        passwordReset: authState.isPasswordReset,
        apiBaseUrl: _apiBaseUrl,
      );
    }

    if (!authState.isAuthenticated) {
      return const LoginPage();
    }

    return HomePage(
      token: authState.token!,
      baseUrl: _apiBaseUrl,
      role: authState.role!,
      name: authState.name ?? 'Usuario',
    );
  }
}





class _Module {
  const _Module(this.title, this.path, {this.keyName});
  final String title;
  final String path;
  final String? keyName;
}

class HomePage extends ConsumerStatefulWidget {
  const HomePage({required this.token, required this.baseUrl, required this.role, required this.name, super.key});
  final String token;
  final String baseUrl;
  final String role;
  final String name;

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
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
        _Module('Mis trabajos', '/api/v1/work-orders/mine'),
        _Module('Órdenes de trabajo', '/api/v1/work-orders'),
        _Module('Inventario', '/api/v1/products'),
        _Module('Agenda', '/api/v1/appointments'),
        _Module('Scanner LAUNCH', '/api/v1/scanner-reports'),
      ];
    }
    return const [
      _Module('Panel principal', '/api/v1/dashboard'),
      _Module('Órdenes de trabajo', '/api/v1/work-orders'),
      _Module('Clientes', '/api/v1/customers'),
      _Module('Inventario', '/api/v1/products'),
      _Module('Agenda', '/api/v1/appointments'),
      _Module('Scanner LAUNCH', '/api/v1/scanner-reports'),
      _Module('POS', '/api/v1/sales'),
      _Module('Usuarios', '/api/v1/users'),
      _Module('Cotizaciones', '/api/v1/quotes'),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final modules = _modules;
    final selected = _selected.clamp(0, modules.length - 1).toInt();
    final api = ApiClient(widget.baseUrl, token: widget.token);
    final useNavigationRail = MediaQuery.sizeOf(context).width >= 900;
    final pageContent = SafeArea(child: LayoutBuilder(builder: (context, constraints) => Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1320),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(padding: const EdgeInsets.fromLTRB(18, 16, 18, 12), child: Row(children: [
            CircleAvatar(
              radius: 23,
              backgroundColor: const Color(0xFFFFF3A8),
              child: Icon(widget.role == 'customer' ? Icons.person_outline : Icons.handyman_outlined,
                  color: GudexColors.primary),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Hola, ${widget.name}', maxLines: 1, overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.onSurface)),
              Text(_roleName(widget.role), style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ])),
            if (constraints.maxWidth >= 600) _RoleChip(role: widget.role),
          ])),
          Expanded(
            child: Center(child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1120),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                child: KeyedSubtree(
                  key: ValueKey(modules[selected].path),
                  child: Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child:
                modules[selected].path == '/api/v1/sales'
                    ? _PosScreen(api: api)
                    : modules[selected].path == '/api/v1/quotes'
                        ? _QuotesScreen(api: api)
                    : modules[selected].path == '/api/v1/dashboard'
                        ? DashboardScreen(api: api, onOpenModule: (index) => setState(() => _selected = index))
                    : modules[selected].path == '/api/v1/users'
                        ? UsersScreen(api: api)
                    : modules[selected].path == '/api/v1/products'
                        ? InventoryScreen(api: api, canManage: widget.role == 'admin')
                    : modules[selected].path == '/api/v1/appointments'
                        ? AgendaScreen(api: api, role: widget.role)
                    : modules[selected].path == '/api/v1/portal/appointments'
                        ? CustomerAppointmentsScreen(api: api)
                    : modules[selected].path == '/api/v1/scanner-reports'
                        ? ScannerScreen(api: api, role: widget.role)
                    : {'/api/v1/work-orders', '/api/v1/work-orders/mine', '/api/v1/customers'}.contains(modules[selected].path)
                        ? _WorkshopScreen(api: api, module: modules[selected], role: widget.role)
                        : _ModuleList(api: api, module: modules[selected], role: widget.role),
                  ),
                ),
              ),
            )),
          ),
        ]),
      ),
    )));
    return Scaffold(
      appBar: AppBar(title: Image.asset('assets/gudex-logo.png', height: 34, width: 126, fit: BoxFit.contain, semanticLabel: 'Gudex Lubricentro Serviteca'), actions: [
        IconButton(
          tooltip: Theme.of(context).brightness == Brightness.dark ? 'Cambiar a modo claro' : 'Cambiar a modo oscuro',
          icon: Icon(Theme.of(context).brightness == Brightness.dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined),
          onPressed: () async {
            final next = Theme.of(context).brightness == Brightness.dark ? ThemeMode.light : ThemeMode.dark;
            _themeMode.value = next;
            await _storage.write(key: 'theme_mode', value: next == ThemeMode.dark ? 'dark' : 'light');
          },
        ),
        IconButton(tooltip: 'Asistente IA', icon: const Icon(Icons.auto_awesome), onPressed: () => Navigator.push(context,
          MaterialPageRoute(builder: (_) => _AssistantScreen(api: api, role: widget.role)))),
        if (widget.role == 'admin') IconButton(tooltip: 'Integraciones', icon: const Icon(Icons.link), onPressed: () => Navigator.push(context,
          MaterialPageRoute(builder: (_) => _IntegrationSettingsScreen(api: api)))),
        IconButton(onPressed: () => ref.read(authProvider.notifier).signOut(), tooltip: 'Cerrar sesión', icon: const Icon(Icons.logout)),
      ]),
      body: useNavigationRail ? Row(children: [
        NavigationRail(
          extended: true,
          selectedIndex: selected,
          onDestinationSelected: (index) => setState(() => _selected = index),
          destinations: [for (final module in modules) NavigationRailDestination(
            icon: Icon(_iconFor(module.title)), label: Text(module.title),
          )],
        ),
        const VerticalDivider(width: 1, thickness: 1, color: GudexColors.line),
        Expanded(child: pageContent),
      ]) : pageContent,
      bottomNavigationBar: useNavigationRail ? null : SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: MediaQuery.sizeOf(context).width < modules.length * 88.0
              ? modules.length * 88.0 : MediaQuery.sizeOf(context).width,
          child: NavigationBar(
        selectedIndex: selected,
        onDestinationSelected: (index) => setState(() => _selected = index),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: [for (final module in modules) NavigationDestination(
          icon: Icon(_iconFor(module.title)), label: _navLabel(module.title),
        )],
          ),
        ),
      ),
    );
  }

  IconData _iconFor(String title) {
    if (title.contains('Panel')) return Icons.space_dashboard_outlined;
    if (title.toLowerCase().contains('orden') || title.toLowerCase().contains('trabajos')) return Icons.assignment_outlined;
    if (title.contains('Inventario')) return Icons.inventory_2_outlined;
    if (title.toLowerCase().contains('cliente') || title.toLowerCase().contains('vehículos')) return Icons.directions_car_outlined;
    if (title.contains('Cotizaciones')) return Icons.request_quote_outlined;
    return Icons.calendar_month_outlined;
  }

  String _navLabel(String title) {
    if (title == 'Órdenes de trabajo') return 'Órdenes';
    if (title == 'Trabajos anteriores') return 'Trabajos';
    if (title == 'Mis vehículos') return 'Vehículos';
    if (title == 'Inventario') return 'Stock';
    if (title == 'Cotizaciones') return 'Cotiz.';
    if (title == 'Mis citas') return 'Citas';
    return title;
  }

  String _roleName(String role) {
    if (role == 'admin') return 'Administración';
    if (role == 'mechanic') return 'Equipo mecánico';
    return 'Portal de cliente';
  }
}

class _RoleChip extends StatelessWidget {
  const _RoleChip({required this.role});
  final String role;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
    decoration: BoxDecoration(color: const Color(0xFFE5F2F4), borderRadius: BorderRadius.circular(30)),
    child: Text(role == 'admin' ? 'ADMINISTRACIÓN' : role == 'mechanic' ? 'MECÁNICO' : 'CLIENTE',
      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: .5, color: GudexColors.primary)),
  );
}

class _AssistantScreen extends StatefulWidget {
  const _AssistantScreen({required this.api, required this.role});
  final ApiClient api;
  final String role;

  @override
  State<_AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends State<_AssistantScreen> {
  final _message = TextEditingController();
  String _contextType = 'general';
  int? _selectedContextId;
  List<dynamic> _orders = [];
  List<dynamic> _vehicles = [];
  Map<String, dynamic>? _answer;
  int? _interactionId;
  bool _busy = false;

  String get _path => widget.role == 'customer' ? '/api/v1/portal/assistant/query' : '/api/v1/assistant/query';

  @override
  void initState() {
    super.initState();
    _loadContextRecords();
  }

  Future<void> _loadContextRecords() async {
    try {
      final paths = widget.role == 'customer'
          ? ['/api/v1/portal/work-orders', '/api/v1/portal/profile']
          : ['/api/v1/work-orders', '/api/v1/vehicles'];
      final values = await Future.wait(paths.map(widget.api.get));
      if (!mounted) return;
      setState(() {
        _orders = values[0] as List;
        final vehicleResponse = values[1];
        _vehicles = widget.role == 'customer'
            ? (vehicleResponse as Map)['vehicles'] as List? ?? []
            : vehicleResponse as List;
      });
    } catch (_) {
      // El asistente sigue disponible en modo general aunque no cargue el contexto.
    }
  }

  Future<void> _ask() async {
    if (_message.text.trim().length < 2) return;
    final id = _selectedContextId;
    if ((_contextType == 'work_order' || _contextType == 'vehicle') && id == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Selecciona un registro')));
      return;
    }
    setState(() => _busy = true);
    try {
      final result = Map<String, dynamic>.from(await widget.api.postJson(_path, {
        'message': _message.text.trim(), 'context_type': _contextType,
        if (id != null) 'context_id': id,
      }) as Map);
      setState(() { _answer = result; _interactionId = result['interaction_id'] as int?; });
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirm(bool approved) async {
    if (_interactionId == null) return;
    setState(() => _busy = true);
    try {
      final result = await widget.api.postJson('/api/v1/assistant/interactions/$_interactionId/confirm', {'approved': approved});
      if (!mounted) return;
      setState(() { _answer = {...?_answer, 'action_result': result, 'proposed_action': null}; });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(approved ? 'Acción confirmada y aplicada' : 'Propuesta descartada')));
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Asistente Gudex')),
    body: ListView(padding: const EdgeInsets.all(16), children: [
      const Text('Consulta sobre una orden, vehículo, inventario, agenda o el uso del sistema. La IA puede equivocarse; verifica las recomendaciones mecánicas.'),
      const SizedBox(height: 14),
      DropdownButtonFormField<String>(value: _contextType, decoration: const InputDecoration(labelText: 'Contexto'),
        items: [
          const DropdownMenuItem(value: 'general', child: Text('General')),
          const DropdownMenuItem(value: 'work_order', child: Text('Trabajo / orden')),
          const DropdownMenuItem(value: 'vehicle', child: Text('Vehículo / historial')),
          if (widget.role != 'customer') ...[
            const DropdownMenuItem(value: 'inventory', child: Text('Inventario')),
            const DropdownMenuItem(value: 'agenda', child: Text('Agenda de 7 días')),
          ],
        ], onChanged: (value) { if (value != null) setState(() { _contextType = value; _selectedContextId = null; }); }),
      if (_contextType == 'work_order' || _contextType == 'vehicle') ...[
        const SizedBox(height: 10),
        DropdownButtonFormField<int>(value: _selectedContextId,
          decoration: InputDecoration(labelText: _contextType == 'work_order' ? 'Selecciona un trabajo' : 'Selecciona un vehículo'),
          items: [
            for (final raw in (_contextType == 'work_order' ? _orders : _vehicles))
              DropdownMenuItem<int>(value: raw['id'] as int,
                child: Text(_contextType == 'work_order'
                    ? '${raw['code'] ?? 'Orden'} · ${spanishStatus(raw['status'])}'
                    : '${raw['plate'] ?? ''} · ${raw['make'] ?? ''} ${raw['model'] ?? ''}')),
          ], onChanged: (value) => setState(() => _selectedContextId = value)),
        if ((_contextType == 'work_order' ? _orders : _vehicles).isEmpty)
          const Padding(padding: EdgeInsets.only(top: 6), child: Text('No hay registros disponibles para este perfil.')),
      ],
      const SizedBox(height: 10), TextField(controller: _message, minLines: 2, maxLines: 5,
        decoration: const InputDecoration(labelText: '¿En qué te ayudo?')),
      const SizedBox(height: 10), FilledButton.icon(onPressed: _busy ? null : _ask,
        icon: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.send),
        label: const Text('Consultar')),
      if (_answer != null) ...[
        const SizedBox(height: 18),
        Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Respuesta de IA', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8), Text('${_answer!['answer'] ?? ''}'),
          for (final pair in <String, String>{'Hechos registrados': 'known_facts', 'Posibles causas': 'possible_causes', 'Verificaciones sugeridas': 'suggested_checks'}.entries)
            if ((_answer![pair.value] as List? ?? []).isNotEmpty) ...[
              const SizedBox(height: 12), Text(pair.key, style: const TextStyle(fontWeight: FontWeight.bold)),
              for (final item in _answer![pair.value] as List) Padding(padding: const EdgeInsets.only(top: 4), child: Text('• $item')),
            ],
          if (_answer!['safety_warning'] != null) ...[
            const SizedBox(height: 12), Container(width: double.infinity, padding: const EdgeInsets.all(12),
              color: Theme.of(context).colorScheme.errorContainer, child: Text('Seguridad: ${_answer!['safety_warning']}')),
          ],
          if (_answer!['proposed_action'] is Map) ...[
            const Divider(height: 24), Text((_answer!['proposed_action'] as Map)['confirmation_message']?.toString() ?? 'La IA propone actualizar información.'),
            const SizedBox(height: 8), Wrap(spacing: 8, children: [
              OutlinedButton(onPressed: _busy ? null : () => _confirm(false), child: const Text('Descartar')),
              FilledButton(onPressed: _busy ? null : () => _confirm(true), child: const Text('Confirmar acción')),
            ]),
          ],
          if (_answer!['action_result'] != null) Text('Resultado: ${_answer!['action_result']}'),
        ]))),
      ],
    ]),
  );
}

class _IntegrationSettingsScreen extends StatefulWidget {
  const _IntegrationSettingsScreen({required this.api});
  final ApiClient api;

  @override
  State<_IntegrationSettingsScreen> createState() => _IntegrationSettingsScreenState();
}

class _IntegrationSettingsScreenState extends State<_IntegrationSettingsScreen> {
  Map<String, dynamic>? _status;
  List<dynamic> _candidates = [];
  String _candidateSource = 'gmail';
  bool _busy = false;

  @override
  void initState() { super.initState(); _refresh(); }

  Future<void> _refresh() async {
    try { final data = Map<String, dynamic>.from(await widget.api.get('/api/v1/integrations/status') as Map); if (mounted) setState(() => _status = data); }
    catch (error) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString()))); }
  }

  Future<void> _connect() async {
    setState(() => _busy = true);
    try {
      final data = Map<String, dynamic>.from(await widget.api.post('/api/v1/integrations/google/authorize') as Map);
      final url = Uri.parse(data['authorization_url'] as String);
      if (!await launchUrl(url, mode: LaunchMode.externalApplication)) throw Exception('No se pudo abrir Google OAuth');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Completa el acceso a Google y vuelve a esta pantalla.')));
    } catch (error) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString()))); }
    finally { if (mounted) setState(() => _busy = false); }
  }

  Future<void> _syncCalendar() async {
    final approved = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: const Text('Sincronizar agenda'), content: const Text('Crear o actualizar en Google Calendar las citas pendientes de Gudex?'),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Sincronizar'))],
    ));
    if (approved != true) return;
    try {
      final result = Map<String, dynamic>.from(await widget.api.post('/api/v1/integrations/google/calendar/sync-pending') as Map);
      await _refresh();
      final failures = (result['results'] as List? ?? []).where((item) => item['status'] == 'error').length;
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(
        'Citas procesadas: ${result['processed']}${failures > 0 ? ' · Errores: $failures' : ''}',
      )));
    } catch (error) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString()))); }
  }

  Future<void> _disconnectGoogle() async {
    final approved = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: const Text('Desconectar Google'),
      content: const Text('Gudex revocará y eliminará las credenciales guardadas para esta cuenta.'),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Desconectar'))],
    ));
    if (approved != true) return;
    try {
      await widget.api.delete('/api/v1/integrations/google');
      await _refresh();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cuenta Google desconectada')));
    } catch (error) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString()))); }
  }

  Future<void> _chooseAiModel() async {
    setState(() => _busy = true);
    try {
      final raw = Map<String, dynamic>.from(await widget.api.get('/api/v1/integrations/ai/models') as Map);
      final models = (raw['models'] as List? ?? []).map((item) => item.toString()).toList();
      String selected = raw['current_model']?.toString() ?? '';
      final chosen = await showDialog<String>(context: context, builder: (context) => AlertDialog(
        title: const Text('Modelo del asistente'),
        content: StatefulBuilder(builder: (context, update) => SizedBox(width: 440, child: DropdownButtonFormField<String>(
          value: models.contains(selected) ? selected : null,
          decoration: const InputDecoration(labelText: 'Modelo compatible'),
          items: models.map((model) => DropdownMenuItem(value: model, child: Text(model))).toList(),
          onChanged: (value) { if (value != null) update(() => selected = value); },
        ))),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')), FilledButton(onPressed: () => Navigator.pop(context, selected), child: const Text('Usar modelo'))],
      ));
      if (chosen == null || chosen.isEmpty) return;
      await widget.api.putJson('/api/v1/integrations/ai/model', {'model': chosen});
      await _refresh();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Modelo del asistente actualizado.')));
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString().replaceFirst('Exception: ', ''))));
    } finally { if (mounted) setState(() => _busy = false); }
  }

  Future<void> _loadCandidates(String source) async {
    setState(() => _busy = true);
    try { final result = await widget.api.get('/api/v1/integrations/google/scanner-candidates?source=$source');
      setState(() { _candidates = result as List; _candidateSource = source; });
    } catch (error) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString()))); }
    finally { if (mounted) setState(() => _busy = false); }
  }

  Future<void> _import(Map<String, dynamic> item, String source) async {
    final vehicle = TextEditingController();
    final order = TextEditingController();
    final values = await showDialog<List<String>>(context: context, builder: (context) => AlertDialog(
      title: Text('Adjuntar ${item['filename'] ?? 'informe PDF'}'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: vehicle, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'ID del vehículo *')),
        TextField(controller: order, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'ID de orden (opcional)')),
      ]),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.pop(context, [vehicle.text, order.text]), child: const Text('Importar'))],
    ));
    if (values == null || int.tryParse(values[0]) == null) return;
    try {
      await widget.api.postJson('/api/v1/integrations/google/scanner-import', {
        'source': source, 'external_id': item['external_id'], 'filename': item['filename'],
        'vehicle_id': int.parse(values[0]), if (int.tryParse(values[1]) != null) 'work_order_id': int.parse(values[1]),
      });
      if (mounted) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Informe LAUNCH adjuntado'))); _loadCandidates(source); }
    } catch (error) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString()))); }
  }

  @override
  Widget build(BuildContext context) {
    final google = Map<String, dynamic>.from(_status?['google'] as Map? ?? {});
    final ai = Map<String, dynamic>.from(_status?['ai'] as Map? ?? {});
    final mercadoPago = Map<String, dynamic>.from(_status?['mercado_pago'] as Map? ?? {});
    return Scaffold(appBar: AppBar(title: const Text('Integraciones'), actions: [IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh))]),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Card(child: ListTile(leading: const Icon(Icons.account_balance_wallet_outlined, color: GudexColors.primary),
          title: const Text('Mercado Pago Checkout Pro'),
          subtitle: Text(mercadoPago['connected'] == true
              ? 'Checkout ${mercadoPago['mode'] == 'test' ? 'de prueba' : 'productivo'} configurado en Railway'
              : 'Falta configurar Access Token y secreto de Webhook en Railway. Point se registra como terminal externa.'),
        )),
        Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Google Workspace', style: Theme.of(context).textTheme.titleLarge),
          Text(google['connected'] == true ? 'Conectado: ${google['account_email'] ?? 'cuenta Google'}' : 'Sin conectar'),
          const SizedBox(height: 10), FilledButton.icon(onPressed: _busy ? null : _connect, icon: const Icon(Icons.login), label: const Text('Conectar o renovar Google')),
          if (google['connected'] == true) ...[
            Wrap(spacing: 8, children: [
              OutlinedButton(onPressed: _busy ? null : () => _loadCandidates('gmail'), child: const Text('Buscar PDFs en Gmail')),
              OutlinedButton(onPressed: _busy || google['drive_folder_configured'] != true ? null : () => _loadCandidates('drive'), child: const Text('Buscar PDFs en Drive')),
              OutlinedButton(onPressed: _busy ? null : _syncCalendar, child: const Text('Sincronizar citas pendientes')),
              TextButton(onPressed: _busy ? null : _disconnectGoogle, child: const Text('Desconectar Google')),
            ]),
            for (final raw in _candidates) Card(color: Theme.of(context).colorScheme.surfaceContainerLow,
              child: ListTile(title: Text(raw['filename']?.toString() ?? 'PDF'), subtitle: Text(raw['subject']?.toString() ?? raw['modified_at']?.toString() ?? ''),
                trailing: IconButton(tooltip: 'Importar y vincular', icon: const Icon(Icons.attach_file), onPressed: () => _import(Map<String, dynamic>.from(raw as Map), _candidateSource)))),
          ],
        ]))),
        Card(child: ListTile(leading: const Icon(Icons.auto_awesome), title: const Text('Asistente de IA'),
          subtitle: Text(ai['available'] == true ? 'Configurado: ' + ai['provider'].toString() + ' / ' + ai['model'].toString() : 'Falta configurar proveedor y clave en Railway'),
          trailing: ai['available'] == true ? OutlinedButton(onPressed: _busy ? null : _chooseAiModel, child: const Text('Cambiar modelo')) : null)),
        const Card(child: Padding(padding: EdgeInsets.all(14), child: Text('La conexión OAuth y las claves del proveedor se administran en Railway. Esta pantalla muestra el estado y permite iniciar flujos autorizados.'))),
      ]));
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
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              CircularProgressIndicator(), SizedBox(height: 12), Text('Cargando información…'),
            ]),
          );
          if (snapshot.hasError) return Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(
            mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.cloud_off_outlined, size: 40, color: Theme.of(context).colorScheme.error),
              const SizedBox(height: 12),
              Text('No se pudo cargar ${widget.module.title.toLowerCase()}.', textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 6),
              Text('${snapshot.error}'.replaceFirst('Exception: ', ''), textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 12),
              OutlinedButton.icon(onPressed: () => setState(() => _items = _load()),
                icon: const Icon(Icons.refresh), label: const Text('Reintentar')),
            ],
          )));
          final items = snapshot.data ?? [];
          if (items.isEmpty) return RefreshIndicator(
            onRefresh: () async => setState(() => _items = _load()),
            child: ListView(children: [SizedBox(height: 360, child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 64, height: 64, decoration: const BoxDecoration(color: Color(0xFFE5F2F4), shape: BoxShape.circle),
                child: const Icon(Icons.inbox_outlined, color: GudexColors.primary, size: 30)),
              const SizedBox(height: 14),
              Text('Aún no hay ${widget.module.title.toLowerCase()}.', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 5),
              const Text('Desliza hacia abajo para actualizar.', style: TextStyle(color: Color(0xFF637986))),
            ])))]),
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
                      : widget.module.path == '/api/v1/portal/profile' && data['id'] is int
                          ? () => Navigator.push(context, MaterialPageRoute(builder: (_) => VehicleHistoryScreen(api: widget.api, vehicleId: data['id'] as int, portal: true)))
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
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar')),
          FilledButton.icon(onPressed: () async {
            try {
              await openGudexPdf(widget.api, '/api/v1/portal/work-orders/$orderId/inspection-report.pdf', 'Gudex-inspeccion-$orderId.pdf');
            } catch (error) {
              if (mounted) ScaffoldMessenger.of(this.context).showSnackBar(SnackBar(content: Text('No se pudo abrir el informe: $error')));
            }
          }, icon: const Icon(Icons.picture_as_pdf_outlined), label: const Text('PDF')),
        ],
      ));
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
    }
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

  bool get _isOrders => widget.module.path.startsWith('/api/v1/work-orders');
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
          widget.api.get(widget.module.path),
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
    final password = TextEditingController();
    final confirmPassword = TextEditingController();
    bool createPortalAccess = false;
    bool setManualPassword = false;
    try {
      final data = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (context) => StatefulBuilder(builder: (context, update) => AlertDialog(
          title: const Text('Registrar cliente'),
          content: SizedBox(width: 480, child: Form(key: form, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextFormField(controller: name, decoration: const InputDecoration(labelText: 'Nombre completo *'), validator: (v) => (v == null || v.trim().length < 2) ? 'Ingresa el nombre' : null),
            const SizedBox(height: 10),
            TextFormField(controller: rut, decoration: const InputDecoration(labelText: 'RUT (opcional)')),
            const SizedBox(height: 10),
            TextFormField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Teléfono')),
            const SizedBox(height: 10),
            TextFormField(controller: email, keyboardType: TextInputType.emailAddress, decoration: InputDecoration(labelText: createPortalAccess ? 'Correo para acceso al portal *' : 'Correo'), validator: (v) => createPortalAccess && (v == null || !v.contains('@')) ? 'Ingresa un correo válido' : null),
            const SizedBox(height: 8),
            SwitchListTile.adaptive(contentPadding: EdgeInsets.zero, value: createPortalAccess, onChanged: (value) => update(() { createPortalAccess = value; if (!value) setManualPassword = false; }), title: const Text('Crear acceso al portal'), subtitle: const Text('El cliente podrá consultar sus vehículos, trabajos y cotizaciones.')),
            if (createPortalAccess) ...[
              CheckboxListTile.adaptive(contentPadding: EdgeInsets.zero, value: setManualPassword, onChanged: (value) => update(() => setManualPassword = value == true), title: const Text('Definir contraseña manualmente'), subtitle: const Text('El cliente podrá cambiarla después desde el portal.')),
              if (setManualPassword) ...[
                TextFormField(controller: password, obscureText: true, autofillHints: const [AutofillHints.newPassword], decoration: const InputDecoration(labelText: 'Contraseña inicial *', helperText: 'Mínimo 6 caracteres'), validator: (v) => (v == null || v.length < 6) ? 'Usa al menos 6 caracteres' : null),
                const SizedBox(height: 10),
                TextFormField(controller: confirmPassword, obscureText: true, decoration: const InputDecoration(labelText: 'Confirmar contraseña *'), validator: (v) => v != password.text ? 'Las contraseñas no coinciden' : null),
              ],
            ],
          ])))),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
            FilledButton(onPressed: () {
              if (!form.currentState!.validate()) return;
              Navigator.pop(context, {
                'full_name': name.text.trim(),
                if (rut.text.trim().isNotEmpty) 'rut': rut.text.trim(),
                if (phone.text.trim().isNotEmpty) 'phone': phone.text.trim(),
                if (email.text.trim().isNotEmpty) 'email': email.text.trim(),
                'create_portal_access': createPortalAccess,
                if (setManualPassword) 'password': password.text,
              });
            }, child: const Text('Guardar')),
          ],
        )),
      );
      if (data != null) await _save(data['create_portal_access'] == true ? '/api/v1/customers/with-portal-access' : '/api/v1/customers', data, data['password'] != null ? 'Cliente registrado y acceso configurado. Entrega la contraseña al cliente de forma segura.' : data['create_portal_access'] == true ? 'Cliente registrado; invitación preparada para envío.' : 'Cliente registrado');
    } finally {
      name.dispose(); email.dispose(); phone.dispose(); rut.dispose(); password.dispose(); confirmPassword.dispose();
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

  Future<void> _editCustomer(Map<String, dynamic> customer) async {
    final form = GlobalKey<FormState>();
    final name = TextEditingController(text: customer['full_name']?.toString() ?? '');
    final rut = TextEditingController(text: customer['rut']?.toString() ?? '');
    final phone = TextEditingController(text: customer['phone']?.toString() ?? '');
    final email = TextEditingController(text: customer['email']?.toString() ?? '');
    final notes = TextEditingController(text: customer['notes']?.toString() ?? '');
    try {
      final data = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Editar cliente'),
          content: Form(key: form, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextFormField(controller: name, decoration: const InputDecoration(labelText: 'Nombre completo *'), validator: (value) => value == null || value.trim().length < 2 ? 'Ingresa el nombre' : null),
            const SizedBox(height: 10), TextFormField(controller: rut, decoration: const InputDecoration(labelText: 'RUT')),
            const SizedBox(height: 10), TextFormField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Teléfono')),
            const SizedBox(height: 10), TextFormField(controller: email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Correo')),
            const SizedBox(height: 10), TextFormField(controller: notes, maxLines: 3, decoration: const InputDecoration(labelText: 'Notas')),
          ]))),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
            FilledButton(onPressed: () {
              if (!form.currentState!.validate()) return;
              Navigator.pop(context, {'full_name': name.text.trim(), 'rut': rut.text.trim(), 'phone': phone.text.trim(), 'email': email.text.trim(), 'notes': notes.text.trim()});
            }, child: const Text('Guardar cambios')),
          ],
        ),
      );
      if (data == null) return;
      await widget.api.patchJson('/api/v1/customers/' + customer['id'].toString(), data);
      await _refresh();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cliente actualizado')));
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString().replaceFirst('Exception: ', ''))));
    } finally {
      name.dispose(); rut.dispose(); phone.dispose(); email.dispose(); notes.dispose();
    }
  }

  Future<void> _setCustomerPassword(Map<String, dynamic> customer) async {
    if ((customer['email']?.toString() ?? '').isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Agrega primero un correo al cliente.')));
      return;
    }
    final form = GlobalKey<FormState>();
    final password = TextEditingController();
    final confirm = TextEditingController();
    try {
      final value = await showDialog<String>(context: context, builder: (context) => AlertDialog(
        title: const Text('Definir contraseña del portal'),
        content: SizedBox(width: 420, child: Form(key: form, child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Cuenta para ${customer['email']}'),
          const SizedBox(height: 12),
          TextFormField(controller: password, obscureText: true, decoration: const InputDecoration(labelText: 'Nueva contraseña', helperText: 'Mínimo 6 caracteres'), validator: (v) => v == null || v.length < 6 ? 'Usa al menos 6 caracteres' : null),
          const SizedBox(height: 10),
          TextFormField(controller: confirm, obscureText: true, decoration: const InputDecoration(labelText: 'Confirmar contraseña'), validator: (v) => v != password.text ? 'Las contraseñas no coinciden' : null),
        ]))),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')), FilledButton(onPressed: () {
          if (form.currentState!.validate()) Navigator.pop(context, password.text);
        }, child: const Text('Guardar contraseña'))],
      ));
      if (value == null) return;
      await widget.api.postJson('/api/v1/customers/' + customer['id'].toString() + '/portal-access/password', {'password': value});
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Acceso al portal listo. Entrega la contraseña al cliente de forma segura.')));
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString().replaceFirst('Exception: ', ''))));
    } finally { password.dispose(); confirm.dispose(); }
  }

  Future<void> _editVehicle(Map<String, dynamic> vehicle) async {
    final form = GlobalKey<FormState>();
    final plate = TextEditingController(text: vehicle['plate']?.toString() ?? '');
    final make = TextEditingController(text: vehicle['make']?.toString() ?? '');
    final model = TextEditingController(text: vehicle['model']?.toString() ?? '');
    final year = TextEditingController(text: vehicle['year']?.toString() ?? '');
    final vin = TextEditingController(text: vehicle['vin']?.toString() ?? '');
    final engine = TextEditingController(text: vehicle['engine']?.toString() ?? '');
    final mileage = TextEditingController(text: vehicle['current_mileage_km']?.toString() ?? '');
    final notes = TextEditingController(text: vehicle['notes']?.toString() ?? '');
    int customerId = vehicle['customer_id'] as int;
    try {
      final data = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (context) => StatefulBuilder(builder: (context, updateDialog) => AlertDialog(
          title: const Text('Editar vehículo'),
          content: Form(key: form, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<int>(value: customerId, decoration: const InputDecoration(labelText: 'Cliente *'),
              items: _customers.map((item) => DropdownMenuItem<int>(value: item['id'] as int, child: Text(item['full_name'].toString()))).toList(),
              onChanged: (value) { if (value != null) updateDialog(() => customerId = value); }),
            const SizedBox(height: 10),
            TextFormField(controller: plate, textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(labelText: 'Patente *'), validator: (value) => value == null || value.trim().isEmpty ? 'Ingresa la patente' : null),
            const SizedBox(height: 10), TextFormField(controller: make, decoration: const InputDecoration(labelText: 'Marca *'), validator: (value) => value == null || value.trim().isEmpty ? 'Ingresa la marca' : null),
            const SizedBox(height: 10), TextFormField(controller: model, decoration: const InputDecoration(labelText: 'Modelo *'), validator: (value) => value == null || value.trim().isEmpty ? 'Ingresa el modelo' : null),
            const SizedBox(height: 10), TextFormField(controller: year, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Año'), validator: (value) => value == null || value.trim().isEmpty || int.tryParse(value.trim()) != null ? null : 'Ingresa un año válido'),
            const SizedBox(height: 10), TextFormField(controller: vin, decoration: const InputDecoration(labelText: 'VIN')),
            const SizedBox(height: 10), TextFormField(controller: engine, decoration: const InputDecoration(labelText: 'Motor')),
            const SizedBox(height: 10), TextFormField(controller: mileage, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Kilometraje'), validator: (value) => value == null || value.trim().isEmpty || int.tryParse(value.trim()) != null ? null : 'Ingresa un kilometraje válido'),
            const SizedBox(height: 10), TextFormField(controller: notes, maxLines: 3, decoration: const InputDecoration(labelText: 'Notas')),
          ]))),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
            FilledButton(onPressed: () {
              if (!form.currentState!.validate()) return;
              Navigator.pop(context, {'customer_id': customerId, 'plate': plate.text.trim().toUpperCase(), 'make': make.text.trim(), 'model': model.text.trim(), 'year': int.tryParse(year.text.trim()), 'vin': vin.text.trim().toUpperCase(), 'engine': engine.text.trim(), 'current_mileage_km': int.tryParse(mileage.text.trim()), 'notes': notes.text.trim()});
            }, child: const Text('Guardar cambios')),
          ],
        )),
      );
      if (data == null) return;
      await widget.api.patchJson('/api/v1/vehicles/' + vehicle['id'].toString(), data);
      await _refresh();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Vehículo actualizado')));
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString().replaceFirst('Exception: ', ''))));
    } finally {
      plate.dispose(); make.dispose(); model.dispose(); year.dispose(); vin.dispose(); engine.dispose(); mileage.dispose(); notes.dispose();
    }
  }

  Future<void> _deleteRecord(Map<String, dynamic> item, {required bool vehicle}) async {
    final type = vehicle ? 'vehículo' : 'cliente';
    final label = vehicle ? item['plate'].toString() : item['full_name'].toString();
    final confirmed = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: Text('Eliminar ' + type),
      content: Text('¿Eliminar ' + label + '? Esta acción no se puede deshacer. Si tiene historial asociado, Gudex impedirá la eliminación.'),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')), FilledButton.tonal(onPressed: () => Navigator.pop(context, true), child: const Text('Eliminar'))],
    ));
    if (confirmed != true) return;
    try {
      await widget.api.delete('/api/v1/' + (vehicle ? 'vehicles' : 'customers') + '/' + item['id'].toString());
      await _refresh();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text((vehicle ? 'Vehículo' : 'Cliente') + ' eliminado')));
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString().replaceFirst('Exception: ', ''))));
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
      builder: (context) => _WorkOrderDetails(api: widget.api, order: order, role: widget.role, onChanged: _refresh),
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
      trailing: widget.role != 'admin' ? null : PopupMenuButton<String>(
        tooltip: 'Acciones del cliente',
        onSelected: (value) {
          if (value == 'edit') _editCustomer(item);
          else if (value == 'password') _setCustomerPassword(item);
          else _deleteRecord(item, vehicle: false);
        },
        itemBuilder: (context) => const [
          PopupMenuItem(value: 'edit', child: ListTile(leading: Icon(Icons.edit_outlined), title: Text('Editar'))),
          PopupMenuItem(value: 'password', child: ListTile(leading: Icon(Icons.lock_reset_outlined), title: Text('Definir contraseña del portal'))),
          PopupMenuItem(value: 'delete', child: ListTile(leading: Icon(Icons.delete_outline), title: Text('Eliminar'))),
        ],
      ),
      onTap: widget.role == 'admin' ? () => _editCustomer(item) : null,
    ));
  }

  Widget _vehicleTile(Map<String, dynamic> item) {
    final owner = _customers.where((customer) => customer['id'] == item['customer_id']);
    final customerName = owner.isEmpty ? 'Cliente no disponible' : '${owner.first['full_name']}';
    return Card(child: ListTile(
      leading: const CircleAvatar(child: Icon(Icons.directions_car_outlined)),
      title: Text('${item['plate']} · ${item['make']} ${item['model']}'),
      subtitle: Text('$customerName${item['year'] == null ? '' : ' · ${item['year']}'}${item['current_mileage_km'] == null ? '' : ' · ${item['current_mileage_km']} km'}'),
      trailing: widget.role != 'admin' ? const Icon(Icons.chevron_right) : PopupMenuButton<String>(
        tooltip: 'Acciones del vehículo',
        onSelected: (value) {
          if (value == 'edit') _editVehicle(item);
          else if (value == 'delete') _deleteRecord(item, vehicle: true);
          else Navigator.push(context, MaterialPageRoute(builder: (_) => VehicleHistoryScreen(api: widget.api, vehicleId: item['id'] as int, portal: false)));
        },
        itemBuilder: (context) => const [
          PopupMenuItem(value: 'history', child: ListTile(leading: Icon(Icons.history), title: Text('Ver historial'))),
          PopupMenuItem(value: 'edit', child: ListTile(leading: Icon(Icons.edit_outlined), title: Text('Editar'))),
          PopupMenuItem(value: 'delete', child: ListTile(leading: Icon(Icons.delete_outline), title: Text('Eliminar'))),
        ],
      ),
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => VehicleHistoryScreen(api: widget.api, vehicleId: item['id'] as int, portal: false))),
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
      subtitle: Text('$customerLabel\nEstado: ${spanishStatus(item['status'] ?? 'received')}${item['technician_name'] == null ? '' : ' · ${item['technician_name']}'}${item['reported_symptoms'] == null ? '' : '\n${item['reported_symptoms']}'}'),
      isThreeLine: true,
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _openOrder(item),
    ));
  }
}

class _WorkOrderDetails extends StatefulWidget {
  const _WorkOrderDetails({required this.api, required this.order, required this.role, required this.onChanged});
  final ApiClient api;
  final Map<String, dynamic> order;
  final String role;
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
  bool _restoringDraft = true;
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
    _restoreDraft();
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

  int? get _orderId => int.tryParse('${widget.order['id']}');

  Future<void> _restoreDraft() async {
    final orderId = _orderId;
    final draft = orderId == null ? null : await WorkOrderDraftStore.load(orderId);
    if (!mounted) return;
    setState(() => _restoringDraft = false);
    if (draft == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final restore = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Borrador local encontrado'),
          content: const Text('Hay cambios de estado y diagnóstico guardados en este dispositivo. ¿Quieres recuperarlos?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Descartar')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Recuperar')),
          ],
        ),
      );
      if (!mounted) return;
      if (restore == true) {
        final status = '${draft['status'] ?? ''}';
        setState(() {
          if (_statuses.contains(status)) _status = status;
          _diagnosis.text = '${draft['diagnosis'] ?? ''}';
        });
      } else if (orderId != null) {
        await WorkOrderDraftStore.clear(orderId);
      }
    });
  }

  Future<void> _saveLocalDraft({bool showFeedback = true}) async {
    final orderId = _orderId;
    if (orderId == null) return;
    await WorkOrderDraftStore.save(orderId, status: _status, diagnosis: _diagnosis.text.trim());
    if (showFeedback && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Borrador guardado en este dispositivo')));
    }
  }

  Future<void> _printInspectionReport() async {
    try {
      await openGudexPdf(widget.api, '/api/v1/work-orders/${widget.order['id']}/inspection-report.pdf', 'Gudex-inspeccion-${widget.order['id']}.pdf');
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No se pudo abrir el informe: $error')));
    }
  }

  Future<void> _saveOrder() async {
    setState(() { _saving = true; _error = null; });
    try {
      await widget.api.patchJson('/api/v1/work-orders/${widget.order['id']}', {
        'status': _status,
        'diagnosis': _diagnosis.text.trim(),
      });
      final orderId = _orderId;
      if (orderId != null) await WorkOrderDraftStore.clear(orderId);
      if (!mounted) return;
      await widget.onChanged();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Orden actualizada')));
    } catch (error) {
      try {
        await _saveLocalDraft(showFeedback: false);
      } catch (_) {
        // El fallo de almacenamiento local no debe ocultar el error de la API.
      }
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
    final orderId = _orderId;
    final inspectionId = int.tryParse('${inspection['id']}');
    final savedDraft = orderId == null || inspectionId == null ? null : await WorkOrderDraftStore.loadInspection(orderId, inspectionId);
    final initial = savedDraft ?? inspection;
    final notes = TextEditingController(text: '${initial['notes'] ?? ''}');
    final measured = TextEditingController(text: '${initial['measured_value'] ?? ''}');
    String result = '${initial['result'] ?? 'not_inspected'}';
    try {
      final data = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (context) => StatefulBuilder(builder: (context, update) => AlertDialog(
          title: Text('${inspection['item']}'),
          content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (savedDraft != null) ...[
              const Text('Estás editando un borrador local pendiente de envío.', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 10),
            ],
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
      if (orderId != null && inspectionId != null) await WorkOrderDraftStore.clearInspection(orderId, inspectionId);
      if (!mounted) return;
      setState(() { _inspections = _loadInspections(); _report = _loadReport(); });
    } catch (error) {
      if (orderId != null && inspectionId != null) {
        try {
          await WorkOrderDraftStore.saveInspection(orderId, inspectionId, {
            'result': result,
            'measured_value': measured.text.trim(),
            'notes': notes.text.trim(),
          });
        } catch (_) {
          // Conserva el error de API aunque el dispositivo no pueda guardar el borrador.
        }
      }
      if (mounted) setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
    } finally {
      notes.dispose(); measured.dispose();
    }
  }

  Future<void> _editReception() async {
    final orderId = _orderId;
    final savedDraft = orderId == null ? null : await WorkOrderDraftStore.loadReception(orderId);
    Map<String, dynamic> current = savedDraft ?? <String, dynamic>{};
    try {
      final currentRaw = await widget.api.get('/api/v1/work-orders/${widget.order['id']}/reception');
      if (savedDraft == null && currentRaw is Map) current = Map<String, dynamic>.from(currentRaw);
    } catch (_) {
      if (savedDraft == null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sin conexión: puedes preparar y guardar un borrador de recepción local.')));
      }
    }
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
            if (savedDraft != null) ...[
              const Text('Estás editando un borrador local pendiente de envío.', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 10),
            ],
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
      if (orderId != null) await WorkOrderDraftStore.clearReception(orderId);
      if (!mounted) return;
      setState(() => _report = _loadReport());
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Recepción actualizada')));
    } catch (error) {
      if (orderId != null) {
        try {
          final draft = <String, dynamic>{
            'fuel_level_percent': fuel,
            'visible_damage': damage.text.trim(),
            'accessories': accessories.text.trim(),
            'customer_observations': observations.text.trim(),
            'terms_accepted': accepted,
            'accepted_by_name': acceptedBy.text.trim(),
          };
          await WorkOrderDraftStore.saveReception(orderId, draft);
        } catch (_) {
          // Conserva el error de API aunque el dispositivo no pueda guardar el borrador.
        }
      }
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

  Future<void> _assignTechnician() async {
    try {
      final raw = await widget.api.get('/api/v1/team/mechanics');
      final mechanics = raw is List ? raw.whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList() : <Map<String, dynamic>>[];
      if (mechanics.isEmpty) throw Exception('No hay mecánicos activos para asignar');
      int? selected;
      for (final mechanic in mechanics) {
        if ('${mechanic['full_name']}' == '${widget.order['technician_name'] ?? ''}') selected = mechanic['id'] as int?;
      }
      final decision = await showDialog<Map<String, dynamic>>(context: context, builder: (context) => AlertDialog(
        title: const Text('Asignar mecánico'),
        content: StatefulBuilder(builder: (context, update) => DropdownButtonFormField<int?>(
          value: selected,
          decoration: const InputDecoration(labelText: 'Responsable'),
          items: [const DropdownMenuItem<int?>(value: null, child: Text('Sin asignar')), ...mechanics.map((item) => DropdownMenuItem<int?>(value: item['id'] as int, child: Text('${item['full_name']}')))],
          onChanged: (value) => update(() => selected = value),
        )),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')), FilledButton(onPressed: () => Navigator.pop(context, {'technician_user_id': selected}), child: const Text('Guardar'))],
      ));
      if (decision == null) return;
      final updated = await widget.api.putJson('/api/v1/work-orders/${widget.order['id']}/assignment', decision);
      if (updated is Map) widget.order.addAll(Map<String, dynamic>.from(updated));
      await widget.onChanged();
      if (mounted) setState(() {});
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString().replaceFirst('Exception: ', ''))));
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
          if (widget.role == 'admin') ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(onPressed: _saving ? null : _assignTechnician, icon: const Icon(Icons.person_add_alt_1), label: Text(widget.order['technician_name'] == null ? 'Asignar mecánico' : 'Responsable: ${widget.order['technician_name']}')),
          ],
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
            items: _statuses.map((value) => DropdownMenuItem(value: value, child: Text(spanishStatus(value)))).toList(),
            onChanged: (value) { if (value != null) setState(() => _status = value); },
          ),
          const SizedBox(height: 12),
          TextField(controller: _diagnosis, maxLines: 4, decoration: const InputDecoration(labelText: 'Diagnóstico / pruebas pendientes', alignLabelWithHint: true)),
          const SizedBox(height: 12),
          if (_restoringDraft) const LinearProgressIndicator(),
          if (_restoringDraft) const SizedBox(height: 12),
          if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          FilledButton.icon(onPressed: _saving ? null : _saveOrder, icon: const Icon(Icons.save_outlined), label: Text(_saving ? 'Guardando…' : 'Guardar cambios')),
          const SizedBox(height: 8),
          OutlinedButton.icon(onPressed: _saving ? null : _saveLocalDraft, icon: const Icon(Icons.save_as_outlined), label: const Text('Guardar borrador local')),
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
          Row(children: [
            Expanded(child: Text('Resumen para el cliente', style: Theme.of(context).textTheme.titleLarge)),
            IconButton(tooltip: 'Imprimir / guardar informe PDF', onPressed: _printInspectionReport,
              icon: const Icon(Icons.picture_as_pdf_outlined)),
          ]),
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
                  subtitle: Text('${_currency(amount)} · ${spanishStatus(quote['status'] ?? 'draft')}${quote['notes'] == null ? '' : '\n${quote['notes']}'}'),
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
  final _productSearch = TextEditingController();
  List<Map<String, dynamic>> _products = [];
  List<Map<String, dynamic>> _customers = [];
  List<Map<String, dynamic>> _sales = [];
  final Map<int, double> _cart = {};
  final List<Map<String, dynamic>> _serviceItems = [];
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
    _productSearch.dispose();
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
      }) + _serviceItems.fold<int>(0, (total, item) => total + _money(item['line_total_clp']));

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

  Future<void> _addServiceLine() async {
    final description = TextEditingController();
    final quantity = TextEditingController(text: '1');
    final price = TextEditingController();
    try {
      final line = await showDialog<Map<String, dynamic>>(context: context, builder: (context) => AlertDialog(
        title: const Text('Agregar servicio o trabajo'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: description, autofocus: true, decoration: const InputDecoration(labelText: 'Descripción *')),
          const SizedBox(height: 10),
          TextField(controller: quantity, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Cantidad / horas')),
          const SizedBox(height: 10),
          TextField(controller: price, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Precio unitario (CLP)', prefixText: '\$')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          FilledButton(onPressed: () {
            final qty = double.tryParse(quantity.text.trim().replaceAll(',', '.'));
            final unitPrice = int.tryParse(price.text.trim().replaceAll('.', '').replaceAll(',', ''));
            if (description.text.trim().isEmpty || qty == null || qty <= 0 || unitPrice == null || unitPrice < 0) return;
            Navigator.pop(context, {'description': description.text.trim(), 'quantity': qty,
              'unit_price_clp': unitPrice, 'line_total_clp': (qty * unitPrice).round()});
          }, child: const Text('Agregar')),
        ],
      ));
      if (line != null && mounted) setState(() => _serviceItems.add(line));
    } finally {
      description.dispose(); quantity.dispose(); price.dispose();
    }
  }

  Future<void> _printSaleReceipt(Map<String, dynamic> sale) async {
    try {
      await openGudexPdf(widget.api, '/api/v1/sales/${sale['id']}/receipt.pdf', 'Gudex-comprobante-${sale['id']}.pdf');
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No se pudo abrir el comprobante: $error')));
    }
  }

  bool _hasPendingCheckout(Map<String, dynamic> sale) {
    final payments = sale['payments'];
    return payments is List && payments.any((payment) => payment is Map && payment['status'] == 'pending_external');
  }

  Future<void> _cancelCheckout(Map<String, dynamic> sale) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancelar cobro de Mercado Pago'),
        content: Text('La venta ${sale['receipt_code']} quedará disponible para cobrarse por otro medio. '
            'Si el cliente igual paga el enlace, ese pago quedará marcado para devolución.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Volver')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Cancelar cobro')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _saving = true);
    try {
      await widget.api.post('/api/v1/sales/${sale['id']}/mercado-pago/cancel');
      await _refresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Cobro cancelado. Ya puedes registrar el pago de ${sale['receipt_code']} por otro medio.')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No se pudo cancelar el cobro: ${error.toString().replaceFirst('Exception: ', '')}')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _checkout() async {
    if (_cart.isEmpty && _serviceItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Agrega al menos un producto o servicio a la venta.')));
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
        content: Text(method == 'mercado_pago_checkout'
            ? 'Se creará un checkout de Mercado Pago por ${_formatMoney(total)}. La venta se marcará pagada solo cuando el backend verifique la notificación.'
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
        'lines': [
          ..._cart.entries.map((entry) {
          final product = _products.firstWhere((item) => item['id'] == entry.key);
          return {
            'product_id': entry.key,
            'description': product['name'],
            'quantity': entry.value,
            'unit_price_clp': _money(product['price_clp']),
          };
          }),
          ..._serviceItems.map((item) => {
            'description': item['description'],
            'quantity': item['quantity'],
            'unit_price_clp': item['unit_price_clp'],
          }),
        ],
      });
      sale = Map<String, dynamic>.from(result as Map);
      setState(() {
        _cart.clear();
        _serviceItems.clear();
        _discountController.text = '0';
      });

      if (total > 0) {
        await widget.api.postJson('/api/v1/sales/${sale['id']}/payments', {
          'method': method,
          'amount_clp': total,
        });
        if (method == 'mercado_pago_checkout') {
          final checkout = await widget.api.post('/api/v1/sales/${sale['id']}/mercado-pago/checkout');
          final checkoutUrl = '${checkout['checkout_url'] ?? ''}';
          if (!checkoutUrl.startsWith('https://') || !await launchUrl(Uri.parse(checkoutUrl), mode: LaunchMode.platformDefault)) {
            throw Exception('Venta ${sale['receipt_code']} creada. No se pudo abrir el checkout de Mercado Pago.');
          }
        }
      }
      await _refresh();
      if (!mounted) return;
      final message = method == 'mercado_pago_checkout' && total > 0
          ? 'Checkout de Mercado Pago iniciado para la venta ${sale['receipt_code']}; espera la confirmación del pago.'
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
    return LayoutBuilder(builder: (context, constraints) {
      final desktop = constraints.maxWidth >= 920;
      return Column(children: [
        Padding(padding: const EdgeInsets.fromLTRB(18, 12, 18, 10), child: Row(children: [
          Container(width: 44, height: 44, decoration: BoxDecoration(color: Theme.of(context).colorScheme.primaryContainer, borderRadius: BorderRadius.circular(14)), child: Icon(Icons.point_of_sale_outlined, color: Theme.of(context).colorScheme.onPrimaryContainer)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Punto de venta', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
            Text('Productos, servicios y cobros', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ])),
          IconButton(tooltip: 'Actualizar datos', onPressed: _refresh, icon: const Icon(Icons.refresh)),
        ])),
        Expanded(child: desktop
            ? Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 12), child: Column(children: [
                Expanded(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Expanded(flex: 6, child: _catalogPanel(available, desktop: true)),
                  const SizedBox(width: 14),
                  Expanded(flex: 5, child: _checkoutPanel(desktop: true)),
                ])),
                const SizedBox(height: 10),
                SizedBox(height: 156, child: _salesPanel()),
              ]))
            : RefreshIndicator(onRefresh: _refresh, child: ListView(padding: const EdgeInsets.fromLTRB(12, 0, 12, 24), children: [
                _catalogPanel(available, desktop: false),
                const SizedBox(height: 10),
                _checkoutPanel(desktop: false),
                const SizedBox(height: 10),
                SizedBox(height: 320, child: _salesPanel()),
              ]))),
      ]);
    });
  }

  Widget _catalogPanel(List<Map<String, dynamic>> available, {required bool desktop}) {
    final query = _productSearch.text.trim().toLowerCase();
    final filtered = available.where((product) => query.isEmpty || '${product['name']} ${product['sku'] ?? ''} ${product['category'] ?? ''}'.toLowerCase().contains(query)).toList();
    return Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [Expanded(child: Text('Catálogo', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700))), Chip(label: Text('${filtered.length}'))]),
      const SizedBox(height: 10),
      TextField(controller: _productSearch, onChanged: (_) => setState(() {}), decoration: const InputDecoration(prefixIcon: Icon(Icons.search), labelText: 'Buscar por producto o código', isDense: true)),
      const SizedBox(height: 10),
      if (filtered.isEmpty)
        if (desktop)
          Expanded(child: Center(child: Text(available.isEmpty ? 'No hay productos disponibles.' : 'No hay resultados para esa búsqueda.')))
        else
          Padding(padding: const EdgeInsets.symmetric(vertical: 24), child: Center(child: Text(available.isEmpty ? 'No hay productos disponibles.' : 'No hay resultados para esa búsqueda.')))
      else if (desktop)
        Expanded(child: ListView.separated(itemCount: filtered.length, separatorBuilder: (_, __) => const Divider(height: 1), itemBuilder: (context, index) => _productTile(filtered[index])))
      else
        ...filtered.map(_productTile),
    ])));
  }

  Widget _checkoutPanel({required bool desktop}) => Card(child: Padding(padding: const EdgeInsets.all(18), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Row(children: [Expanded(child: Text('Venta actual', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700))), Text('${_cart.length + _serviceItems.length} líneas', style: Theme.of(context).textTheme.bodySmall)]),
    const SizedBox(height: 8),
    if (desktop) Expanded(child: ListView(padding: EdgeInsets.zero, children: [
      if (_cart.isEmpty && _serviceItems.isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 20), child: Text('Agrega productos o servicios para comenzar.')),
      ..._cart.entries.map(_cartTile),
      ..._serviceItems.asMap().entries.map((entry) => ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(entry.value['description'] as String),
        subtitle: Text('Servicio · ${entry.value['quantity']} × ${_formatMoney(_money(entry.value['unit_price_clp']))}'),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [Text(_formatMoney(_money(entry.value['line_total_clp']))), IconButton(tooltip: 'Quitar servicio', onPressed: () => setState(() => _serviceItems.removeAt(entry.key)), icon: const Icon(Icons.close))]),
      )),
      Align(alignment: Alignment.centerLeft, child: TextButton.icon(onPressed: _addServiceLine, icon: const Icon(Icons.build_outlined), label: const Text('Agregar servicio / trabajo'))),
    ])) else ...[
      if (_cart.isEmpty && _serviceItems.isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 20), child: Text('Agrega productos o servicios para comenzar.')),
      ..._cart.entries.map(_cartTile),
      ..._serviceItems.asMap().entries.map((entry) => ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(entry.value['description'] as String),
        subtitle: Text('Servicio · ${entry.value['quantity']} × ${_formatMoney(_money(entry.value['unit_price_clp']))}'),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [Text(_formatMoney(_money(entry.value['line_total_clp']))), IconButton(tooltip: 'Quitar servicio', onPressed: () => setState(() => _serviceItems.removeAt(entry.key)), icon: const Icon(Icons.close))]),
      )),
      Align(alignment: Alignment.centerLeft, child: TextButton.icon(onPressed: _addServiceLine, icon: const Icon(Icons.build_outlined), label: const Text('Agregar servicio / trabajo'))),
    ],
    const SizedBox(height: 8),
      DropdownButtonFormField<int?>(
        value: _customerId,
        decoration: const InputDecoration(labelText: 'Cliente (opcional)', isDense: true),
        items: [const DropdownMenuItem<int?>(value: null, child: Text('Venta sin cliente')), ..._customers.map((customer) => DropdownMenuItem<int?>(value: customer['id'] as int?, child: Text('${customer['full_name']}')))],
        onChanged: (value) => setState(() => _customerId = value),
      ),
      const SizedBox(height: 10),
      TextField(controller: _discountController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Descuento (CLP)', prefixText: '\$', isDense: true), onChanged: (_) => setState(() {})),
      const SizedBox(height: 10),
      DropdownButtonFormField<String>(
        value: _paymentMethod,
        decoration: const InputDecoration(labelText: 'Medio de pago', isDense: true),
        items: const [
          DropdownMenuItem(value: 'cash', child: Text('Efectivo')),
          DropdownMenuItem(value: 'card', child: Text('Tarjeta / Mercado Pago Point')),
          DropdownMenuItem(value: 'transfer', child: Text('Transferencia')),
          DropdownMenuItem(value: 'mercado_pago_checkout', child: Text('Mercado Pago Checkout Pro')),
        ],
        onChanged: (value) { if (value != null) setState(() => _paymentMethod = value); },
      ),
    const Divider(height: 22),
    _totalRow('Subtotal', _subtotal),
    _totalRow('Descuento', _discount.clamp(0, _subtotal).toInt()),
    _totalRow('Total', _total, emphasize: true),
    const SizedBox(height: 10),
    SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: _saving || (_cart.isEmpty && _serviceItems.isEmpty) ? null : _checkout,
      icon: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.lock_outline),
      label: Text(_saving ? 'Guardando…' : 'Cobrar ${_formatMoney(_total)}'))),
  ])));

  Widget _salesPanel() => Card(child: Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 8), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text('Ventas recientes', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
    const SizedBox(height: 4),
    Expanded(child: _sales.isEmpty ? const Center(child: Text('Todavía no hay ventas.')) : ListView.separated(
      itemCount: _sales.length.clamp(0, 10).toInt(), separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) { final sale = _sales[index]; return ListTile(
        dense: true, contentPadding: EdgeInsets.zero, leading: const Icon(Icons.receipt_long_outlined, color: GudexColors.primary),
        title: Text('${sale['receipt_code']} · ${_formatMoney(_money(sale['total_clp']))}'),
        subtitle: Text('Estado: ${spanishStatus(sale['status'])}${_hasPendingCheckout(sale) ? ' · Cobro Mercado Pago pendiente' : ''} · ${sale['created_at'] ?? ''}'),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          if (_hasPendingCheckout(sale))
            IconButton(tooltip: 'Cancelar cobro de Mercado Pago', icon: const Icon(Icons.cancel_outlined), color: Theme.of(context).colorScheme.error,
                onPressed: _saving ? null : () => _cancelCheckout(sale)),
          IconButton(tooltip: 'Abrir comprobante PDF', icon: const Icon(Icons.picture_as_pdf_outlined), onPressed: () => _printSaleReceipt(sale)),
        ]),
      ); },
    )),
  ])));

  Widget _productTile(Map<String, dynamic> product) {
    final id = product['id'] as int?;
    final stock = _number(product['stock_quantity']);
    final quantity = id == null ? 0 : (_cart[id] ?? 0);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(backgroundColor: Theme.of(context).colorScheme.secondaryContainer, child: Icon(Icons.inventory_2_outlined, color: Theme.of(context).colorScheme.onSecondaryContainer)),
      title: Text('${product['name'] ?? 'Producto'}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Padding(padding: const EdgeInsets.only(top: 4), child: Text('Stock ${stock.toStringAsFixed(stock % 1 == 0 ? 0 : 2)} ${product['unit'] ?? ''}  ·  ${_formatMoney(_money(product['price_clp']))}')),
      trailing: stock <= 0
          ? const Chip(label: Text('Sin stock'))
          : FilledButton.tonalIcon(onPressed: () => _changeQuantity(product, 1), icon: Icon(quantity == 0 ? Icons.add_shopping_cart : Icons.add), label: Text(quantity == 0 ? 'Agregar' : quantity.toStringAsFixed(quantity % 1 == 0 ? 0 : 2))),
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
    return spanishStatus(value);
  }

  @override
  Widget build(BuildContext context) {
    final entries = data.entries.where((entry) =>
        !{'id', 'customer_id', 'vehicle_id', 'work_order_id', 'storage_path', 'google_event_id'}.contains(entry.key) &&
        _displayValue(entry.key, entry.value).isNotEmpty).take(4).toList();
    final title = (data['code'] ?? data['plate'] ?? data['full_name'] ?? data['name'] ?? data['description'] ?? data['service_type'] ?? 'Registro').toString();
    final status = data['status']?.toString();
    final statusStyle = _statusStyle(context, status);
    return Card(margin: const EdgeInsets.symmetric(vertical: 6), child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.onSurface))),
          if (statusStyle != null) ...[
            const SizedBox(width: 8),
            Flexible(child: Container(padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              decoration: BoxDecoration(color: statusStyle.$1, borderRadius: BorderRadius.circular(30)),
              child: Text(spanishStatus(status), maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(color: statusStyle.$2, fontSize: 10, fontWeight: FontWeight.w700)))),
          ],
        ]),
        for (final entry in entries)
          Padding(padding: const EdgeInsets.only(top: 6), child: Text('${spanishField(entry.key)}: ${_displayValue(entry.key, entry.value)}',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant))),
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

  (Color, Color)? _statusStyle(BuildContext context, String? status) {
    if (status == null) return null;
    if ({'failed', 'cancelled', 'rejected', 'quote_rejected'}.contains(status)) {
      return (Theme.of(context).colorScheme.errorContainer, Theme.of(context).colorScheme.onErrorContainer);
    }
    if ({'ready', 'delivered', 'approved', 'paid', 'normal', 'completed'}.contains(status)) {
      return (const Color(0xFFE3F3E9), GudexColors.success);
    }
    if ({'in_progress', 'inspecting', 'awaiting_approval', 'requested', 'sent', 'pending'}.contains(status)) {
      return (const Color(0xFFFFF2D8), const Color(0xFF835A00));
    }
    return (const Color(0xFFE5F2F4), GudexColors.primary);
  }
}












