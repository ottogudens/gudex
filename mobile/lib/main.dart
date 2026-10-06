import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'package:printing/printing.dart';
import 'services/api_client.dart';
import 'core/constants.dart';
import 'core/theme.dart';
import 'providers/auth_provider.dart';
import 'screens/auth/customer_access_page.dart';
import 'screens/auth/login_page.dart';
import 'screens/customer_appointments_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/inventory_screen.dart';
import 'screens/services_screen.dart';
import 'screens/users_screen.dart';
import 'screens/agenda_screen.dart';
import 'screens/scanner_screen.dart';
import 'screens/pos_screen.dart';
import 'screens/workshop_screen.dart';
import 'screens/assistant_screen.dart';
import 'screens/integration_settings_screen.dart';
import 'screens/module_list_screen.dart';

part 'quotes_screen.dart';
part 'social_screen.dart';

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





// _Module replaced by AppModule from screens/module_list_screen.dart

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

  List<AppModule> get _modules {
    if (widget.role == 'customer') {
      return const [
        AppModule(title: 'Mis vehículos', icon: Icons.directions_car_outlined, path: '/api/v1/portal/profile', keyName: 'vehicles'),
        AppModule(title: 'Trabajos anteriores', icon: Icons.assignment_outlined, path: '/api/v1/portal/work-orders'),
        AppModule(title: 'Cotizaciones', icon: Icons.request_quote_outlined, path: '/api/v1/portal/quotes'),
        AppModule(title: 'Mis citas', icon: Icons.calendar_month_outlined, path: '/api/v1/portal/appointments'),
      ];
    }
    if (widget.role == 'mechanic') {
      return const [
        AppModule(title: 'Mis trabajos', icon: Icons.assignment_outlined, path: '/api/v1/work-orders/mine'),
        AppModule(title: 'Órdenes de trabajo', icon: Icons.assignment_outlined, path: '/api/v1/work-orders'),
        AppModule(title: 'Inventario', icon: Icons.inventory_2_outlined, path: '/api/v1/products'),
        AppModule(title: 'Agenda', icon: Icons.calendar_month_outlined, path: '/api/v1/appointments'),
        AppModule(title: 'Scanner LAUNCH', icon: Icons.calendar_month_outlined, path: '/api/v1/scanner-reports'),
      ];
    }
    return const [
      AppModule(title: 'Panel principal', icon: Icons.space_dashboard_outlined, path: '/api/v1/dashboard'),
      AppModule(title: 'Órdenes de trabajo', icon: Icons.assignment_outlined, path: '/api/v1/work-orders'),
      AppModule(title: 'Clientes', icon: Icons.directions_car_outlined, path: '/api/v1/customers'),
      AppModule(title: 'Inventario', icon: Icons.inventory_2_outlined, path: '/api/v1/products'),
      AppModule(title: 'Agenda', icon: Icons.calendar_month_outlined, path: '/api/v1/appointments'),
      AppModule(title: 'Scanner LAUNCH', icon: Icons.calendar_month_outlined, path: '/api/v1/scanner-reports'),
      AppModule(title: 'POS', icon: Icons.point_of_sale_outlined, path: '/api/v1/sales'),
      AppModule(title: 'Usuarios', icon: Icons.people_outlined, path: '/api/v1/users'),
      AppModule(title: 'Cotizaciones', icon: Icons.request_quote_outlined, path: '/api/v1/quotes'),
      AppModule(title: 'Servicios', icon: Icons.build_circle_outlined, path: '/api/v1/services'),
      AppModule(title: 'Contenido y redes', icon: Icons.campaign_outlined, path: '/api/v1/social/posts'),
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
                    ? PosScreen(api: api)
                    : modules[selected].path == '/api/v1/services'
                        ? ServicesScreen(api: api)
                    : modules[selected].path == '/api/v1/social/posts'
                        ? _SocialScreen(api: api)
                    : modules[selected].path == '/api/v1/quotes'
                        ? _QuotesScreen(api: api)
                    : modules[selected].path == '/api/v1/dashboard'
                        ? DashboardScreen(api: api, onOpenModule: (index) => setState(() => _selected = index))
                    : modules[selected].path == '/api/v1/users'
                        ? UsersScreen(api: api)
                    : modules[selected].path == '/api/v1/products'
                        ? InventoryScreen(api: api, canManage: widget.role == 'admin', onCreateSocialPost: (product) => Navigator.push(context, MaterialPageRoute(builder: (_) => _SocialEditor(api: api, product: product))))
                    : modules[selected].path == '/api/v1/appointments'
                        ? AgendaScreen(api: api, role: widget.role)
                    : modules[selected].path == '/api/v1/portal/appointments'
                        ? CustomerAppointmentsScreen(api: api)
                    : modules[selected].path == '/api/v1/scanner-reports'
                        ? ScannerScreen(api: api, role: widget.role)
                    : {'/api/v1/work-orders', '/api/v1/work-orders/mine', '/api/v1/customers'}.contains(modules[selected].path)
                        ? WorkshopScreen(api: api, modulePath: modules[selected].path, role: widget.role)
                        : ModuleList(api: api, module: modules[selected], role: widget.role),
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
          MaterialPageRoute(builder: (_) => AssistantScreen(api: api, role: widget.role)))),
        if (widget.role == 'admin') IconButton(tooltip: 'Integraciones', icon: const Icon(Icons.link), onPressed: () => Navigator.push(context,
          MaterialPageRoute(builder: (_) => IntegrationSettingsScreen(api: api)))),
        IconButton(onPressed: () => ref.read(authProvider.notifier).signOut(), tooltip: 'Cerrar sesión', icon: const Icon(Icons.logout)),
      ]),
      body: useNavigationRail ? Row(children: [
        NavigationRail(
          extended: true,
          scrollable: true,
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
    if (title == 'Servicios') return Icons.build_circle_outlined;
    if (title == 'Contenido y redes') return Icons.campaign_outlined;
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
    if (title == 'Contenido y redes') return 'Redes';
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

