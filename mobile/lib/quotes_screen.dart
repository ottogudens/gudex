part of 'main.dart';

class _QuotesScreen extends StatefulWidget {
  const _QuotesScreen({required this.api});
  final ApiClient api;

  @override
  State<_QuotesScreen> createState() => _QuotesScreenState();
}

class _QuotesScreenState extends State<_QuotesScreen> {
  List<Map<String, dynamic>> _quotes = [], _customers = [], _orders = [], _vehicles = [], _services = [], _products = [];
  bool _loading = true, _busy = false;
  String? _error;
  String _search = '', _status = 'all';

  @override
  void initState() {
    super.initState();
    _load();
  }

  List<Map<String, dynamic>> _records(dynamic value) => (value as List)
      .map((row) => Map<String, dynamic>.from(row as Map)).toList();

  Future<void> _load() async {
    if (mounted) setState(() { _loading = true; _error = null; });
    try {
      final results = await Future.wait([
        widget.api.get('/api/v1/quotes'), widget.api.get('/api/v1/customers'),
        widget.api.get('/api/v1/work-orders'), widget.api.get('/api/v1/vehicles'),
        widget.api.get('/api/v1/services'), widget.api.get('/api/v1/products'),
      ]);
      if (!mounted) return;
      setState(() {
        _quotes = _records(results[0]); _customers = _records(results[1]);
        _orders = _records(results[2]); _vehicles = _records(results[3]);
        _services = _records(results[4]); _products = _records(results[5]);
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _money(dynamic value) => '\$${(value as num).toInt().toString().replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.')}';

  String _orderLabel(Map<String, dynamic> order) {
    final vehicles = _vehicles.where((v) => v['id'] == order['vehicle_id']);
    return '${order['code']} · ${vehicles.isEmpty ? 'Sin patente' : vehicles.first['plate']}';
  }

  Future<Map<String, dynamic>?> _manualLine(BuildContext context, String kind) async {
    final description = TextEditingController();
    final quantity = TextEditingController(text: '1');
    final price = TextEditingController(text: '0');
    try {
      return await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(kind == 'service' ? 'Agregar servicio manual' : 'Agregar producto manual'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: description, autofocus: true, decoration: const InputDecoration(labelText: 'Descripción *')),
            TextField(controller: quantity, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Cantidad *')),
            TextField(controller: price, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Precio unitario (CLP) *')),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
            FilledButton(onPressed: () {
              final qty = double.tryParse(quantity.text.trim().replaceAll(',', '.'));
              final unitPrice = int.tryParse(price.text.trim().replaceAll('.', ''));
              if (description.text.trim().isEmpty || qty == null || qty <= 0 || unitPrice == null || unitPrice < 0) return;
              Navigator.pop(context, {'kind': kind, 'description': description.text.trim(), 'quantity': qty, 'unit_price_clp': unitPrice});
            }, child: const Text('Agregar')),
          ],
        ),
      );
    } finally {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      description.dispose(); quantity.dispose(); price.dispose();
    }
  }

  Future<void> _edit([Map<String, dynamic>? quote]) async {
    final form = GlobalKey<FormState>();
    final description = TextEditingController(text: quote?['description']?.toString() ?? 'Productos y servicios cotizados');
    final notes = TextEditingController(text: quote?['notes']?.toString());
    int? customerId = quote?['customer_id'] as int?;
    int? vehicleId = quote?['vehicle_id'] as int?;
    int? orderId = quote?['work_order_id'] as int?;
    final lines = <Map<String, dynamic>>[];
    final storedLines = quote?['lines'];
    if (storedLines is List && storedLines.isNotEmpty) {
      lines.addAll(storedLines.whereType<Map>().map((line) => Map<String, dynamic>.from(line)));
    } else if (quote != null) {
      final labor = (quote['labor_clp'] as num?)?.toInt() ?? 0;
      final parts = (quote['parts_clp'] as num?)?.toInt() ?? 0;
      if (labor > 0) lines.add({'kind': 'service', 'description': 'Servicios y mano de obra', 'quantity': 1.0, 'unit_price_clp': labor});
      if (parts > 0) lines.add({'kind': 'product', 'description': 'Repuestos e insumos', 'quantity': 1.0, 'unit_price_clp': parts});
    }
    try {
      final data = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(builder: (context, update) {
          final customerVehicles = _vehicles.where((v) => v['customer_id'] == customerId).toList();
          final orders = _orders.where((o) => o['customer_id'] == customerId && (vehicleId == null || o['vehicle_id'] == vehicleId)).toList();
          final serviceTotal = lines.where((line) => line['kind'] == 'service').fold<int>(0, (sum, line) => sum + (((line['quantity'] as num?) ?? 0) * ((line['unit_price_clp'] as num?) ?? 0)).round());
          final productTotal = lines.where((line) => line['kind'] == 'product').fold<int>(0, (sum, line) => sum + (((line['quantity'] as num?) ?? 0) * ((line['unit_price_clp'] as num?) ?? 0)).round());
          return AlertDialog(
            title: Text(quote == null ? 'Nueva cotización' : 'Editar borrador'),
            content: SizedBox(width: 720, child: Form(key: form, child: SingleChildScrollView(child: Column(
              mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                DropdownButtonFormField<int>(
                  initialValue: customerId, isExpanded: true, decoration: const InputDecoration(labelText: 'Cliente *'),
                  items: [
                    ..._customers.map((c) => DropdownMenuItem<int>(value: c['id'] as int, child: Text(c['full_name'].toString(), overflow: TextOverflow.ellipsis))),
                    const DropdownMenuItem<int>(value: -1, child: Row(children: [Icon(Icons.person_add_alt_1), SizedBox(width: 8), Text('Crear nuevo cliente')]))
                  ],
                  onChanged: (value) async {
                    if (value == -1) {
                      final created = await showQuickCreateCustomer(context, widget.api);
                      if (created != null && context.mounted) update(() { _customers.add(created); customerId = created['id'] as int; vehicleId = null; orderId = null; });
                    } else {
                      update(() { customerId = value; vehicleId = null; orderId = null; });
                    }
                  },
                  validator: (value) => value == null || value == -1 ? 'Selecciona un cliente' : null,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  key: ValueKey('quote-vehicle-$customerId-$vehicleId'), initialValue: customerVehicles.any((v) => v['id'] == vehicleId) ? vehicleId : null,
                  isExpanded: true, decoration: const InputDecoration(labelText: 'Vehículo *'),
                  items: [
                    ...customerVehicles.map((v) => DropdownMenuItem<int>(value: v['id'] as int, child: Text('${v['plate']} · ${v['make']} ${v['model']}', overflow: TextOverflow.ellipsis))),
                    if (customerId != null) const DropdownMenuItem<int>(value: -1, child: Row(children: [Icon(Icons.add_road), SizedBox(width: 8), Text('Crear nuevo vehículo')]))
                  ],
                  onChanged: customerId == null ? null : (value) async {
                    if (value == -1) {
                      final created = await showQuickCreateVehicle(context, widget.api, _customers, initialCustomerId: customerId);
                      if (created != null && context.mounted) update(() { _vehicles.add(created); vehicleId = created['id'] as int; orderId = null; });
                    } else {
                      update(() { vehicleId = value; orderId = null; });
                    }
                  },
                  validator: (value) => value == null || value == -1 ? 'Selecciona o crea un vehículo' : null,
                ),
                if (customerId != null && customerVehicles.isEmpty)
                  const Padding(padding: EdgeInsets.only(top: 8), child: Text('Este cliente no tiene vehículos. Selecciona “Crear nuevo vehículo”.')),
                const SizedBox(height: 12),
                DropdownButtonFormField<int?>(
                  key: ValueKey('quote-order-$customerId-$vehicleId-$orderId'), initialValue: orders.any((o) => o['id'] == orderId) ? orderId : null,
                  isExpanded: true, decoration: const InputDecoration(labelText: 'Orden de trabajo (opcional)'),
                  items: [
                    const DropdownMenuItem<int?>(value: null, child: Text('Sin orden asociada')),
                    ...orders.map((o) => DropdownMenuItem<int?>(value: o['id'] as int, child: Text(_orderLabel(o), overflow: TextOverflow.ellipsis))),
                  ],
                  onChanged: (value) => update(() => orderId = value),
                ),
                const SizedBox(height: 12),
                TextFormField(controller: description, maxLength: 250, maxLines: 2, decoration: const InputDecoration(labelText: 'Descripción general *'), validator: (value) => value == null || value.trim().isEmpty ? 'Describe la cotización' : null),
                const Divider(height: 28),
                Text('Productos y servicios', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 10),
                DropdownButtonFormField<int>(
                  key: ValueKey('service-${lines.length}'), isExpanded: true, decoration: const InputDecoration(labelText: 'Agregar servicio del catálogo'),
                  items: _services.map((service) => DropdownMenuItem<int>(value: service['id'] as int, child: Text('${service['category']} · ${service['name']} · ${_money(service['price_clp'] ?? 0)}', overflow: TextOverflow.ellipsis))).toList(),
                  onChanged: (id) {
                    if (id == null) return;
                    final service = _services.firstWhere((item) => item['id'] == id);
                    update(() => lines.add({'kind': 'service', 'service_id': id, 'description': service['name'].toString(), 'quantity': 1.0, 'unit_price_clp': (service['price_clp'] as num?)?.toInt() ?? 0}));
                  },
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<int>(
                  key: ValueKey('product-${lines.length}'), isExpanded: true, decoration: const InputDecoration(labelText: 'Agregar producto del catálogo'),
                  items: _products.where((product) => product['active'] != false).map((product) => DropdownMenuItem<int>(value: product['id'] as int, child: Text('${product['name']} · ${_money(product['price_clp'] ?? 0)}', overflow: TextOverflow.ellipsis))).toList(),
                  onChanged: (id) {
                    if (id == null) return;
                    final product = _products.firstWhere((item) => item['id'] == id);
                    update(() => lines.add({'kind': 'product', 'product_id': id, 'description': product['name'].toString(), 'quantity': 1.0, 'unit_price_clp': (product['price_clp'] as num?)?.toInt() ?? 0}));
                  },
                ),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  OutlinedButton.icon(onPressed: () async { final line = await _manualLine(context, 'service'); if (line != null && context.mounted) update(() => lines.add(line)); }, icon: const Icon(Icons.build_outlined), label: const Text('Servicio manual')),
                  OutlinedButton.icon(onPressed: () async { final line = await _manualLine(context, 'product'); if (line != null && context.mounted) update(() => lines.add(line)); }, icon: const Icon(Icons.inventory_2_outlined), label: const Text('Producto manual')),
                ]),
                if (lines.isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Text('Agrega al menos un producto o servicio.')),
                ...lines.asMap().entries.map((entry) {
                  final line = entry.value;
                  final lineTotal = (((line['quantity'] as num?) ?? 0) * ((line['unit_price_clp'] as num?) ?? 0)).round();
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(line['kind'] == 'service' ? Icons.build_outlined : Icons.inventory_2_outlined),
                    title: Text(line['description'].toString()),
                    subtitle: Text('${line['quantity']} × ${_money(line['unit_price_clp'])} = ${_money(lineTotal)}'),
                    trailing: IconButton(tooltip: 'Quitar', onPressed: () => update(() => lines.removeAt(entry.key)), icon: const Icon(Icons.close)),
                  );
                }),
                const Divider(),
                Text('Servicios: ${_money(serviceTotal)} · Productos: ${_money(productTotal)}', style: Theme.of(context).textTheme.bodyMedium),
                Text('Total: ${_money(serviceTotal + productTotal)} CLP', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 12),
                TextFormField(controller: notes, maxLines: 4, decoration: const InputDecoration(labelText: 'Detalle, alcance y condiciones')),
              ],
            )))),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancelar')),
              FilledButton(onPressed: () {
                if (!form.currentState!.validate()) return;
                if (lines.isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Agrega al menos un producto o servicio.'))); return; }
                Navigator.pop(dialogContext, {
                  'customer_id': customerId, 'vehicle_id': vehicleId, 'work_order_id': orderId,
                  'description': description.text.trim(), 'labor_clp': serviceTotal, 'parts_clp': productTotal,
                  'notes': notes.text.trim().isEmpty ? null : notes.text.trim(),
                  'lines': lines.map((line) => {
                    'kind': line['kind'], 'product_id': line['product_id'], 'service_id': line['service_id'],
                    'description': line['description'], 'quantity': line['quantity'], 'unit_price_clp': line['unit_price_clp'],
                  }).toList(),
                });
              }, child: const Text('Guardar borrador')),
            ],
          );
        }),
      );
      if (data == null || !mounted) return;
      await _run(() async {
        if (quote == null) {
          await widget.api.postJson('/api/v1/quotes', data);
        } else {
          await widget.api.putJson('/api/v1/quotes/${quote['id']}', data);
        }
      }, 'Borrador guardado');
    } finally {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      description.dispose(); notes.dispose();
    }
  }

  Future<void> _run(Future<void> Function() action, String message) async {
    setState(() => _busy = true);
    try {
      await action();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      await _load();
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _publish(Map<String, dynamic> quote) async {
    final confirmed = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: const Text('Enviar al portal del cliente'),
      content: Text('Publicar la cotización para ${quote['customer_name']} por ${_money(quote['labor_clp'] + quote['parts_clp'])} CLP. El cliente podrá verla y responder desde su cuenta. Después de publicar no se podrá editar. Esta acción no envía correo ni WhatsApp.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Publicar en portal')),
      ],
    ));
    if (confirmed != true || !mounted) return;
    await _run(() async { await widget.api.post('/api/v1/quotes/${quote['id']}/publish'); }, 'Cotización publicada en el portal');
  }

  Future<void> _pdf(Map<String, dynamic> quote, {bool share = false}) async {
    setState(() => _busy = true);
    try {
      final path = '/api/v1/quotes/${quote['id']}/pdf';
      final filename = 'cotizacion-${quote['id']}.pdf';
      if (share) {
        final bytes = await widget.api.getBytes(path);
        await Printing.sharePdf(bytes: bytes, filename: filename);
      } else {
        final bytes = await widget.api.getBytes(path);
        await Printing.layoutPdf(name: filename, onLayout: (_) async => bytes);
      }
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No se pudo abrir el PDF: $error')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _email(Map<String, dynamic> quote) async {
    final confirmed = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: const Text('Enviar cotización por Gmail'),
      content: Text('Se enviará la cotización COT-${quote['id']} al correo registrado de ${quote['customer_name']}. ¿Continuar?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Enviar')),
      ],
    ));
    if (confirmed != true || !mounted) return;
    await _run(() async { await widget.api.post('/api/v1/quotes/${quote['id']}/email'); }, 'Cotización enviada por Gmail');
  }

  @override
  Widget build(BuildContext context) {
    final records = _quotes.where((q) => (_status == 'all' || q['status'] == _status) &&
      '${q['customer_name']} ${q['vehicle_plate']} ${q['order_code']} ${q['description']} ${q['id']}'
        .toLowerCase().contains(_search.toLowerCase())).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Wrap(alignment: WrapAlignment.spaceBetween, spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        Text('Cotizaciones', style: Theme.of(context).textTheme.headlineSmall),
        FilledButton.icon(onPressed: _loading || _busy || _error != null ? null : () => _edit(),
          icon: const Icon(Icons.add), label: const Text('Nueva cotización')),
        IconButton(onPressed: _busy || _loading ? null : _load, icon: const Icon(Icons.refresh), tooltip: 'Actualizar'),
      ]),
      const SizedBox(height: 12),
      TextField(decoration: const InputDecoration(labelText: 'Buscar cliente, patente, orden o trabajo', prefixIcon: Icon(Icons.search)),
        onChanged: (value) => setState(() => _search = value)),
      const SizedBox(height: 8),
      DropdownButton<String>(value: _status, isExpanded: true, items: const [
        DropdownMenuItem(value: 'all', child: Text('Todos los estados')),
        DropdownMenuItem(value: 'draft', child: Text('Borradores')),
        DropdownMenuItem(value: 'sent', child: Text('Publicadas en portal')),
        DropdownMenuItem(value: 'approved', child: Text('Aprobadas')),
        DropdownMenuItem(value: 'rejected', child: Text('Rechazadas')),
      ], onChanged: (value) => setState(() => _status = value ?? 'all')),
      if (_busy) const LinearProgressIndicator(),
      Expanded(child: _loading ? const Center(child: CircularProgressIndicator())
        : _error != null ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('No se pudieron cargar las cotizaciones: $_error'),
            TextButton(onPressed: _load, child: const Text('Reintentar')),
          ]))
        : records.isEmpty ? const Center(child: Text('No hay cotizaciones para mostrar. Usa Nueva cotización para comenzar.'))
        : ListView.builder(itemCount: records.length, itemBuilder: (context, index) {
            final q = records[index];
            final draft = q['status'] == 'draft';
            return Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('COT-${q['id']} · ${q['customer_name']}', style: Theme.of(context).textTheme.titleMedium),
                Text('${q['vehicle_plate']}${q['order_code'] == null ? ' · Sin orden asociada' : ' · ${q['order_code']}'}'),
                const SizedBox(height: 8),
                Text(q['description'].toString()),
                if (q['notes'] != null) Text(q['notes'].toString()),
                const SizedBox(height: 8),
                Text('${_money(q['labor_clp'] + q['parts_clp'])} CLP · ${q['status'] == 'sent' ? 'Publicada en portal' : spanishStatus(q['status'])}'),
                Wrap(spacing: 8, children: [
                  if (draft) TextButton.icon(onPressed: _busy ? null : () => _edit(q), icon: const Icon(Icons.edit_outlined), label: const Text('Editar')),
                  TextButton.icon(onPressed: _busy ? null : () => _pdf(q), icon: const Icon(Icons.picture_as_pdf_outlined), label: const Text('Ver PDF')),
                  if (draft) TextButton.icon(onPressed: _busy ? null : () => _publish(q), icon: const Icon(Icons.send_outlined), label: const Text('Enviar al portal')),
                  if (!draft) TextButton.icon(onPressed: _busy ? null : () => _pdf(q, share: true), icon: const Icon(Icons.share_outlined),
                    label: Text(kIsWeb ? 'Descargar PDF para enviar' : 'Compartir PDF')),
                  if (!draft) TextButton.icon(onPressed: _busy ? null : () => _email(q), icon: const Icon(Icons.email_outlined),
                    label: const Text('Enviar por Gmail')),
                ]),
              ],
            )));
          })),
    ]);
  }
}
