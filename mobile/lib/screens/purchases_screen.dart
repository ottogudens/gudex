import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../core/constants.dart';
import '../services/api_client.dart';

class PurchasesScreen extends StatefulWidget {
  const PurchasesScreen({required this.api, super.key});
  final ApiClient api;

  @override
  State<PurchasesScreen> createState() => _PurchasesScreenState();
}

class _PurchasesScreenState extends State<PurchasesScreen> {
  late Future<List<dynamic>> _future;
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<dynamic>> _load() async {
    final result = await widget.api.get('/api/v1/purchases');
    return result is List ? result : const [];
  }

  Future<void> _refresh() async => setState(() => _future = _load());

  Future<void> _upload() async {
    if (_uploading) return;
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['xml', 'pdf'],
      withData: true,
    );
    if (picked == null || picked.files.single.bytes == null) return;
    setState(() => _uploading = true);
    try {
      final file = picked.files.single;
      final receipt = Map<String, dynamic>.from(await widget.api.uploadBytes(
        '/api/v1/purchases/import',
        file.bytes!,
        file.name,
        contentType: file.extension?.toLowerCase() == 'xml'
            ? 'application/xml'
            : 'application/pdf',
      ));
      if (!mounted) return;
      await _refresh();
      await _openReceipt(receipt['id'] as int);
    } catch (error) {
      if (mounted) _message(error, error: true);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  void _message(Object message, {bool error = false}) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(message.toString().replaceFirst('Exception: ', '')), backgroundColor: error ? Theme.of(context).colorScheme.error : null));

  Future<void> _newSupplier() async {
    final name = TextEditingController();
    final rut = TextEditingController();
    final email = TextEditingController();
    try {
      final data = await showDialog<Map<String, String>>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Nuevo proveedor'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: name, autofocus: true, decoration: const InputDecoration(labelText: 'Razón social / nombre *')),
            TextField(controller: rut, decoration: const InputDecoration(labelText: 'RUT')),
            TextField(controller: email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Correo')),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(context, {'name': name.text.trim(), 'rut': rut.text.trim(), 'email': email.text.trim()}), child: const Text('Guardar')),
          ],
        ),
      );
      if (data == null || data['name']!.length < 2) return;
      await widget.api.postJson('/api/v1/suppliers', data);
      if (mounted) _message('Proveedor creado');
    } catch (error) {
      if (mounted) _message(error, error: true);
    } finally {
      name.dispose(); rut.dispose(); email.dispose();
    }
  }

  Future<void> _openReceipt(int id) async {
    final result = await Navigator.push<bool>(context, MaterialPageRoute(
      builder: (_) => _PurchaseDetail(api: widget.api, receiptId: id),
    ));
    if (result == true && mounted) await _refresh();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<dynamic>>(
    future: _future,
    builder: (context, snapshot) {
      final rows = snapshot.data ?? const [];
      return Column(children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            const Icon(Icons.local_shipping_outlined, size: 32),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Compras y proveedores', style: Theme.of(context).textTheme.headlineSmall),
              const Text('Importa XML o PDF, revisa coincidencias y aplica stock de forma controlada.'),
            ])),
            OutlinedButton.icon(onPressed: _newSupplier, icon: const Icon(Icons.person_add_alt_1_outlined), label: const Text('Proveedor')),
            const SizedBox(width: 8),
            FilledButton.icon(onPressed: _uploading ? null : _upload, icon: _uploading ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.upload_file_outlined), label: Text(_uploading ? 'Procesando…' : 'Importar factura')),
          ]),
        ),
        const Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Card(child: Padding(padding: EdgeInsets.all(12), child: Text('XML DTE: detecta proveedor, folio, productos, cantidades y costos. PDF: conserva y extrae datos legibles para revisión; confirma siempre antes de aplicar inventario y caja.')))),
        if (snapshot.connectionState != ConnectionState.done) const LinearProgressIndicator(),
        Expanded(child: RefreshIndicator(
          onRefresh: _refresh,
          child: ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: rows.isEmpty ? 1 : rows.length,
            itemBuilder: (context, index) {
              if (rows.isEmpty) return const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('Aún no hay facturas de compra importadas.')));
              final row = Map<String, dynamic>.from(rows[index] as Map);
              final supplier = row['supplier'] is Map ? Map<String, dynamic>.from(row['supplier'] as Map) : null;
              final applied = row['status'] == 'applied';
              return Card(child: ListTile(
                onTap: () => _openReceipt(row['id'] as int),
                leading: Icon(applied ? Icons.inventory_2_outlined : Icons.fact_check_outlined),
                title: Text('${supplier?['name'] ?? 'Proveedor sin identificar'} · ${row['folio'] ?? row['code']}'),
                subtitle: Text('${row['source_format']?.toString().toUpperCase()} · ${applied ? 'Stock aplicado' : 'Pendiente de revisión'} · ${formatClp((row['total_amount_clp'] as num?)?.toInt() ?? 0)}'),
                trailing: const Icon(Icons.chevron_right),
              ));
            },
          ),
        )),
      ]);
    },
  );
}

class _PurchaseDetail extends StatefulWidget {
  const _PurchaseDetail({required this.api, required this.receiptId});
  final ApiClient api;
  final int receiptId;
  @override State<_PurchaseDetail> createState() => _PurchaseDetailState();
}

class _PurchaseDetailState extends State<_PurchaseDetail> {
  late Future<Map<String, dynamic>> _future;
  bool _busy = false;
  @override void initState() { super.initState(); _future = _load(); }
  Future<Map<String, dynamic>> _load() async => Map<String, dynamic>.from(await widget.api.get('/api/v1/purchases/${widget.receiptId}'));
  Future<void> _refresh() async => setState(() => _future = _load());
  void _notice(Object value, {bool error = false}) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value.toString().replaceFirst('Exception: ', '')), backgroundColor: error ? Theme.of(context).colorScheme.error : null));

  Future<void> _apply(Map<String, dynamic> receipt) async {
    setState(() => _busy = true);
    try {
      await widget.api.postJson('/api/v1/purchases/${widget.receiptId}/apply', {});
      if (!mounted) return;
      _notice('Stock actualizado y costo de compra registrado.');
      Navigator.pop(context, true);
    } catch (error) {
      if (mounted) _notice(error, error: true);
    } finally { if (mounted) setState(() => _busy = false); }
  }

  Future<void> _createProduct(Map<String, dynamic> line) async {
    try {
      await widget.api.postJson('/api/v1/purchases/${widget.receiptId}/lines/${line['id']}/create-product', {});
      if (mounted) {
        _notice('Producto creado y vinculado. Completa luego su ficha técnica.');
        await _refresh();
      }
    } catch (error) {
      if (mounted) _notice(error, error: true);
    }
  }

  @override Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Revisar compra')),
    body: FutureBuilder<Map<String, dynamic>>(
      future: _future,
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final receipt = snapshot.data!;
        final lines = receipt['lines'] is List ? receipt['lines'] as List : const [];
        final pending = receipt['status'] == 'review';
        return Column(children: [
          Padding(padding: const EdgeInsets.all(16), child: Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(receipt['supplier'] is Map ? '${receipt['supplier']['name']}' : 'Proveedor sin identificar', style: Theme.of(context).textTheme.titleLarge),
            Text('Documento ${receipt['folio'] ?? receipt['code']} · Total ${formatClp((receipt['total_amount_clp'] as num?)?.toInt() ?? 0)}'),
            if (receipt['extraction_note'] != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text('${receipt['extraction_note']}')),
          ]))),
          Expanded(child: ListView.builder(itemCount: lines.length, itemBuilder: (context, index) {
            final line = Map<String, dynamic>.from(lines[index] as Map);
            final matched = line['product_id'] != null;
            return ListTile(
              leading: Icon(matched ? Icons.link : Icons.link_off, color: matched ? Colors.green : Theme.of(context).colorScheme.error),
              title: Text('${line['description']}'),
              subtitle: Text('Código: ${line['supplier_code'] ?? 'sin código'} · ${line['quantity']} × ${formatClp((line['unit_cost_clp'] as num?)?.toInt() ?? 0)}'),
              trailing: matched ? const Text('Vinculado') : TextButton(
                onPressed: pending ? () => _createProduct(line) : null,
                child: const Text('Crear producto'),
              ),
            );
          })),
          if (pending) Padding(padding: const EdgeInsets.all(16), child: SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: _busy ? null : () => _apply(receipt), icon: const Icon(Icons.inventory_rounded), label: Text(_busy ? 'Aplicando…' : 'Aplicar productos al stock')))),
        ]);
      },
    ),
  );
}
