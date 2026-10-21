import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../services/api_client.dart';

class InventoryCountScreen extends StatefulWidget {
  const InventoryCountScreen({required this.api, required this.canApply, super.key});
  final ApiClient api;
  final bool canApply;

  @override
  State<InventoryCountScreen> createState() => _InventoryCountScreenState();
}

class _InventoryCountScreenState extends State<InventoryCountScreen> {
  late Future<List<Map<String, dynamic>>> _sessions;

  @override
  void initState() { super.initState(); _sessions = _load(); }

  Future<List<Map<String, dynamic>>> _load() async {
    final raw = await widget.api.get('/api/v1/inventory-counts');
    return raw is List ? raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : [];
  }

  Future<void> _refresh() async { setState(() => _sessions = _load()); await _sessions; }

  Future<void> _create() async {
    final name = TextEditingController(text: 'Toma de inventario');
    var blind = true;
    try {
      final data = await showDialog<Map<String, dynamic>>(context: context, builder: (context) => StatefulBuilder(builder: (context, update) => AlertDialog(
        title: const Text('Nueva toma de inventario'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: name, autofocus: true, decoration: const InputDecoration(labelText: 'Nombre de la toma')),
          SwitchListTile.adaptive(contentPadding: EdgeInsets.zero, value: blind, title: const Text('Conteo ciego'), subtitle: const Text('El operario no ve el stock esperado mientras cuenta.'), onChanged: (value) => update(() => blind = value)),
        ]),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')), FilledButton(onPressed: () => Navigator.pop(context, {'name': name.text.trim(), 'blind_count': blind}), child: const Text('Iniciar conteo'))],
      )));
      if (data == null || '${data['name']}'.length < 3) return;
      final created = await widget.api.postJson('/api/v1/inventory-counts', data);
      if (mounted) await Navigator.push(context, MaterialPageRoute(builder: (_) => InventoryCountDetailScreen(api: widget.api, session: Map<String, dynamic>.from(created as Map), canApply: widget.canApply)));
      if (mounted) await _refresh();
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString().replaceFirst('Exception: ', ''))));
    } finally { name.dispose(); }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<Map<String, dynamic>>>(future: _sessions, builder: (context, snapshot) {
    if (snapshot.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
    if (snapshot.hasError) return Center(child: FilledButton(onPressed: _refresh, child: const Text('Reintentar')));
    final rows = snapshot.data ?? [];
    return RefreshIndicator(onRefresh: _refresh, child: ListView(padding: const EdgeInsets.all(18), children: [
      Row(children: [const Icon(Icons.qr_code_scanner_outlined, size: 34), const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Toma de inventario', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)), const Text('Escanea, cuenta y envía a revisión sin alterar el stock durante el proceso.')])), FilledButton.icon(onPressed: _create, icon: const Icon(Icons.add), label: const Text('Nueva toma'))]),
      const SizedBox(height: 18),
      if (rows.isEmpty) const Card(child: Padding(padding: EdgeInsets.all(20), child: Text('No hay tomas de inventario. Crea una para empezar a escanear productos.'))),
      ...rows.map((row) => Card(child: ListTile(leading: Icon(row['status'] == 'applied' ? Icons.verified_outlined : Icons.inventory_outlined), title: Text('${row['code']} · ${row['name']}'), subtitle: Text('${_status(row['status'])}${row['blind_count'] == true ? ' · Conteo ciego' : ''}'), trailing: const Icon(Icons.chevron_right), onTap: () async { await Navigator.push(context, MaterialPageRoute(builder: (_) => InventoryCountDetailScreen(api: widget.api, session: row, canApply: widget.canApply))); if (mounted) await _refresh(); }))),
    ]));
  });
}

class InventoryCountDetailScreen extends StatefulWidget {
  const InventoryCountDetailScreen({required this.api, required this.session, required this.canApply, super.key});
  final ApiClient api;
  final Map<String, dynamic> session;
  final bool canApply;
  @override
  State<InventoryCountDetailScreen> createState() => _InventoryCountDetailScreenState();
}

class _InventoryCountDetailScreenState extends State<InventoryCountDetailScreen> {
  late Future<Map<String, dynamic>> _detail;
  @override
  void initState() { super.initState(); _detail = _load(); }
  Future<Map<String, dynamic>> _load() async { final raw = await widget.api.get('/api/v1/inventory-counts/${widget.session['id']}'); return raw is Map ? Map<String, dynamic>.from(raw) : {}; }
  Future<void> _refresh() async { setState(() => _detail = _load()); await _detail; }
  double _qty(dynamic value) => value is num ? value.toDouble() : double.tryParse('$value') ?? 0;
  String _qtyText(dynamic value) { final n = _qty(value); return n.toStringAsFixed(n % 1 == 0 ? 0 : 2); }

  Future<void> _scan() async { await Navigator.push(context, MaterialPageRoute(builder: (_) => _BarcodeScanner(api: widget.api, sessionId: widget.session['id'] as int))); if (mounted) await _refresh(); }
  Future<void> _manualCode() async { final code = TextEditingController(); try { final value = await showDialog<String>(context: context, builder: (context) => AlertDialog(title: const Text('Ingresar código'), content: TextField(controller: code, autofocus: true, decoration: const InputDecoration(labelText: 'Código de barras / SKU')), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')), FilledButton(onPressed: () => Navigator.pop(context, code.text.trim()), child: const Text('Buscar'))])); if (value != null && value.isNotEmpty && mounted) { await Navigator.push(context, MaterialPageRoute(builder: (_) => _CountBarcode(api: widget.api, sessionId: widget.session['id'] as int, barcode: value))); if (mounted) await _refresh(); }} finally { code.dispose(); } }
  Future<void> _submit() async { try { await widget.api.post('/api/v1/inventory-counts/${widget.session['id']}/submit'); if (mounted) { await _refresh(); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Toma enviada a revisión'))); } } catch (error) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString().replaceFirst('Exception: ', '')))); } }
  Future<void> _apply() async { try { await widget.api.post('/api/v1/inventory-counts/${widget.session['id']}/apply'); if (mounted) { await _refresh(); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Diferencias aplicadas al inventario'))); } } catch (error) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString().replaceFirst('Exception: ', '')))); } }

  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, dynamic>>(future: _detail, builder: (context, snapshot) {
    if (snapshot.connectionState != ConnectionState.done) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (snapshot.hasError) return Scaffold(appBar: AppBar(), body: Center(child: FilledButton(onPressed: _refresh, child: const Text('Reintentar'))));
    final data = snapshot.data ?? {}; final session = data['session'] is Map ? Map<String, dynamic>.from(data['session'] as Map) : widget.session; final lines = data['lines'] is List ? (data['lines'] as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : <Map<String, dynamic>>[]; final counting = session['status'] == 'counting'; final reveal = data['expected_visible'] == true;
    return Scaffold(appBar: AppBar(title: Text('${session['code']} · ${session['name']}')), body: RefreshIndicator(onRefresh: _refresh, child: ListView(padding: const EdgeInsets.all(16), children: [
      Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(_status(session['status']), style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)), Text(reveal ? 'Las diferencias se muestran para revisión.' : 'Conteo ciego activo: el stock esperado se revelará al enviar la toma.'), const SizedBox(height: 10), if (counting) Wrap(spacing: 8, runSpacing: 8, children: [FilledButton.icon(onPressed: _scan, icon: const Icon(Icons.qr_code_scanner), label: const Text('Escanear')), OutlinedButton.icon(onPressed: _manualCode, icon: const Icon(Icons.keyboard), label: const Text('Ingresar código')), OutlinedButton.icon(onPressed: lines.isEmpty ? null : _submit, icon: const Icon(Icons.send_outlined), label: const Text('Enviar a revisión'))]), if (widget.canApply && session['status'] == 'review') FilledButton.icon(onPressed: _apply, icon: const Icon(Icons.verified_outlined), label: const Text('Aplicar diferencias'))]))),
      const SizedBox(height: 14), Text('Productos contados (${lines.length})', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
      ...lines.map((line) { final product = line['product'] is Map ? Map<String, dynamic>.from(line['product'] as Map) : <String, dynamic>{}; return Card(child: ListTile(title: Text(product['name']?.toString() ?? 'Producto'), subtitle: Text('${product['sku'] ?? 'Sin código'} · Contado: ${_qtyText(line['counted_quantity'])}${reveal ? ' · Sistema: ${_qtyText(line['expected_quantity'])} · Dif: ${_qtyText(line['difference_quantity'])}' : ''}'), trailing: Icon(line['difference_quantity'] == null || line['difference_quantity'] == 0 ? Icons.check_circle_outline : Icons.warning_amber_outlined))); }),
    ])));
  });
}

class _BarcodeScanner extends StatefulWidget { const _BarcodeScanner({required this.api, required this.sessionId}); final ApiClient api; final int sessionId; @override State<_BarcodeScanner> createState() => _BarcodeScannerState(); }
class _BarcodeScannerState extends State<_BarcodeScanner> { final _controller = MobileScannerController(); bool _found = false; @override void dispose() { _controller.dispose(); super.dispose(); } @override Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Escanear código de barras')), body: MobileScanner(controller: _controller, onDetect: (capture) async { if (_found || capture.barcodes.isEmpty) return; final code = capture.barcodes.first.rawValue?.trim(); if (code == null || code.isEmpty) return; _found = true; await _controller.stop(); if (!mounted) return; await Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => _CountBarcode(api: widget.api, sessionId: widget.sessionId, barcode: code))); })); }

class _CountBarcode extends StatefulWidget { const _CountBarcode({required this.api, required this.sessionId, required this.barcode}); final ApiClient api; final int sessionId; final String barcode; @override State<_CountBarcode> createState() => _CountBarcodeState(); }
class _CountBarcodeState extends State<_CountBarcode> { late Future<Map<String, dynamic>> _lookup; @override void initState() { super.initState(); _lookup = _load(); } Future<Map<String, dynamic>> _load() async { final raw = await widget.api.get('/api/v1/inventory-counts/${widget.sessionId}/lookup?barcode=${Uri.encodeQueryComponent(widget.barcode)}'); return raw is Map ? Map<String, dynamic>.from(raw) : {}; }
  Future<void> _count(Map<String, dynamic> product) async { final quantity = TextEditingController(); try { final value = await showDialog<String>(context: context, builder: (context) => AlertDialog(title: Text(product['name'].toString()), content: TextField(controller: quantity, autofocus: true, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Cantidad física contada')), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')), FilledButton(onPressed: () => Navigator.pop(context, quantity.text.trim()), child: const Text('Guardar conteo'))])); final counted = double.tryParse(value ?? ''); if (counted == null || counted < 0) return; await widget.api.putJson('/api/v1/inventory-counts/${widget.sessionId}/lines', {'product_id': product['id'], 'counted_quantity': counted}); if (mounted) Navigator.pop(context); } catch (error) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString().replaceFirst('Exception: ', '')))); } finally { quantity.dispose(); } }
  Future<void> _createMissing() async {
    final fields = <String, TextEditingController>{
      for (final key in ['name', 'quantity', 'manufacturer', 'oem_number', 'equivalent_codes', 'technical_specs', 'sae_grade', 'api_spec', 'acea_spec', 'oem_approvals', 'data_source_url']) key: TextEditingController(),
    };
    var productType = 'Filtro';
    try {
      final data = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, update) => AlertDialog(
            title: const Text('Producto no registrado'),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Align(alignment: Alignment.centerLeft, child: Text('Código escaneado: ${widget.barcode}')),
                  const SizedBox(height: 12),
                  TextField(controller: fields['name'], autofocus: true, decoration: const InputDecoration(labelText: 'Nombre del producto *')),
                  TextField(controller: fields['quantity'], keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Cantidad física *')),
                  DropdownButtonFormField<String>(
                    initialValue: productType,
                    decoration: const InputDecoration(labelText: 'Tipo técnico'),
                    items: const [
                      DropdownMenuItem(value: 'Filtro', child: Text('Filtro')),
                      DropdownMenuItem(value: 'Aceite motor', child: Text('Aceite de motor')),
                      DropdownMenuItem(value: 'Lubricante transmisión', child: Text('Lubricante de transmisión / tracción')),
                      DropdownMenuItem(value: 'Refrigerante', child: Text('Refrigerante')),
                      DropdownMenuItem(value: 'Repuesto', child: Text('Repuesto / otro')),
                    ],
                    onChanged: (value) => update(() => productType = value ?? productType),
                  ),
                  TextField(controller: fields['manufacturer'], decoration: const InputDecoration(labelText: 'Marca / fabricante')),
                  TextField(controller: fields['oem_number'], decoration: const InputDecoration(labelText: 'Número OEM')),
                  TextField(controller: fields['equivalent_codes'], decoration: const InputDecoration(labelText: 'Equivalencias (separadas por coma)')),
                  TextField(controller: fields['technical_specs'], maxLines: 2, decoration: const InputDecoration(labelText: 'Medidas o especificaciones técnicas')),
                  if (productType.contains('Aceite') || productType.contains('Lubricante')) ...[
                    TextField(controller: fields['sae_grade'], decoration: const InputDecoration(labelText: 'Viscosidad SAE (ej.: 5W-30)')),
                    TextField(controller: fields['api_spec'], decoration: const InputDecoration(labelText: 'Norma API')),
                    TextField(controller: fields['acea_spec'], decoration: const InputDecoration(labelText: 'Norma ACEA')),
                    TextField(controller: fields['oem_approvals'], decoration: const InputDecoration(labelText: 'Homologaciones OEM')),
                  ],
                  TextField(controller: fields['data_source_url'], decoration: const InputDecoration(labelText: 'Enlace a ficha técnica / fuente')),
                  const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: Text('La ficha quedará pendiente de validación. No se asumirá compatibilidad con vehículos hasta verificarla.', style: TextStyle(fontSize: 12)),
                  ),
                ]),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
              FilledButton(
                onPressed: () => Navigator.pop(context, {
                  'name': fields['name']!.text.trim(),
                  'counted_quantity': double.tryParse(fields['quantity']!.text.replaceAll(',', '.')) ?? -1,
                  'manufacturer': fields['manufacturer']!.text.trim(),
                  'product_type': productType,
                  'category': productType.startsWith('Filtro') ? 'Filtros' : productType.contains('Aceite') || productType.contains('Lubricante') ? 'Lubricantes' : 'Repuestos',
                  'oem_number': fields['oem_number']!.text.trim(),
                  'equivalent_codes': fields['equivalent_codes']!.text.trim(),
                  'technical_specs': fields['technical_specs']!.text.trim(),
                  'sae_grade': fields['sae_grade']!.text.trim(),
                  'api_spec': fields['api_spec']!.text.trim(),
                  'acea_spec': fields['acea_spec']!.text.trim(),
                  'oem_approvals': fields['oem_approvals']!.text.trim(),
                  'data_source_url': fields['data_source_url']!.text.trim(),
                }),
                child: const Text('Crear y contar'),
              ),
            ],
          ),
        ),
      );
      if (data == null || '${data['name']}'.length < 2 || (data['counted_quantity'] as num) < 0) return;
      await widget.api.postJson('/api/v1/inventory-counts/${widget.sessionId}/missing-product', {'barcode': widget.barcode, ...data});
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString().replaceFirst('Exception: ', ''))));
    } finally {
      for (final controller in fields.values) { controller.dispose(); }
    }
  }
  @override Widget build(BuildContext context) => FutureBuilder<Map<String, dynamic>>(future: _lookup, builder: (context, snapshot) { if (snapshot.connectionState != ConnectionState.done) return const Scaffold(body: Center(child: CircularProgressIndicator())); final product = snapshot.data?['product']; return Scaffold(appBar: AppBar(title: const Text('Resultado del escaneo')), body: Center(child: Padding(padding: const EdgeInsets.all(24), child: product is Map ? Column(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.inventory_2_outlined, size: 60), Text(product['name'].toString(), style: Theme.of(context).textTheme.headlineSmall), Text('Código: ${widget.barcode}'), const SizedBox(height: 16), FilledButton.icon(onPressed: () => _count(Map<String, dynamic>.from(product)), icon: const Icon(Icons.add_task), label: const Text('Registrar cantidad'))]) : Column(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.help_outline, size: 60), const Text('Código no registrado'), Text(widget.barcode), const SizedBox(height: 16), FilledButton.icon(onPressed: _createMissing, icon: const Icon(Icons.add_box_outlined), label: const Text('Crear producto y contar'))])))); }); }

String _status(dynamic value) => {'counting': 'En conteo', 'review': 'Pendiente de revisión', 'applied': 'Aplicada' }['$value'] ?? '$value';
