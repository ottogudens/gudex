import 'dart:math';
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
    setState(() => _history = future);
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
      'engine': 'Motor',
      'current_mileage_km': 'Kilometraje'
    };
    final controllers = {
      for (final key in labels.keys)
        key: TextEditingController(text: '${vehicle[key] ?? ''}')
    };
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
                                  keyboardType: ['year', 'current_mileage_km']
                                          .contains(field.key)
                                      ? TextInputType.number
                                      : TextInputType.text,
                                  decoration:
                                      InputDecoration(labelText: field.value))),
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
                                  if (['year', 'current_mileage_km']
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
                                      : ['year', 'current_mileage_km']
                                              .contains(field)
                                          ? int.parse(text)
                                          : text;
                                }
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
      return Card(
          child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
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
                  ])));
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
    final materials = TextEditingController();
    final notes = TextEditingController();
    final requestKey = List.generate(
            24,
            (_) =>
                Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'))
        .join();
    int? orderId;
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
                                if ((km.text.trim().isNotEmpty &&
                                        mileage == null) ||
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
                                              'notes': notes.text.trim(),
                                            }
                                          : {
                                              'vehicle_id': widget.vehicleId,
                                              'name': name.text.trim(),
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
    for (final controller in [name, km, days, materials, notes]) {
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

  Widget _maintenance(Map<String, dynamic> data) {
    final plans = _maps(data['maintenance_plans']);
    final orders = _maps(data['work_orders']);
    final reports = _maps(data['scanner_reports']);
    return _page([
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
        final nextKm = p['interval_km'] is num && p['last_service_km'] is num
            ? (p['interval_km'] as num) + (p['last_service_km'] as num)
            : null;
        final last = DateTime.tryParse('${p['last_service_at']}');
        final nextDate = last != null && p['interval_days'] is int
            ? last.add(Duration(days: p['interval_days'] as int))
            : null;
        return Card(
            child: ListTile(
                leading: const Icon(Icons.event_repeat),
                trailing: _canEdit && p['active'] == true
                    ? IconButton(
                        tooltip: 'Registrar mantención',
                        icon: const Icon(Icons.playlist_add_check),
                        onPressed: () => _maintenanceEditor(data, plan: p))
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
      ..._maps(data['maintenance_executions']).map((e) => Card(
              child: ListTile(
            leading: const Icon(Icons.fact_check_outlined),
            title: Text('${e['plan_name']} · ${e['mileage_km']} km'),
            subtitle: Text(
                '${_date(e['performed_at'])}\n${e['materials'] ?? ''}\n${e['notes'] ?? ''}'),
          ))),
      _heading('Mantenciones y trabajos registrados'),
      if (orders.isEmpty)
        const ListTile(title: Text('Sin trabajos registrados')),
      ...orders.map((o) => Card(
          child: ListTile(
              leading: const Icon(Icons.build_outlined),
              title: Text('${o['code']} · ${spanishStatus(o['status'])}'),
              subtitle: Text(
                  '${_date(o['opened_at'])} · ${o['mileage_km'] ?? '—'} km\n${o['diagnosis'] ?? o['reported_symptoms'] ?? ''}')))),
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
                return Column(children: [
                  Padding(
                      padding: const EdgeInsets.all(12),
                      child: ListTile(
                          leading: const Icon(Icons.directions_car, size: 36),
                          title: Text(
                              '${vehicle['plate']} · ${vehicle['make']} ${vehicle['model']}'),
                          subtitle: Text(
                              'Año ${vehicle['year'] ?? '—'} · ${vehicle['current_mileage_km'] ?? '—'} km'))),
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
