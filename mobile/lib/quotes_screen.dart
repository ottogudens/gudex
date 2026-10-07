part of 'main.dart';

class _QuotesScreen extends StatefulWidget {
  const _QuotesScreen({required this.api});
  final ApiClient api;

  @override
  State<_QuotesScreen> createState() => _QuotesScreenState();
}

class _QuotesScreenState extends State<_QuotesScreen> {
  List<Map<String, dynamic>> _quotes = [], _customers = [], _orders = [], _vehicles = [], _services = [];
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
        widget.api.get('/api/v1/services'),
      ]);
      if (!mounted) return;
      setState(() {
        _quotes = _records(results[0]); _customers = _records(results[1]);
        _orders = _records(results[2]); _vehicles = _records(results[3]);
        _services = _records(results[4]);
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

  Future<void> _edit([Map<String, dynamic>? quote]) async {
    final form = GlobalKey<FormState>();
    final description = TextEditingController(text: quote?['description']?.toString());
    final labor = TextEditingController(text: quote?['labor_clp']?.toString());
    final parts = TextEditingController(text: quote?['parts_clp']?.toString());
    final notes = TextEditingController(text: quote?['notes']?.toString());
    int? customerId = quote?['customer_id'] as int?, orderId = quote?['work_order_id'] as int?;
    final selectedServices = <String>[];
    String? amountError(String? value) {
      final amount = int.tryParse((value ?? '').trim());
      return amount == null || amount < 0 ? 'Ingresa un valor entero en CLP (0 si no aplica)' : null;
    }
    try {
      final data = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(builder: (context, update) {
          final orders = _orders.where((o) => o['customer_id'] == customerId).toList();
          final total = (int.tryParse(labor.text) ?? 0) + (int.tryParse(parts.text) ?? 0);
          return AlertDialog(
            title: Text(quote == null ? 'Nueva cotización' : 'Editar borrador'),
            content: SizedBox(width: 560, child: Form(key: form, child: SingleChildScrollView(child: Column(
              mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                DropdownButtonFormField<int>(
                  initialValue: customerId, isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Cliente *'),
                  items: _customers.map((c) => DropdownMenuItem<int>(value: c['id'] as int,
                    child: Text(c['full_name'].toString(), overflow: TextOverflow.ellipsis))).toList(),
                  onChanged: quote != null ? null : (value) => update(() { customerId = value; orderId = null; }),
                  validator: (value) => value == null ? 'Selecciona un cliente' : null,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  key: ValueKey(customerId), initialValue: orderId, isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Orden y vehículo *'),
                  items: orders.map((o) => DropdownMenuItem<int>(value: o['id'] as int,
                    child: Text(_orderLabel(o), overflow: TextOverflow.ellipsis))).toList(),
                  onChanged: quote != null ? null : (value) => update(() => orderId = value),
                  validator: (value) => value == null ? 'Selecciona una orden' : null,
                ),
                if (customerId != null && orders.isEmpty)
                  const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('Este cliente no tiene órdenes. Crea una en Órdenes de trabajo y vuelve a este menú.')),
                const SizedBox(height: 12),
                TextFormField(controller: description, maxLength: 250, maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Trabajo propuesto *'),
                  validator: (v) => v == null || v.trim().isEmpty ? 'Describe el trabajo' : null),
                DropdownButtonFormField<String>(
                  isExpanded: true, decoration: const InputDecoration(labelText: 'Agregar servicio del catálogo'),
                  items: _services.map((s) => DropdownMenuItem<String>(value: s['code'] as String,
                    child: Text('${s['category']} · ${s['name']}', overflow: TextOverflow.ellipsis))).toList(),
                  onChanged: (code) {
                    if (code == null) return;
                    final service = _services.firstWhere((s) => s['code'] == code);
                    final name = service['name'] as String;
                    final suggestedPrice = (service['price_clp'] as num?)?.toInt() ?? 0;
                    update(() {
                      final isNew = !selectedServices.contains(name);
                      if (isNew) selectedServices.add(name);
                      if (description.text.trim().isEmpty) description.text = name;
                      if (isNew && suggestedPrice > 0) {
                        labor.text = ((int.tryParse(labor.text) ?? 0) + suggestedPrice).toString();
                      }
                    });
                  },
                ),
                Wrap(spacing: 6, children: selectedServices.map((name) => InputChip(label: Text(name),
                  onDeleted: () => update(() => selectedServices.remove(name)))).toList()),
                const SizedBox(height: 12),
                const Text('El precio sugerido de cada servicio seleccionado se suma a la mano de obra. Puedes ajustarlo antes de guardar.'),
                const SizedBox(height: 12),
                TextFormField(controller: labor, keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Mano de obra / servicios (CLP) *'),
                  validator: amountError, onChanged: (_) => update(() {})),
                const SizedBox(height: 12),
                TextFormField(controller: parts, keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Repuestos e insumos (CLP) *'),
                  validator: amountError, onChanged: (_) => update(() {})),
                const SizedBox(height: 12),
                Text('Total: ${_money(total)} CLP', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                TextFormField(controller: notes, maxLines: 4,
                  decoration: const InputDecoration(labelText: 'Detalle, alcance y condiciones')),
              ],
            )))),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancelar')),
              FilledButton(onPressed: () {
                if (!form.currentState!.validate()) return;
                final detail = [notes.text.trim(), if (selectedServices.isNotEmpty)
                  'Servicios incluidos:\n${selectedServices.map((s) => '• $s').join('\n')}']
                    .where((s) => s.isNotEmpty).join('\n\n');
                Navigator.pop(dialogContext, {
                  'order_id': orderId, 'description': description.text.trim(),
                  'labor_clp': int.parse(labor.text.trim()), 'parts_clp': int.parse(parts.text.trim()),
                  'notes': detail.isEmpty ? null : detail,
                });
              }, child: const Text('Guardar borrador')),
            ],
          );
        }),
      );
      if (data == null || !mounted) return;
      final selectedOrderId = data.remove('order_id');
      await _run(() async {
        if (quote == null) {
          await widget.api.postJson('/api/v1/work-orders/$selectedOrderId/quotes', data);
        } else {
          await widget.api.putJson('/api/v1/quotes/${quote['id']}', data);
        }
      }, 'Borrador guardado');
    } finally {
      // Los campos del diálogo pueden permanecer montados durante su animación de cierre.
      await Future<void>.delayed(const Duration(milliseconds: 300));
      description.dispose(); labor.dispose(); parts.dispose(); notes.dispose();
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
                Text('${q['order_code']} · ${q['vehicle_plate']}'),
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
                ]),
              ],
            )));
          })),
    ]);
  }
}
