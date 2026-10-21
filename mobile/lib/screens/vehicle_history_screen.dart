import 'dart:math';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/constants.dart';
import '../providers/auth_provider.dart';
import '../services/api_client.dart';

class VehicleHistoryScreen extends ConsumerStatefulWidget {
  const VehicleHistoryScreen(
      {required this.api,
      required this.vehicleId,
      required this.portal,
      super.key});
  final ApiClient api;
  final int vehicleId;
  final bool portal;
  @override
  ConsumerState<VehicleHistoryScreen> createState() =>
      _VehicleHistoryScreenState();
}

class _VehicleHistoryScreenState extends ConsumerState<VehicleHistoryScreen> {
  late Future<Map<String, dynamic>> _history;
  final Map<String, Future<Uint8List>> _cardPhotoFutures = {};
  bool _busy = false;
  bool get _canEdit => !widget.portal && ref.read(authProvider).role == 'admin';
  @override
  void initState() {
    super.initState();
    _history = _load();
  }

  Future<Map<String, dynamic>> _load() async {
    final prefix = widget.portal ? '/api/v1/portal' : '/api/v1';
    return Map<String, dynamic>.from(await widget.api
        .get('$prefix/vehicles/${widget.vehicleId}/history') as Map);
  }

  Future<void> _refresh() async {
    final future = _load();
    setState(() { _cardPhotoFutures.clear(); _history = future; });
    await future;
  }

  Map<String, dynamic> _map(dynamic v) =>
      v is Map ? Map<String, dynamic>.from(v) : {};
  List<Map<String, dynamic>> _maps(dynamic v) =>
      v is List ? v.map(_map).toList() : [];
  String _date(dynamic v) =>
      DateTime.tryParse('$v')?.toLocal().toString().split('.').first ??
      'Sin fecha';
  void _error(Object error) {
    if (mounted)
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('$error')));
  }

  Future<void> _partPhoto(Map<String, dynamic> part) async {
    try {
      final bytes = await widget.api.getBytes('${part['photo_url']}');
      if (!mounted) return;
      await showDialog<void>(context: context, builder: (context) => Dialog(
        child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 900, maxHeight: 700),
          child: Image.memory(bytes, fit: BoxFit.contain))));
    } catch (error) { _error(error); }
  }

  String _status(dynamic status) => switch (status) {
        'verified' => 'Verificado',
        'suggested' => 'Sugerido por IA',
        _ => 'Por verificar'
      };

  Future<void> _editIdentity(Map<String, dynamic> vehicle) async {
    const labels = {
      'plate': 'Patente',
      'make': 'Marca',
      'model': 'Modelo',
      'year': 'Año',
      'vin': 'VIN',
      'engine_number': 'Número de motor',
      'engine_code': 'Código de motor',
      'displacement_cc': 'Cilindrada (cc)',
      'current_mileage_km': 'Kilometraje'
    };
    final controllers = {
      for (final key in labels.keys)
        key: TextEditingController(text: '${vehicle[key] ?? ''}')
    };
    bool saving = false;
    bool saved = false;
    bool publicCard = vehicle['public_service_card_enabled'] == true;
    String? error;
    await _showEditor(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => StatefulBuilder(
            builder: (context, update) => PopScope(
                canPop: !saving,
                child: AlertDialog(
                  title: const Text('Información del vehículo'),
                  content: SizedBox(
                      width: 480,
                      child: SingleChildScrollView(
                          child:
                              Column(mainAxisSize: MainAxisSize.min, children: [
                        for (final field in labels.entries)
                          Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: TextField(
                                  controller: controllers[field.key],
                                  enabled: !saving,
                                  keyboardType: ['year', 'current_mileage_km', 'displacement_cc']
                                          .contains(field.key)
                                      ? TextInputType.number
                                      : TextInputType.text,
                                  decoration:
                                      InputDecoration(labelText: field.value))),
                        SwitchListTile(
                          value: publicCard,
                          title: const Text('Tarjeta de aceite pública'),
                          subtitle: const Text('Permite consultar solo la última mantención de aceite y la próxima por patente. No muestra datos del cliente.'),
                          onChanged: saving ? null : (value) => update(() => publicCard = value),
                        ),
                        if (error != null)
                          Text(error!,
                              style: TextStyle(
                                  color: Theme.of(context).colorScheme.error)),
                      ]))),
                  actions: [
                    TextButton(
                        onPressed:
                            saving ? null : () => Navigator.pop(dialogContext),
                        child: const Text('Cancelar')),
                    FilledButton(
                        onPressed: saving
                            ? null
                            : () async {
                                final payload = <String, dynamic>{};
                                for (final field in labels.keys) {
                                  final text = controllers[field]!.text.trim();
                                  if (['plate', 'make', 'model']
                                          .contains(field) &&
                                      text.isEmpty) {
                                    update(() => error =
                                        'Completa patente, marca y modelo.');
                                    return;
                                  }
                                  if (['year', 'current_mileage_km', 'displacement_cc']
                                          .contains(field) &&
                                      text.isNotEmpty &&
                                      (int.tryParse(text) == null ||
                                          int.parse(text) < 0)) {
                                    update(() =>
                                        error = 'Revisa año y kilometraje.');
                                    return;
                                  }
                                  payload[field] = text.isEmpty
                                      ? null
                                      : ['year', 'current_mileage_km', 'displacement_cc']
                                              .contains(field)
                                          ? int.parse(text)
                                          : text;
                                }
                                payload['public_service_card_enabled'] = publicCard;
                                update(() {
                                  saving = true;
                                  error = null;
                                });
                                try {
                                  await widget.api.patchJson(
                                      '/api/v1/vehicles/${widget.vehicleId}',
                                      payload);
                                  saved = true;
                                  if (dialogContext.mounted)
                                    Navigator.pop(dialogContext);
                                } catch (e) {
                                  update(() {
                                    saving = false;
                                    error = '$e';
                                  });
                                }
                              },
                        child: Text(saving ? 'Guardando…' : 'Guardar'))
                  ],
                ))));
    for (final c in controllers.values) {
      c.dispose();
    }
    if (saved && mounted) {
      try {
        await _refresh();
      } catch (e) {
        _error(e);
      }
    }
  }

  Future<void> _edit(
      Map<String, dynamic> field, Map<String, dynamic> entry) async {
    final value = TextEditingController(text: entry['value']?.toString() ?? '');
    final source =
        TextEditingController(text: entry['source']?.toString() ?? '');
    bool verified = entry['status'] == 'verified';
    bool saving = false;
    bool saved = false;
    String? error;
    await _showEditor(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => StatefulBuilder(
            builder: (context, update) => PopScope(
                  canPop: !saving,
                  child: AlertDialog(
                    title: Text('${field['label']}'),
                    content: SizedBox(
                        width: 520,
                        child: SingleChildScrollView(
                            child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                              TextField(
                                  controller: value,
                                  enabled: !saving,
                                  maxLength: 8000,
                                  minLines: 2,
                                  maxLines: 7,
                                  decoration: const InputDecoration(
                                      labelText: 'Dato técnico',
                                      hintText:
                                          'Indica aplicación exacta; si no corresponde, escribe No aplica.')),
                              const SizedBox(height: 12),
                              TextField(
                                  controller: source,
                                  enabled: !saving,
                                  maxLength: 2000,
                                  minLines: 2,
                                  maxLines: 4,
                                  decoration: const InputDecoration(
                                      labelText: 'Fuente documental',
                                      hintText:
                                          'Manual, página, catálogo, URL y variante consultada')),
                              CheckboxListTile(
                                  value: verified,
                                  onChanged: saving
                                      ? null
                                      : (v) =>
                                          update(() => verified = v ?? false),
                                  title: const Text(
                                      'Verificado para este vehículo')),
                              if (error != null)
                                Text(error!,
                                    style: TextStyle(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .error)),
                            ]))),
                    actions: [
                      TextButton(
                          onPressed: saving
                              ? null
                              : () => Navigator.pop(dialogContext),
                          child: const Text('Cancelar')),
                      FilledButton(
                          onPressed: saving
                              ? null
                              : () async {
                                  if (verified &&
                                      (source.text.trim().isEmpty ||
                                          value.text.trim().isEmpty)) {
                                    update(() => error =
                                        'Completa el dato y su fuente antes de verificar.');
                                    return;
                                  }
                                  update(() {
                                    saving = true;
                                    error = null;
                                  });
                                  try {
                                    await widget.api.putJson(
                                        '/api/v1/vehicles/${widget.vehicleId}/technical/${field['key']}',
                                        {
                                          'value': value.text,
                                          'source': source.text,
                                          'status':
                                              verified ? 'verified' : 'draft',
                                          'revision': entry['revision'] ?? 0,
                                        });
                                    saved = true;
                                    if (dialogContext.mounted)
                                      Navigator.pop(dialogContext);
                                  } catch (e) {
                                    update(() {
                                      saving = false;
                                      error = '$e';
                                    });
                                  }
                                },
                          child: Text(saving ? 'Guardando…' : 'Guardar'))
                    ],
                  ),
                )));
    value.dispose();
    source.dispose();
    if (saved && mounted) {
      try {
        await _refresh();
      } catch (e) {
        _error(e);
      }
    }
  }

  Future<void> _showEditor(
      {required BuildContext context,
      required bool barrierDismissible,
      required WidgetBuilder builder}) async {
    final route = DialogRoute<void>(
        context: context,
        builder: builder,
        barrierDismissible: barrierDismissible);
    await Navigator.of(context).push(route);
    // Text fields remain mounted during the reverse route animation.
    await route.completed;
  }

  Future<void> _assist() async {
    setState(() => _busy = true);
    try {
      await widget.api
          .post('/api/v1/vehicles/${widget.vehicleId}/technical-assistant');
      if (mounted) await _refresh();
    } catch (e) {
      _error(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _revisions() async {
    try {
      final rows = _maps(await widget.api
          .get('/api/v1/vehicles/${widget.vehicleId}/technical-history'));
      if (!mounted) return;
      await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
                title: const Text('Historial de cambios técnicos'),
                content: SizedBox(
                    width: 600,
                    height: 420,
                    child: rows.isEmpty
                        ? const Text('Sin cambios registrados')
                        : ListView(
                            children: rows
                                .map((r) => ListTile(
                                      title: Text(
                                          '${r['key']} · revisión ${r['revision']} · ${_status(r['status'])}'),
                                      subtitle: Text(
                                          '${r['value']}\nFuente: ${r['source']}\n${r['changed_by']} · ${_date(r['created_at'])}'),
                                    ))
                                .toList())),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cerrar'))
                ],
              ));
    } catch (e) {
      _error(e);
    }
  }

  Widget _page(List<Widget> children) =>
      ListView(padding: const EdgeInsets.all(16), children: children);
  Widget _heading(String title) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Text(title, style: Theme.of(context).textTheme.titleMedium));
  List<Widget> _fields(String group, Map<String, dynamic> technical) {
    final values = _map(technical['values']);
    return _maps(technical['fields'])
        .where((f) => f['group'] == group)
        .map((f) {
      final entry = _map(values[f['key']]);
      final filled = '${entry['value'] ?? ''}'.trim().isNotEmpty;
      final accent = entry['status'] == 'verified' ? Colors.green :
          entry['status'] == 'suggested' ? Colors.amber.shade700 : Theme.of(context).colorScheme.outline;
      return TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1), duration: const Duration(milliseconds: 280),
        builder: (context, value, child) => Opacity(opacity: value,
          child: Transform.translate(offset: Offset(0, 8 * (1 - value)), child: child)),
        child: Card(
          clipBehavior: Clip.antiAlias,
          child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Container(width: 5, height: 34, margin: const EdgeInsets.only(right: 12),
                        decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(4))),
                      Expanded(
                          child: Text('${f['label']}',
                              style: Theme.of(context).textTheme.titleSmall)),
                      if (_canEdit)
                        IconButton(
                            tooltip: 'Editar ${f['label']}',
                            onPressed: () => _edit(f, entry),
                            icon: const Icon(Icons.edit_outlined))
                    ]),
                    SelectableText(
                        filled ? '${entry['value']}' : 'Por completar'),
                    if (filled) ...[
                      const SizedBox(height: 8),
                      Chip(
                          avatar: Icon(
                              entry['status'] == 'verified'
                                  ? Icons.verified_outlined
                                  : Icons.info_outline,
                              size: 18),
                          label: Text(_status(entry['status']))),
                      if ('${entry['source'] ?? ''}'.isNotEmpty)
                        Text('Fuente: ${entry['source']}'),
                      if ('${entry['source'] ?? ''}'.startsWith('https://'))
                        TextButton(
                            onPressed: () async {
                              try {
                                if (!await launchUrl(
                                    Uri.parse(
                                        '${entry['source']}'.split('\n').first),
                                    mode: LaunchMode.externalApplication)) {
                                  throw Exception('No se pudo abrir la fuente');
                                }
                              } catch (e) {
                                _error(e);
                              }
                            },
                            child: const Text('Consultar fuente')),
                      if (entry['needs_review'] == true)
                        const Text(
                            'La identificación cambió. Revisa nuevamente la aplicación de este dato.'),
                      Text('Actualizado: ${_date(entry['created_at'])}',
                          style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ]))));
    }).toList();
  }

  List<Widget> _groupedFields(String group, Map<String, dynamic> technical) {
    final fields =
        _maps(technical['fields']).where((f) => f['group'] == group).toList();
    final categories =
        fields.map((f) => '${f['label']}'.split(' · ').first).toSet();
    return categories
        .map((category) => Card(
                child: ExpansionTile(
              key: PageStorageKey('$group-$category'),
              initiallyExpanded: category == categories.first,
              title: Text(category),
              children: _fields(group, {
                ...technical,
                'fields': fields
                    .where(
                        (f) => '${f['label']}'.split(' · ').first == category)
                    .toList()
              }),
            )))
        .toList();
  }

  Future<void> _maintenanceEditor(Map<String, dynamic> data,
      {Map<String, dynamic>? plan}) async {
    final completing = plan != null;
    final name = TextEditingController();
    final km = TextEditingController(
        text: completing
            ? '${_map(data['vehicle'])['current_mileage_km'] ?? ''}'
            : '');
    final days = TextEditingController();
    final nextKm = TextEditingController();
    final materials = TextEditingController();
    final oilUsed = TextEditingController();
    final filtersUsed = TextEditingController();
    final notes = TextEditingController();
    final requestKey = List.generate(
            24,
            (_) =>
                Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'))
        .join();
    int? orderId;
    String category = 'general';
    DateTime? nextDate;
    bool saving = false, saved = false;
    String? error;
    final orders = _maps(data['work_orders'])
        .where(
            (o) => {'in_progress', 'ready', 'delivered'}.contains(o['status']))
        .toList();
    await _showEditor(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => StatefulBuilder(
            builder: (context, update) => PopScope(
                canPop: !saving,
                child: AlertDialog(
                  title: Text(completing
                      ? 'Registrar mantención realizada'
                      : 'Nuevo plan de mantención'),
                  content: SizedBox(
                      width: 460,
                      child: SingleChildScrollView(
                          child:
                              Column(mainAxisSize: MainAxisSize.min, children: [
                        if (!completing)
                          const Text(
                              'Define los intervalos según el fabricante y el uso del vehículo; Gudex no los deduce automáticamente.'),
                        if (!completing)
                          TextField(
                              controller: name,
                              enabled: !saving,
                              decoration: const InputDecoration(
                                  labelText: 'Nombre del plan *')),
                        if (!completing)
                          DropdownButtonFormField<String>(
                            initialValue: category,
                            decoration: const InputDecoration(labelText: 'Tipo de mantención'),
                            items: const [
                              DropdownMenuItem(value: 'oil', child: Text('Aceite de motor')),
                              DropdownMenuItem(value: 'filters', child: Text('Filtros')),
                              DropdownMenuItem(value: 'preventive', child: Text('Preventiva')),
                              DropdownMenuItem(value: 'general', child: Text('General')),
                            ],
                            onChanged: saving ? null : (value) => update(() => category = value ?? 'general'),
                          ),
                        TextField(
                            controller: km,
                            enabled: !saving,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                                labelText: completing
                                    ? 'Kilometraje realizado *'
                                    : 'Intervalo en kilómetros')),
                        if (!completing)
                          TextField(
                              controller: days,
                              enabled: !saving,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                  labelText: 'Intervalo en días')),
                        if (completing) ...[
                          if (plan['category'] == 'oil') ...[
                            TextField(controller: oilUsed, enabled: !saving, maxLines: 2,
                              decoration: const InputDecoration(
                                labelText: 'Aceite realmente utilizado',
                                helperText: 'Marca, producto, viscosidad, norma y cantidad (L)')),
                            TextField(controller: filtersUsed, enabled: !saving, maxLines: 3,
                              decoration: const InputDecoration(
                                labelText: 'Filtros realmente instalados',
                                helperText: 'Tipo, marca y número de parte de cada filtro')),
                          ],
                          TextField(controller: nextKm, enabled: !saving,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(labelText: 'Próxima mantención a los km (opcional)',
                              helperText: 'Si se deja vacío, se calcula con el intervalo del plan')),
                          OutlinedButton.icon(
                            onPressed: saving ? null : () async {
                              final selected = await showDatePicker(context: dialogContext,
                                initialDate: DateTime.now().add(const Duration(days: 1)),
                                firstDate: DateTime.now().add(const Duration(days: 1)),
                                lastDate: DateTime.now().add(const Duration(days: 3650)));
                              if (selected != null) update(() => nextDate = selected);
                            },
                            icon: const Icon(Icons.event_outlined),
                            label: Text(nextDate == null ? 'Elegir próxima fecha (opcional)' :
                              'Próxima fecha: ${nextDate!.day}/${nextDate!.month}/${nextDate!.year}'),
                          ),
                          DropdownButtonFormField<int>(
                              initialValue: orderId,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                  labelText: 'Orden asociada (opcional)'),
                              items: orders
                                  .map((o) => DropdownMenuItem<int>(
                                      value: o['id'] as int,
                                      child: Text('${o['code']}')))
                                  .toList(),
                              onChanged: saving
                                  ? null
                                  : (id) => update(() => orderId = id)),
                          TextField(
                              controller: materials,
                              enabled: !saving,
                              maxLines: 3,
                              decoration: const InputDecoration(
                                  labelText:
                                      'Filtros y fluidos realmente utilizados',
                                  helperText:
                                      'Registro descriptivo; no descuenta inventario.')),
                          TextField(
                              controller: notes,
                              enabled: !saving,
                              maxLines: 3,
                              decoration: const InputDecoration(
                                  labelText:
                                      'Observaciones visibles para el cliente')),
                        ],
                        if (error != null)
                          Text(error!,
                              style: TextStyle(
                                  color: Theme.of(context).colorScheme.error)),
                      ]))),
                  actions: [
                    TextButton(
                        onPressed:
                            saving ? null : () => Navigator.pop(dialogContext),
                        child: const Text('Cancelar')),
                    FilledButton(
                        onPressed: saving
                            ? null
                            : () async {
                                final mileage = int.tryParse(km.text.trim());
                                final intervalDays =
                                    int.tryParse(days.text.trim());
                                final nextMileage = int.tryParse(nextKm.text.trim());
                                if ((km.text.trim().isNotEmpty &&
                                        mileage == null) ||
                                    (nextKm.text.trim().isNotEmpty && nextMileage == null) ||
                                    (!completing &&
                                        days.text.trim().isNotEmpty &&
                                        intervalDays == null) ||
                                    (completing &&
                                        (mileage == null || mileage < 0)) ||
                                    (!completing &&
                                        (name.text.trim().length < 2 ||
                                            (mileage == null &&
                                                intervalDays == null) ||
                                            (mileage != null && mileage <= 0) ||
                                            (intervalDays != null &&
                                                intervalDays <= 0)))) {
                                  update(() => error =
                                      'Revisa el nombre, kilometraje e intervalos.');
                                  return;
                                }
                                update(() {
                                  saving = true;
                                  error = null;
                                });
                                try {
                                  await widget.api.postJson(
                                      completing
                                          ? '/api/v1/maintenance-plans/${plan['id']}/executions'
                                          : '/api/v1/maintenance-plans',
                                      completing
                                          ? {
                                              'request_key': requestKey,
                                              'mileage_km': mileage,
                                              'work_order_id': orderId,
                                              'materials':
                                                  materials.text.trim(),
                                              'oil_used': oilUsed.text.trim(),
                                              'filters_used': filtersUsed.text.trim(),
                                              'notes': notes.text.trim(),
                                              'next_due_km': nextMileage,
                                              'next_due_at': nextDate?.toIso8601String(),
                                            }
                                          : {
                                              'vehicle_id': widget.vehicleId,
                                              'name': name.text.trim(),
                                              'category': category,
                                              'interval_km': mileage,
                                              'interval_days': intervalDays
                                            });
                                  saved = true;
                                  if (dialogContext.mounted)
                                    Navigator.pop(dialogContext);
                                } catch (e) {
                                  if (dialogContext.mounted)
                                    update(() {
                                      saving = false;
                                      error = '$e';
                                    });
                                }
                              },
                        child: Text(saving ? 'Guardando…' : 'Guardar')),
                  ],
                ))));
    for (final controller in [name, km, days, nextKm, materials, oilUsed, filtersUsed, notes]) {
      controller.dispose();
    }
    if (saved && mounted) {
      try {
        await _refresh();
      } catch (e) {
        _error(e);
      }
    }
  }

  Future<void> _editOilCard(Map<String, dynamic> current) async {
    final service = TextEditingController(text: '${current['service_name'] ?? 'Cambio de aceite'}');
    final km = TextEditingController(text: '${current['mileage_km'] ?? ''}');
    final nextKm = TextEditingController(text: '${current['next_due_km'] ?? ''}');
    final oil = TextEditingController(text: '${current['oil_used'] ?? ''}');
    final filters = TextEditingController(text: '${current['filters_used'] ?? ''}');
    final note = TextEditingController(text: '${current['customer_note'] ?? ''}');
    DateTime performed = DateTime.tryParse('${current['performed_at']}')?.toLocal() ?? DateTime.now();
    DateTime? nextDate = DateTime.tryParse('${current['next_due_at']}')?.toLocal();
    bool saving = false, saved = false;
    String? error;
    await showDialog<void>(context: context, barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(builder: (context, update) => PopScope(
        canPop: !saving,
        child: AlertDialog(
          title: Text(current['id'] == null ? 'Crear tarjeta de aceite' : 'Editar tarjeta de aceite'),
          content: SizedBox(width: 520, child: SingleChildScrollView(child: Column(
            mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text('Esta tarjeta informa al cliente. Las correcciones no modifican la mantención original.'),
              TextField(controller: service, enabled: !saving, decoration: const InputDecoration(labelText: 'Servicio realizado *')),
              TextButton.icon(onPressed: saving ? null : () async {
                final selected = await showDatePicker(context: dialogContext, initialDate: performed,
                  firstDate: DateTime(1980), lastDate: DateTime.now().add(const Duration(days: 1)));
                if (selected != null) update(() => performed = selected);
              }, icon: const Icon(Icons.event), label: Text('Fecha del servicio: ${performed.day}/${performed.month}/${performed.year}')),
              TextField(controller: km, enabled: !saving, keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Kilometraje del servicio *')),
              TextField(controller: nextKm, enabled: !saving, keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Próximo cambio a los km')),
              TextButton.icon(onPressed: saving ? null : () async {
                final selected = await showDatePicker(context: dialogContext,
                  initialDate: nextDate ?? DateTime.now().add(const Duration(days: 1)),
                  firstDate: DateTime(1980), lastDate: DateTime.now().add(const Duration(days: 3650)));
                if (selected != null) update(() => nextDate = selected);
              }, icon: const Icon(Icons.event_repeat),
                label: Text(nextDate == null ? 'Agregar fecha del próximo cambio' :
                  'Próximo cambio: ${nextDate!.day}/${nextDate!.month}/${nextDate!.year}')),
              if (nextDate != null)
                TextButton(onPressed: saving ? null : () => update(() => nextDate = null),
                  child: const Text('Quitar próxima fecha')),
              TextField(controller: oil, enabled: !saving, maxLines: 2,
                decoration: const InputDecoration(labelText: 'Aceite utilizado',
                  helperText: 'Marca, producto, viscosidad, norma y cantidad')),
              TextField(controller: filters, enabled: !saving, maxLines: 3,
                decoration: const InputDecoration(labelText: 'Filtros instalados',
                  helperText: 'Tipo, marca y número de parte de cada filtro')),
              TextField(controller: note, enabled: !saving, maxLines: 3,
                decoration: const InputDecoration(labelText: 'Nota visible para el cliente')),
              if (error != null) Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ]))),
          actions: [
            TextButton(onPressed: saving ? null : () => Navigator.pop(dialogContext), child: const Text('Cancelar')),
            FilledButton(onPressed: saving ? null : () async {
              final mileage = int.tryParse(km.text.trim());
              final nextMileage = nextKm.text.trim().isEmpty ? null : int.tryParse(nextKm.text.trim());
              if (service.text.trim().length < 2 || mileage == null || mileage < 0 ||
                  (nextKm.text.trim().isNotEmpty && (nextMileage == null || nextMileage <= mileage))) {
                update(() => error = 'Revisa el servicio y los kilometrajes.');
                return;
              }
              update(() { saving = true; error = null; });
              try {
                await widget.api.putJson('/api/v1/vehicles/${widget.vehicleId}/oil-card', {
                  'service_name': service.text.trim(), 'performed_at': performed.toUtc().toIso8601String(),
                  'mileage_km': mileage, 'next_due_km': nextMileage,
                  'next_due_at': nextDate?.toUtc().toIso8601String(),
                  'oil_used': oil.text.trim(), 'filters_used': filters.text.trim(),
                  'customer_note': note.text.trim(),
                });
                saved = true;
                if (dialogContext.mounted) Navigator.pop(dialogContext);
              } catch (e) {
                if (dialogContext.mounted) update(() { saving = false; error = '$e'; });
              }
            }, child: Text(saving ? 'Guardando…' : 'Guardar tarjeta')),
          ],
        ))));
    for (final controller in [service, km, nextKm, oil, filters, note]) { controller.dispose(); }
    if (saved && mounted) await _refresh();
  }

  Future<void> _uploadOilCardImage(String kind) async {
    try {
      final picked = await FilePicker.pickFiles(type: FileType.image, withData: true);
      if (picked == null || picked.files.isEmpty || !mounted) return;
      final file = picked.files.single;
      if (file.bytes == null) throw Exception('No se pudo leer la imagen.');
      await widget.api.uploadBytes('/api/v1/vehicles/${widget.vehicleId}/oil-card/images/$kind',
        file.bytes!, file.name);
      if (mounted) await _refresh();
    } catch (error) { _error(error); }
  }

  Future<void> _showOilCardImage(String url) async {
    try {
      final bytes = await widget.api.getBytes(url);
      if (!mounted) return;
      await showDialog<void>(context: context, builder: (context) => Dialog(
        child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 900, maxHeight: 700),
          child: Image.memory(bytes, fit: BoxFit.contain))));
    } catch (error) { _error(error); }
  }

  Future<void> _removeOilCardImage(String kind) async {
    try {
      await widget.api.delete('/api/v1/vehicles/${widget.vehicleId}/oil-card/images/$kind');
      if (mounted) await _refresh();
    } catch (error) { _error(error); }
  }

  Widget _oilCard(Map<String, dynamic> data) {
    final vehicle = _map(data['vehicle']);
    final latest = _map(data['oil_card']);
    if (latest.isEmpty) {
      return _canEdit ? Align(alignment: Alignment.centerLeft, child: OutlinedButton.icon(
        onPressed: () => _editOilCard(const {}), icon: const Icon(Icons.oil_barrel_outlined),
        label: const Text('Crear tarjeta de aceite del último servicio'))) : const SizedBox.shrink();
    }
    final oilDescription = '${latest['oil_used'] ?? ''}'.trim();
    final filterDescription = '${latest['filters_used'] ?? ''}'.trim();
    final plate = vehicle['plate']?.toString() ?? '';
    final color = Theme.of(context).colorScheme;
    Widget metric(String label, String value, IconData icon) => Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: .10), borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: color.onPrimary), const SizedBox(height: 10),
        Text(label, style: TextStyle(color: color.onPrimary.withValues(alpha: .75), fontSize: 12)),
        const SizedBox(height: 4), Text(value, style: TextStyle(color: color.onPrimary, fontSize: 19, fontWeight: FontWeight.bold)),
      ]),
    );
    return Padding(padding: const EdgeInsets.only(bottom: 18), child: AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [color.primary, color.primary.withValues(alpha: .78)]),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: color.primary.withValues(alpha: .24), blurRadius: 24, offset: const Offset(0, 10))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('GUDEX · TARJETA DIGITAL DE ACEITE', style: TextStyle(color: color.onPrimary.withValues(alpha: .8), fontWeight: FontWeight.w700, letterSpacing: 1.2)),
        const SizedBox(height: 14),
        Text(plate, style: TextStyle(color: color.onPrimary, fontSize: 34, fontWeight: FontWeight.w900)),
        Text('${vehicle['make']} ${vehicle['model']}', style: TextStyle(color: color.onPrimary)),
        const SizedBox(height: 18),
        LayoutBuilder(builder: (context, constraints) => Wrap(spacing: 10, runSpacing: 10, children: [
          SizedBox(width: constraints.maxWidth > 600 ? (constraints.maxWidth - 30) / 4 : (constraints.maxWidth - 10) / 2,
            child: metric('Último servicio', _date(latest['performed_at']).split(' ').first, Icons.check_circle_outline)),
          SizedBox(width: constraints.maxWidth > 600 ? (constraints.maxWidth - 30) / 4 : (constraints.maxWidth - 10) / 2,
            child: metric('Kilometraje', '${latest['mileage_km']} km', Icons.speed_outlined)),
          SizedBox(width: constraints.maxWidth > 600 ? (constraints.maxWidth - 30) / 4 : (constraints.maxWidth - 10) / 2,
            child: metric('Próximo km', latest['next_due_km'] == null ? 'No definido' : '${latest['next_due_km']} km', Icons.route_outlined)),
          SizedBox(width: constraints.maxWidth > 600 ? (constraints.maxWidth - 30) / 4 : (constraints.maxWidth - 10) / 2,
            child: metric('Próxima fecha', latest['next_due_at'] == null ? 'No definida' : _date(latest['next_due_at']).split(' ').first, Icons.event_outlined)),
        ])),
        const SizedBox(height: 18),
        Text('PRODUCTOS DEL ÚLTIMO SERVICIO', style: TextStyle(color: color.onPrimary.withValues(alpha: .8), fontWeight: FontWeight.w700, letterSpacing: 1.1)),
        const SizedBox(height: 8),
        Text('Aceite: ${oilDescription.isEmpty ? 'No registrado en este servicio' : oilDescription}',
          style: TextStyle(color: color.onPrimary)),
        const SizedBox(height: 6),
        Text('Filtros: ${filterDescription.isEmpty ? 'No registrados en este servicio' : filterDescription}',
          style: TextStyle(color: color.onPrimary)),
        if ('${latest['customer_note'] ?? ''}'.trim().isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('Nota del taller: ${latest['customer_note']}', style: TextStyle(color: color.onPrimary)),
        ],
        Wrap(spacing: 10, runSpacing: 10, children: [
          for (final kind in ['oil', 'filter'])
            if (latest['${kind}_image_url'] != null)
              SizedBox(width: 160, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(kind == 'oil' ? 'Foto del aceite' : 'Foto del filtro',
                  style: TextStyle(color: color.onPrimary.withValues(alpha: .8), fontSize: 12)),
                const SizedBox(height: 4),
                ClipRRect(borderRadius: BorderRadius.circular(12), child: SizedBox(
                  width: 160, height: 120,
                  child: FutureBuilder<Uint8List>(
                    future: _cardPhotoFutures.putIfAbsent('${latest['${kind}_image_url']}',
                      () => widget.api.getBytes('${latest['${kind}_image_url']}')),
                    builder: (context, snapshot) => snapshot.hasData
                      ? Image.memory(snapshot.data!, fit: BoxFit.cover)
                      : Center(child: Icon(snapshot.hasError ? Icons.broken_image_outlined : Icons.image_outlined,
                          color: color.onPrimary)),
                  ),
                )),
              ])),
        ]),
        Wrap(spacing: 8, runSpacing: 4, children: [
          for (final kind in ['oil', 'filter']) ...[
            if (latest['${kind}_image_url'] != null)
              TextButton.icon(onPressed: () => _showOilCardImage('${latest['${kind}_image_url']}'),
                icon: Icon(Icons.image_outlined, color: color.onPrimary),
                label: Text(kind == 'oil' ? 'Ver foto aceite' : 'Ver foto filtro',
                  style: TextStyle(color: color.onPrimary))),
            if (_canEdit && latest['id'] != null) ...[
              TextButton.icon(onPressed: () => _uploadOilCardImage(kind),
                icon: Icon(Icons.add_photo_alternate_outlined, color: color.onPrimary),
                label: Text(latest['${kind}_image_url'] == null
                  ? (kind == 'oil' ? 'Agregar foto aceite' : 'Agregar foto filtro')
                  : (kind == 'oil' ? 'Cambiar foto aceite' : 'Cambiar foto filtro'),
                  style: TextStyle(color: color.onPrimary))),
              if (latest['${kind}_image_url'] != null)
                IconButton(onPressed: () => _removeOilCardImage(kind),
                  tooltip: kind == 'oil' ? 'Quitar foto aceite' : 'Quitar foto filtro',
                  icon: Icon(Icons.delete_outline, color: color.onPrimary)),
            ],
          ],
        ]),
        const SizedBox(height: 12),
        Text('Vence por fecha o kilometraje, lo que ocurra primero.', style: TextStyle(color: color.onPrimary.withValues(alpha: .8))),
        if (_canEdit) TextButton.icon(onPressed: () => _editOilCard(latest),
          icon: Icon(Icons.edit_outlined, color: color.onPrimary),
          label: Text(latest['id'] == null ? 'Crear tarjeta editable' : 'Editar tarjeta',
            style: TextStyle(color: color.onPrimary))),
        if (vehicle['public_service_card_enabled'] == true) TextButton.icon(
          onPressed: () => launchUrl(Uri.parse('https://bknd.gudex.cl/tarjeta-aceite?patente=${Uri.encodeQueryComponent(plate)}'),
              mode: LaunchMode.externalApplication),
          icon: Icon(Icons.open_in_new, color: color.onPrimary),
          label: Text('Ver tarjeta pública', style: TextStyle(color: color.onPrimary))),
      ]),
    ));
  }

  Future<void> _markOilPlan(Map<String, dynamic> plan) async {
    final confirmed = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: const Text('Clasificar plan de aceite'),
      content: Text('¿Confirmas que “${plan['name']}” corresponde a cambio de aceite de motor? Solo sus servicios realizados podrán aparecer en la tarjeta digital.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Confirmar')),
      ],
    ));
    if (confirmed != true || !mounted) return;
    try {
      await widget.api.patchJson('/api/v1/maintenance-plans/${plan['id']}', {'category': 'oil'});
      await _refresh();
    } catch (error) { _error(error); }
  }

  Widget _maintenance(Map<String, dynamic> data) {
    final plans = _maps(data['maintenance_plans']);
    final orders = _maps(data['work_orders']);
    final services = _maps(data['work_order_services']);
    final reports = _maps(data['scanner_reports']);
    final parts = _maps(data['installed_parts']);
    final verifiedParts = _maps(data['verified_part_references']);
    return _page([
      _oilCard(data),
      _heading('Repuestos instalados y referencias'),
      const Text('Referencias verificadas para este vehículo; confirmar siempre por VIN y documentación técnica antes de comprar.'),
      if (verifiedParts.isNotEmpty) ...[
        const SizedBox(height: 8),
        Text('Compatibilidad verificada', style: Theme.of(context).textTheme.titleMedium),
        ...verifiedParts.map((p) => ListTile(
          leading: const Icon(Icons.verified_outlined),
          title: Text('${p['name']} · ${p['brand'] ?? ''}'),
          subtitle: Text('OEM: ${p['oem_number'] == '' ? '—' : p['oem_number']} · Parte: ${p['part_number'] == '' ? '—' : p['part_number']}'),
        )),
      ],
      if (parts.isEmpty) const ListTile(title: Text('Sin repuestos registrados')),
      ...parts.map((p) => Card(child: ListTile(
        leading: const Icon(Icons.settings_outlined),
        title: Text('${p['name']} · ${p['quantity']} unidad(es)'),
          subtitle: Text('${p['supplied_by'] == 'customer' ? 'Aportado por cliente' : 'Aportado por taller'} · ${p['status']} · ${_date(p['installed_at'] ?? p['recorded_at'])}\nOEM: ${p['oem_number'] == '' ? '—' : p['oem_number']} · ${p['needs_review'] == true ? 'compatibilidad por revisar' : p['fitment_status']}'),
        trailing: p['photo_url'] == null ? null : IconButton(
          tooltip: 'Ver imagen de la pieza', icon: const Icon(Icons.image_outlined),
          onPressed: () => _partPhoto(p)),
      ))),
      _heading('Próximas mantenciones'),
      if (_canEdit)
        Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
                onPressed: () => _maintenanceEditor(data),
                icon: const Icon(Icons.add),
                label: const Text('Crear plan'))),
      const Text(
          'Vence por fecha o kilometraje, lo que ocurra primero. Los planes se administran desde el módulo de mantenciones.'),
      if (plans.isEmpty)
        const ListTile(title: Text('Sin planes de mantención registrados')),
      ...plans.map((p) {
        final history = _maps(data['maintenance_executions']).where((e) => e['plan_id'] == p['id']).toList();
        final latest = history.isEmpty ? <String, dynamic>{} : history.first;
        final calculatedKm = p['interval_km'] is num && p['last_service_km'] is num
            ? (p['interval_km'] as num) + (p['last_service_km'] as num)
            : null;
        final nextKm = latest['next_due_km'] ?? calculatedKm;
        final last = DateTime.tryParse('${p['last_service_at']}');
        final calculatedDate = last != null && p['interval_days'] is int
            ? last.add(Duration(days: p['interval_days'] as int))
            : null;
        final nextDate = DateTime.tryParse('${latest['next_due_at']}') ?? calculatedDate;
        return Card(
            child: ListTile(
                leading: const Icon(Icons.event_repeat),
                trailing: _canEdit && p['active'] == true
                    ? Row(mainAxisSize: MainAxisSize.min, children: [
                      if (p['category'] != 'oil') IconButton(
                        tooltip: 'Clasificar como cambio de aceite', icon: const Icon(Icons.oil_barrel_outlined),
                        onPressed: () => _markOilPlan(p)),
                      IconButton(
                        tooltip: 'Registrar mantención',
                        icon: const Icon(Icons.playlist_add_check),
                        onPressed: () => _maintenanceEditor(data, plan: p)),
                    ])
                    : null,
                title: Text(
                    '${p['name']}${p['active'] == true ? '' : ' · Inactivo'}'),
                subtitle: Text(
                    'Última: ${_date(p['last_service_at'])} · ${p['last_service_km'] ?? '—'} km\nPróxima: ${nextDate == null ? 'sin fecha' : _date(nextDate)} · ${nextKm ?? '—'} km')));
      }),
      _heading('Registro de mantenciones realizadas'),
      if (_maps(data['maintenance_executions']).isEmpty)
        const ListTile(
            title: Text('Sin ejecuciones registradas'),
            subtitle: Text(
                'Los planes anteriores conservan su última fecha; no se inventa historial previo.')),
      ..._maps(data['maintenance_executions']).map((e) {
        final oil = '${e['oil_used'] ?? ''}'.trim();
        final filters = '${e['filters_used'] ?? ''}'.trim();
        return Card(child: ListTile(
            leading: const Icon(Icons.fact_check_outlined),
            title: Text('${e['plan_name']} · ${e['mileage_km']} km'),
            subtitle: Text(
                '${_date(e['performed_at'])}\n${oil.isEmpty ? '' : 'Aceite: $oil\n'}${filters.isEmpty ? '' : 'Filtros: $filters\n'}${e['materials'] ?? ''}\n${e['notes'] ?? ''}'),
          ));
      }),
      _heading('Mantenciones y trabajos registrados'),
      if (orders.isEmpty)
        const ListTile(title: Text('Sin trabajos registrados')),
      ...orders.map((o) => Card(
          child: ListTile(
              leading: const Icon(Icons.build_outlined),
              title: Text('${o['code']} · ${spanishStatus(o['status'])}'),
              subtitle: Text(
                  '${_date(o['opened_at'])} · ${o['mileage_km'] ?? '—'} km\n${o['diagnosis'] ?? o['reported_symptoms'] ?? ''}')))),
      _heading('Servicios realizados por orden'),
      if (services.isEmpty) const ListTile(title: Text('Sin servicios detallados')),
      ...services.map((s) => Card(child: ListTile(
        leading: const Icon(Icons.handyman_outlined),
        title: Text('${s['name']}'),
        subtitle: Text('Orden #${s['work_order_id']} · ${s['status']} · ${_date(s['completed_at'] ?? s['created_at'])}\n${s['findings'] ?? ''}'),
      ))),
      _heading('Informes scanner LAUNCH'),
      if (reports.isEmpty) const ListTile(title: Text('Sin informes adjuntos')),
      ...reports.map((r) => Card(
          child: ListTile(
              title: Text('${r['filename']}'),
              subtitle: Text(
                  '${_date(r['scanned_at'])} · ${r['mileage_km'] ?? '—'} km'),
              trailing: IconButton(
                  tooltip: 'Abrir informe PDF',
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  onPressed: () async {
                    try {
                      await openGudexPdf(widget.api, '${r['download_url']}',
                          '${r['filename']}');
                    } catch (e) {
                      _error(e);
                    }
                  })))),
      _heading('Citas'),
      ..._maps(data['appointments']).map((a) => ListTile(
          leading: const Icon(Icons.event_outlined),
          title: Text('${a['service_type']}'),
          subtitle: Text(
              '${_date(a['starts_at'])} · ${spanishStatus(a['status'])}'))),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(authProvider);
    return DefaultTabController(
        length: 5,
        child: Scaffold(
          appBar: AppBar(
              title: const Text('Ficha técnica digital'),
              actions: [
                if (!widget.portal)
                  IconButton(
                      tooltip: 'Historial de cambios',
                      onPressed: _revisions,
                      icon: const Icon(Icons.history)),
                IconButton(
                    tooltip: 'Actualizar ficha',
                    onPressed: () async {
                      try {
                        await _refresh();
                      } catch (e) {
                        _error(e);
                      }
                    },
                    icon: const Icon(Icons.refresh)),
              ],
              bottom: const TabBar(isScrollable: true, tabs: [
                Tab(
                    text: 'Información',
                    icon: Icon(Icons.directions_car_outlined)),
                Tab(
                    text: 'Características y cuidados',
                    icon: Icon(Icons.auto_awesome_outlined)),
                Tab(text: 'Filtros', icon: Icon(Icons.filter_alt_outlined)),
                Tab(
                    text: 'Lubricantes y fluidos',
                    icon: Icon(Icons.water_drop_outlined)),
                Tab(
                    text: 'Mantenciones y trabajos',
                    icon: Icon(Icons.build_outlined)),
              ])),
          body: FutureBuilder<Map<String, dynamic>>(
              future: _history,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done)
                  return const Center(child: CircularProgressIndicator());
                if (snapshot.hasError)
                  return Center(
                      child: Padding(
                          padding: const EdgeInsets.all(24),
                          child:
                              Column(mainAxisSize: MainAxisSize.min, children: [
                            Text('${snapshot.error}'),
                            TextButton(
                                onPressed: () =>
                                    setState(() => _history = _load()),
                                child: const Text('Reintentar'))
                          ])));
                final data = snapshot.data!;
                final vehicle = _map(data['vehicle']);
                final technical = _map(data['technical']);
                final values = _map(technical['values']);
                final verified = values.values.where((v) => _map(v)['status'] == 'verified').length;
                final suggested = values.values.where((v) => _map(v)['status'] == 'suggested').length;
                return Column(children: [
                  Padding(
                      padding: const EdgeInsets.all(12),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(colors: [Theme.of(context).colorScheme.primaryContainer,
                            Theme.of(context).colorScheme.surfaceContainerHigh]),
                          borderRadius: BorderRadius.circular(22)),
                        child: Wrap(spacing: 16, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
                          const Icon(Icons.directions_car_outlined, size: 34),
                          Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                            Text('${vehicle['plate']} · ${vehicle['make']} ${vehicle['model']}',
                              style: Theme.of(context).textTheme.titleLarge),
                            Text('Año ${vehicle['year'] ?? '—'} · ${vehicle['current_mileage_km'] ?? '—'} km'),
                          ]),
                          Chip(label: Text('$verified datos verificados')),
                          Chip(label: Text('$suggested sugerencias por revisar')),
                        ]))),
                  Expanded(
                      child: TabBarView(children: [
                    _page([
                      Card(
                          child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    for (final item in {
                                      'Patente': 'plate',
                                      'Marca': 'make',
                                      'Modelo': 'model',
                                      'Año': 'year',
                                      'VIN': 'vin',
                                      'Motor': 'engine',
                                      'Kilometraje': 'current_mileage_km'
                                    }.entries)
                                      Padding(
                                          padding: const EdgeInsets.symmetric(
                                              vertical: 5),
                                          child: SelectableText(
                                              '${item.key}: ${vehicle[item.value] ?? 'Por completar'}')),
                                    if (_canEdit)
                                      OutlinedButton.icon(
                                          onPressed: () =>
                                              _editIdentity(vehicle),
                                          icon: const Icon(Icons.edit_outlined),
                                          label:
                                              const Text('Editar información')),
                                  ]))),
                      ..._fields('information', technical),
                    ]),
                    _page([
                      const Text(
                          'Las sugerencias requieren revisión técnica. Los datos pendientes no confirman compatibilidad.'),
                      if (values['research_status'] is Map)
                        Card(child: ListTile(
                          leading: const Icon(Icons.travel_explore_outlined),
                          title: const Text('Resultado de la investigación'),
                          subtitle: Text('${_map(values['research_status'])['value']}'),
                        )),
                      if (_canEdit)
                        Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: FilledButton.icon(
                                onPressed: _busy ? null : _assist,
                                icon: const Icon(Icons.auto_awesome),
                                label: Text(_busy
                                    ? 'Buscando fuentes…'
                                    : 'Buscar datos faltantes con IA'))),
                      ..._fields('care', technical),
                    ]),
                    _page([
                      const Text(
                          'Confirma cada equivalencia para la versión y motor exactos del vehículo.'),
                      ..._groupedFields('filters', technical)
                    ]),
                    _page([
                      const Text(
                          'Verifica norma, homologación y procedimiento. El color del refrigerante es orientativo y no determina compatibilidad.'),
                      ..._groupedFields('fluids', technical)
                    ]),
                    _maintenance(data),
                  ])),
                ]);
              }),
        ));
  }
}
