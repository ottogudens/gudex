import 'dart:async';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
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
  Map<String, dynamic>? _baileysSession;

  @override
  void initState() { super.initState(); _refresh(); }

  Future<void> _refresh() async {
    try {
      // A distinct URL prevents an intermediary cache from keeping an older
      // connector state after an administrator changes Railway variables.
      final nonce = DateTime.now().microsecondsSinceEpoch;
      final data = Map<String, dynamic>.from(await widget.api.get('/api/v1/integrations/status?refresh=$nonce') as Map);
      if (mounted) setState(() => _status = data);
    }
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

  Future<void> _configureGoogle() async {
    try {
      final current = Map<String, dynamic>.from(
        await widget.api.get('/api/v1/integrations/google/config') as Map);
      if (!mounted) return;
      final clientId = TextEditingController(text: '${current['client_id'] ?? ''}');
      final secret = TextEditingController();
      final redirect = TextEditingController(text: '${current['redirect_uri'] ?? ''}');
      final folder = TextEditingController(text: '${current['drive_folder_id'] ?? ''}');
      final calendar = TextEditingController(text: '${current['calendar_id'] ?? 'primary'}');
      final query = TextEditingController(text: '${current['gmail_query'] ?? ''}');
      final form = GlobalKey<FormState>();
      try {
        final data = await showDialog<Map<String, dynamic>>(context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Configurar Google'),
            content: SizedBox(width: 500, child: Form(key: form,
              child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Crea un cliente OAuth de tipo Aplicación web en Google Cloud. '
                  'Habilita Gmail, Drive y Calendar y agrega la URL de retorno indicada abajo.'),
                const SizedBox(height: 12),
                TextFormField(controller: clientId,
                  decoration: const InputDecoration(labelText: 'Client ID'),
                  validator: (value) => value == null || value.trim().isEmpty ? 'Obligatorio' : null),
                TextFormField(controller: secret, obscureText: true,
                  decoration: InputDecoration(labelText: 'Client Secret',
                    helperText: current['configured_in_app'] == true
                      ? 'Ya hay uno guardado. Deja vacío para conservarlo.'
                      : 'Obligatorio para guardar la configuración en Gudex'),
                  validator: (value) => current['configured_in_app'] != true &&
                    (value == null || value.trim().isEmpty) ? 'Obligatorio' : null),
                TextFormField(controller: redirect,
                  decoration: const InputDecoration(labelText: 'URL de retorno autorizada',
                    helperText: 'Regístrala exactamente igual en Google Cloud'),
                  validator: (value) => value == null || value.trim().isEmpty ? 'Obligatoria' : null),
                TextFormField(controller: folder,
                  decoration: const InputDecoration(labelText: 'ID carpeta de Drive (opcional)')),
                TextFormField(controller: calendar,
                  decoration: const InputDecoration(labelText: 'ID calendario', hintText: 'primary'),
                  validator: (value) => value == null || value.trim().isEmpty ? 'Obligatorio' : null),
                TextFormField(controller: query,
                  decoration: const InputDecoration(labelText: 'Búsqueda de PDF en Gmail')),
                const SizedBox(height: 8),
                const Text('El secreto se guarda cifrado en el servidor y no volverá a mostrarse.'),
              ])))),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancelar')),
              FilledButton(onPressed: () {
                if (!form.currentState!.validate()) return;
                Navigator.pop(dialogContext, {
                  'client_id': clientId.text.trim(),
                  'client_secret': secret.text.trim().isEmpty ? null : secret.text.trim(),
                  'redirect_uri': redirect.text.trim(),
                  'drive_folder_id': folder.text.trim().isEmpty ? null : folder.text.trim(),
                  'calendar_id': calendar.text.trim(),
                  'gmail_query': query.text.trim(),
                });
              }, child: const Text('Guardar')),
            ],
          ));
        if (data == null) return;
        setState(() => _busy = true);
        await widget.api.putJson('/api/v1/integrations/google/config', data);
        await _refresh();
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Configuración de Google guardada. Ya puedes conectar la cuenta.')));
      } finally {
        clientId.dispose(); secret.dispose(); redirect.dispose();
        folder.dispose(); calendar.dispose(); query.dispose();
      }
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(error.toString().replaceFirst('Exception: ', ''))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _configureMeta() async {
    try {
      final current = Map<String, dynamic>.from(
        await widget.api.get('/api/v1/integrations/meta/config') as Map);
      if (!mounted) return;
      final appId = TextEditingController(text: '${current['app_id'] ?? ''}');
      final secret = TextEditingController();
      final redirect = TextEditingController(text: '${current['redirect_uri'] ?? ''}');
      final form = GlobalKey<FormState>();
      try {
        final data = await showDialog<Map<String, dynamic>>(context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Configurar Facebook e Instagram'),
            content: SizedBox(width: 500, child: Form(key: form,
              child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Crea una app empresarial en Meta for Developers, habilita Facebook Login '
                  'y agrega la URL de retorno como URI OAuth válida. Para Instagram se requiere una '
                  'cuenta profesional vinculada a una página de Facebook.'),
                const SizedBox(height: 12),
                TextFormField(controller: appId,
                  decoration: const InputDecoration(labelText: 'Meta App ID'),
                  validator: (value) => value == null || value.trim().isEmpty ? 'Obligatorio' : null),
                TextFormField(controller: secret, obscureText: true,
                  decoration: InputDecoration(labelText: 'Meta App Secret',
                    helperText: current['configured_in_app'] == true
                      ? 'Deja vacío para conservar el secreto guardado.' : 'Obligatorio la primera vez'),
                  validator: (value) => current['configured_in_app'] != true &&
                    (value == null || value.trim().isEmpty) ? 'Obligatorio' : null),
                TextFormField(controller: redirect,
                  decoration: const InputDecoration(labelText: 'URL de retorno autorizada',
                    helperText: 'Regístrala exactamente igual en Meta for Developers'),
                  validator: (value) => value == null || value.trim().isEmpty ? 'Obligatoria' : null),
                const SizedBox(height: 8),
                const Text('El secreto se cifra en el servidor y nunca se vuelve a mostrar.'),
              ])))),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancelar')),
              FilledButton(onPressed: () {
                if (!form.currentState!.validate()) return;
                Navigator.pop(dialogContext, {
                  'app_id': appId.text.trim(),
                  'app_secret': secret.text.trim().isEmpty ? null : secret.text.trim(),
                  'redirect_uri': redirect.text.trim(),
                });
              }, child: const Text('Guardar')),
            ],
          ));
        if (data == null) return;
        setState(() => _busy = true);
        await widget.api.putJson('/api/v1/integrations/meta/config', data);
        await _refresh();
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Configuración guardada. Ya puedes autorizar Meta.')));
      } finally {
        appId.dispose(); secret.dispose(); redirect.dispose();
      }
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(error.toString().replaceFirst('Exception: ', ''))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _connectMeta() async {
    setState(() => _busy = true);
    try {
      final data = Map<String, dynamic>.from(
        await widget.api.post('/api/v1/integrations/meta/authorize') as Map);
      final url = Uri.parse(data['authorization_url'] as String);
      if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
        throw Exception('No se pudo abrir la autorización de Meta');
      }
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Autoriza en Meta, vuelve a Gudex y pulsa Actualizar.')));
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(error.toString().replaceFirst('Exception: ', ''))));
    } finally { if (mounted) setState(() => _busy = false); }
  }

  Future<void> _selectMetaPage() async {
    setState(() => _busy = true);
    try {
      final pages = List<Map<String, dynamic>>.from(
        (await widget.api.get('/api/v1/integrations/meta/pages') as List)
          .map((page) => Map<String, dynamic>.from(page as Map)));
      if (!mounted) return;
      if (pages.isEmpty) throw Exception('No hay páginas disponibles. Revisa los permisos de Meta y tu acceso a la página.');
      final pageId = await showDialog<String>(context: context,
        builder: (dialogContext) => SimpleDialog(
          title: const Text('Seleccionar página de Facebook'),
          children: pages.map((page) => SimpleDialogOption(
            onPressed: () => Navigator.pop(dialogContext, '${page['id']}'),
            child: ListTile(
              title: Text('${page['name'] ?? 'Página'}'),
              subtitle: Text(page['instagram_username'] == null
                ? 'Instagram no vinculado' : 'Instagram: @${page['instagram_username']}'),
            ),
          )).toList(),
        ));
      if (pageId == null) return;
      await widget.api.postJson('/api/v1/integrations/meta/select-page', {'page_id': pageId});
      await _refresh();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Página de Facebook seleccionada.')));
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(error.toString().replaceFirst('Exception: ', ''))));
    } finally { if (mounted) setState(() => _busy = false); }
  }

  Future<void> _disconnectMeta() async {
    final confirmed = await showDialog<bool>(context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Desconectar Meta'),
        content: const Text('Se eliminarán los tokens guardados de Facebook e Instagram. La configuración de la app permanecerá.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Desconectar')),
        ],
      ));
    if (confirmed != true) return;
    try {
      await widget.api.delete('/api/v1/integrations/meta');
      await _refresh();
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(error.toString().replaceFirst('Exception: ', ''))));
    }
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

  Future<Map<String, dynamic>> _baileysStatus() async {
    final result = await widget.api.get('/api/v1/integrations/whatsapp/baileys/status');
    final session = Map<String, dynamic>.from(result as Map);
    if (mounted) setState(() => _baileysSession = session);
    return session;
  }

  Future<void> _startBaileysPairing() async {
    setState(() => _busy = true);
    try {
      await widget.api.post('/api/v1/integrations/whatsapp/baileys/connect');
      if (!mounted) return;
      await showDialog<void>(context: context, builder: (dialogContext) => _BaileysPairingDialog(
        loadStatus: _baileysStatus,
        restartPairing: _restartBaileysPairing,
      ));
      await _refresh();
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString().replaceFirst('Exception: ', ''))));
    } finally { if (mounted) setState(() => _busy = false); }
  }

  Future<void> _restartBaileysPairing() async {
    final session = Map<String, dynamic>.from(await widget.api.post('/api/v1/integrations/whatsapp/baileys/reset') as Map);
    if (mounted) setState(() => _baileysSession = session);
  }

  Future<void> _sendBaileysTest() async {
    final phone = TextEditingController();
    final message = TextEditingController(text: 'Prueba de conexión Gudex.');
    final payload = await showDialog<Map<String, String>>(context: context, builder: (context) => AlertDialog(
      title: const Text('Enviar mensaje de prueba'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('Solo se permiten números definidos en BAILEYS_TEST_RECIPIENTS.'),
        TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Número internacional')),
        TextField(controller: message, maxLength: 1000, maxLines: 3, decoration: const InputDecoration(labelText: 'Mensaje')),
      ]),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.pop(context, {'phone': phone.text, 'message': message.text}), child: const Text('Enviar prueba'))],
    ));
    if (payload == null) return;
    try {
      await widget.api.postJson('/api/v1/integrations/whatsapp/baileys/test-message', payload);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Mensaje de prueba aceptado por Baileys.')));
    } catch (error) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString().replaceFirst('Exception: ', '')))); }
  }

  Future<void> _configureWhatsAppBusiness(Map<String, dynamic> configuration) async {
    setState(() => _busy = true);
    try {
      final saved = await showDialog<bool>(
        context: context,
        builder: (_) => _WhatsAppBusinessConfigDialog(api: widget.api, initial: configuration),
      );
      if (saved == true) {
        await _refresh();
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Configuración de WhatsApp Business guardada de forma segura.')),
        );
      }
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
    final whatsapp = Map<String, dynamic>.from(_status?['whatsapp'] as Map? ?? {});
    final business = Map<String, dynamic>.from(whatsapp['business'] as Map? ?? {});
    final baileys = Map<String, dynamic>.from(whatsapp['baileys_test'] as Map? ?? {});
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
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            OutlinedButton.icon(onPressed: _busy ? null : _configureGoogle,
              icon: const Icon(Icons.settings_outlined), label: const Text('Configurar Google')),
            FilledButton.icon(onPressed: _busy || google['credentials_present'] != true ? null : _connect,
              icon: const Icon(Icons.login), label: const Text('Conectar o renovar Google')),
          ]),
          if (google['credentials_present'] != true)
            const Text('Ingresa las credenciales OAuth para habilitar la conexión.'),
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
              ? (social['connected'] == true ? 'Página de Facebook conectada.'
                : social['authorized'] == true ? 'Cuenta autorizada; selecciona la página de Facebook.'
                : 'App de Meta configurada; falta autorizar la cuenta.')
              : 'Configura Meta desde aquí para conectar Facebook e Instagram.'),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            OutlinedButton.icon(onPressed: _busy ? null : _configureMeta,
              icon: const Icon(Icons.settings_outlined), label: const Text('Configurar Meta')),
            FilledButton.icon(onPressed: _busy || social['credentials_present'] != true ? null : _connectMeta,
              icon: const Icon(Icons.login), label: const Text('Autorizar Facebook e Instagram')),
            if (social['authorized'] == true)
              OutlinedButton(onPressed: _busy ? null : _selectMetaPage,
                child: const Text('Seleccionar página')),
            if (social['authorized'] == true)
              TextButton(onPressed: _busy ? null : _disconnectMeta,
                child: const Text('Desconectar')),
          ]),
          const SizedBox(height: 8),
          _socialConnectionTile(Icons.camera_alt_outlined, 'Instagram', instagram['configured'] == true, social['connected'] == true),
          _socialConnectionTile(Icons.facebook, 'Facebook', facebook['configured'] == true, social['connected'] == true),
          if (facebook['page_name'] != null) Text('Página: ${facebook['page_name']}'),
          if (instagram['username'] != null) Text('Instagram: @${instagram['username']}'),
          const SizedBox(height: 8),
          const Text('Instagram requiere una cuenta profesional vinculada a la página seleccionada. Las publicaciones siguen requiriendo aprobación humana.'),
        ]))),
        Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.verified_user_outlined),
            const SizedBox(width: 10),
            Expanded(child: Text('WhatsApp Business Platform (Meta)', style: Theme.of(context).textTheme.titleLarge)),
            Icon(business['configured'] == true ? Icons.check_circle : Icons.warning_amber_outlined,
                color: business['configured'] == true ? Colors.green : Theme.of(context).colorScheme.onSurfaceVariant),
          ]),
          const SizedBox(height: 6),
          Text(business['configured'] == true
              ? 'Datos guardados. Número: ${business['phone_number_id']}'
              : 'Agrega las credenciales de Meta para preparar el canal oficial.'),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _busy ? null : () => _configureWhatsAppBusiness(business),
            icon: const Icon(Icons.settings_outlined),
            label: Text(business['configured'] == true ? 'Editar configuración' : 'Configurar WhatsApp Business'),
          ),
          const SizedBox(height: 10),
          const Text('Los secretos se cifran en el servidor y nunca se vuelven a mostrar. Esta pantalla guarda la configuración; el envío y la recepción de conversaciones requieren completar la integración del webhook y la bandeja de atención.'),
        ]))),
        Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('WhatsApp: puente Baileys de pruebas', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          const Text('Canal no oficial y limitado a pruebas. Para atención real de clientes, automatizaciones y campañas debe utilizarse WhatsApp Business Platform.'),
          const SizedBox(height: 10),
          Text(baileys['configured'] == true
              ? (baileys['enabled'] == true ? 'Servicio de pruebas configurado.' : 'Servicio configurado, pero deshabilitado por seguridad.')
              : 'No se pudo confirmar el estado del bridge. Puedes iniciar el emparejamiento; el backend lo validará de forma segura.'),
          if (_baileysSession != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text('Sesión: ${_baileysSession!['status'] ?? 'sin estado'}')),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            // The endpoint is the source of truth and enforces test mode and
            // administrator permissions. Do not lock the only recovery action
            // behind a status card that may be stale after a config redeploy.
            FilledButton.icon(onPressed: _busy ? null : _startBaileysPairing, icon: const Icon(Icons.qr_code_2), label: const Text('Emparejar teléfono de prueba')),
            OutlinedButton(onPressed: _busy || _baileysSession?['connected'] != true ? null : _sendBaileysTest, child: const Text('Enviar mensaje de prueba')),
            // Keep the status refresh available even if the initial integration
            // status is stale. The bridge endpoint returns the authoritative
            // result (or a clear configuration error) to the administrator.
            TextButton(onPressed: _busy ? null : () async { try { await _baileysStatus(); } catch (error) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString()))); } }, child: const Text('Actualizar sesión')),
          ]),
        ]))),
        const Card(child: Padding(padding: EdgeInsets.all(14), child: Text('Las credenciales de Google y Meta se ingresan aquí y se guardan cifradas en el servidor. La clave maestra de cifrado permanece protegida en Railway.'))),
      ]));
  }

  Widget _socialConnectionTile(IconData icon, String name, bool accountConfigured, bool tokenAvailable) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: Icon(icon),
    title: Text(name),
    subtitle: Text(accountConfigured && tokenAvailable ? 'Conectada' : accountConfigured ? 'Cuenta identificada; falta autorización' : 'Cuenta no vinculada'),
    trailing: Icon(accountConfigured && tokenAvailable ? Icons.check_circle : Icons.warning_amber_outlined),
  );
}

class _BaileysPairingDialog extends StatefulWidget {
  const _BaileysPairingDialog({required this.loadStatus, required this.restartPairing});
  final Future<Map<String, dynamic>> Function() loadStatus;
  final Future<void> Function() restartPairing;

  @override
  State<_BaileysPairingDialog> createState() => _BaileysPairingDialogState();
}

class _BaileysPairingDialogState extends State<_BaileysPairingDialog> {
  Timer? _timer;
  Map<String, dynamic>? _session;
  String? _error;
  bool _restarting = false;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 3), (_) => _load());
  }

  Future<void> _load() async {
    try {
      final session = await widget.loadStatus();
      if (mounted) setState(() { _session = session; _error = null; });
    } catch (_) { if (mounted) setState(() => _error = 'No se pudo actualizar el estado de emparejamiento.'); }
  }

  Future<void> _restart() async {
    if (_restarting) return;
    setState(() { _restarting = true; _error = null; });
    try {
      await widget.restartPairing();
      await _load();
    } catch (_) {
      if (mounted) setState(() => _error = 'No se pudo reiniciar la sesión de pruebas.');
    } finally {
      if (mounted) setState(() => _restarting = false);
    }
  }

  @override
  void dispose() { _timer?.cancel(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final qr = _session?['qr']?.toString();
    final connected = _session?['connected'] == true;
    final status = _session?['status']?.toString() ?? 'connecting';
    final needsRestart = status == 'logged_out';
    final message = connected
        ? 'Teléfono conectado para pruebas.'
        : (qr != null && qr.isNotEmpty
            ? 'En WhatsApp, abre Dispositivos vinculados y escanea este código.'
            : (needsRestart
                ? 'La sesión anterior dejó de ser válida. Reiníciala para generar un código QR nuevo.'
                : (status == 'reconnecting'
                    ? 'WhatsApp confirmó el código. Completando la vinculación…'
                    : (status == 'disconnected'
                        ? 'La conexión se interrumpió. Actualiza la sesión o vuelve a generar el código QR.'
                        : 'Generando un código QR seguro…'))));
    return AlertDialog(
      title: const Text('Emparejar WhatsApp de prueba'),
      content: SizedBox(width: 330, child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (qr != null && qr.isNotEmpty) QrImageView(data: qr, size: 240, errorCorrectionLevel: QrErrorCorrectLevel.M),
        if (connected) const Icon(Icons.check_circle, color: Colors.green, size: 64),
        const SizedBox(height: 12),
        Text(message, textAlign: TextAlign.center),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
      ])),
      actions: [
        if (needsRestart) FilledButton.icon(
          onPressed: _restarting ? null : _restart,
          icon: _restarting ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.restart_alt),
          label: const Text('Reiniciar emparejamiento'),
        ),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar')),
      ],
    );
  }
}

class _WhatsAppBusinessConfigDialog extends StatefulWidget {
  const _WhatsAppBusinessConfigDialog({required this.api, required this.initial});
  final ApiClient api;
  final Map<String, dynamic> initial;

  @override
  State<_WhatsAppBusinessConfigDialog> createState() => _WhatsAppBusinessConfigDialogState();
}

class _WhatsAppBusinessConfigDialogState extends State<_WhatsAppBusinessConfigDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _appId;
  late final TextEditingController _businessAccountId;
  late final TextEditingController _phoneNumberId;
  final _accessToken = TextEditingController();
  final _appSecret = TextEditingController();
  final _verifyToken = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _appId = TextEditingController(text: widget.initial['app_id']?.toString() ?? '');
    _businessAccountId = TextEditingController(text: widget.initial['business_account_id']?.toString() ?? '');
    _phoneNumberId = TextEditingController(text: widget.initial['phone_number_id']?.toString() ?? '');
  }

  @override
  void dispose() {
    _appId.dispose();
    _businessAccountId.dispose();
    _phoneNumberId.dispose();
    _accessToken.dispose();
    _appSecret.dispose();
    _verifyToken.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await widget.api.putJson('/api/v1/integrations/whatsapp/business', {
        'app_id': _appId.text.trim(),
        'business_account_id': _businessAccountId.text.trim(),
        'phone_number_id': _phoneNumberId.text.trim(),
        'access_token': _accessToken.text.trim(),
        'app_secret': _appSecret.text.trim(),
        'verify_token': _verifyToken.text.trim(),
      });
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String? _required(String? value) => value == null || value.trim().isEmpty ? 'Este dato es obligatorio' : null;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Configurar WhatsApp Business'),
    content: SizedBox(
      width: 520,
      child: SingleChildScrollView(child: Form(
        key: _formKey,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Obtén estos datos en Meta for Developers y WhatsApp Manager. Los campos secretos quedan vacíos al editar; déjalos así para conservar los valores actuales.'),
          const SizedBox(height: 16),
          TextFormField(controller: _appId, decoration: const InputDecoration(labelText: 'ID de la aplicación Meta (opcional)'),),
          TextFormField(controller: _businessAccountId, validator: _required, decoration: const InputDecoration(labelText: 'ID de cuenta de WhatsApp Business (WABA) *'),),
          TextFormField(controller: _phoneNumberId, validator: _required, decoration: const InputDecoration(labelText: 'ID del número de teléfono *'),),
          TextFormField(controller: _accessToken, obscureText: true, validator: widget.initial['configured'] == true ? null : _required,
              decoration: InputDecoration(labelText: 'Token de acceso de Meta *', helperText: widget.initial['access_token_configured'] == true ? 'Configurado; vacío conserva el actual.' : null),),
          TextFormField(controller: _appSecret, obscureText: true, validator: widget.initial['configured'] == true ? null : _required,
              decoration: InputDecoration(labelText: 'App Secret *', helperText: widget.initial['app_secret_configured'] == true ? 'Configurado; vacío conserva el actual.' : null),),
          TextFormField(controller: _verifyToken, obscureText: true, validator: widget.initial['configured'] == true ? null : _required,
              decoration: InputDecoration(labelText: 'Token de verificación del webhook *', helperText: widget.initial['verify_token_configured'] == true ? 'Configurado; vacío conserva el actual.' : 'Define uno y usa el mismo valor al registrar el webhook en Meta.'),),
          const SizedBox(height: 12),
          const Align(alignment: Alignment.centerLeft, child: Text('Al guardar, Gudex no muestra ni registra los secretos. La conexión operativa de mensajes y webhook debe habilitarse por separado.'),),
        ]),
      )),
    ),
    actions: [
      TextButton(onPressed: _saving ? null : () => Navigator.of(context).pop(false), child: const Text('Cancelar')),
      FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Guardando…' : 'Guardar credenciales')),
    ],
  );
}
