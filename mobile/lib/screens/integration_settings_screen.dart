import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/api_client.dart';
import '../core/constants.dart';

class IntegrationSettingsScreen extends StatefulWidget {
  const IntegrationSettingsScreen({required this.api, super.key});
  final ApiClient api;

  @override
  State<IntegrationSettingsScreen> createState() => _IntegrationSettingsScreenState();
}

class _IntegrationSettingsScreenState extends State<IntegrationSettingsScreen> {
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
          initialValue: models.contains(selected) ? selected : null,
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
    final social = Map<String, dynamic>.from(_status?['social'] as Map? ?? {});
    final instagram = Map<String, dynamic>.from(social['instagram'] as Map? ?? {});
    final facebook = Map<String, dynamic>.from(social['facebook'] as Map? ?? {});
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
        Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Redes sociales', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(social['credentials_present'] == true
              ? (social['connected'] == true ? 'Meta configurado y con token disponible.' : 'Meta configurado; falta autorizar una cuenta.')
              : 'Configura Meta OAuth en Railway para conectar Instagram y Facebook.'),
          const SizedBox(height: 12),
          _socialConnectionTile(Icons.camera_alt_outlined, 'Instagram', instagram['configured'] == true, social['connected'] == true),
          _socialConnectionTile(Icons.facebook, 'Facebook', facebook['configured'] == true, social['connected'] == true),
          const SizedBox(height: 8),
          const Text('Variables requeridas: META_APP_ID, META_APP_SECRET, META_REDIRECT_URI, META_ACCESS_TOKEN y el ID de cada cuenta. Las publicaciones siguen requiriendo aprobación humana.'),
        ]))),
        const Card(child: Padding(padding: EdgeInsets.all(14), child: Text('La conexión OAuth y las claves del proveedor se administran en Railway. Esta pantalla muestra el estado y permite iniciar flujos autorizados.'))),
      ]));
  }

  Widget _socialConnectionTile(IconData icon, String name, bool accountConfigured, bool tokenAvailable) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: Icon(icon),
    title: Text(name),
    subtitle: Text(accountConfigured && tokenAvailable ? 'Cuenta lista para conectar' : accountConfigured ? 'Cuenta identificada; falta autorización' : 'ID de cuenta no configurado'),
    trailing: Icon(accountConfigured && tokenAvailable ? Icons.check_circle : Icons.warning_amber_outlined),
  );
}
