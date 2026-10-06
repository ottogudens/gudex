import 'package:flutter/material.dart';

import '../core/constants.dart';
import '../services/api_client.dart';

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({required this.api, required this.canManage, this.onCreateSocialPost, super.key});
  final ApiClient api;
  final bool canManage;
  final void Function(Map<String, dynamic>)? onCreateSocialPost;

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  final _search = TextEditingController();
  List<Map<String, dynamic>> _products = [];
  bool _loading = true;
  bool _lowStockOnly = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (!mounted) return;
    setState(() { _loading = true; _error = null; });
    try {
      final result = await widget.api.get('/api/v1/products');
      if (!mounted) return;
      setState(() => _products = result is List
          ? result.whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList()
          : <Map<String, dynamic>>[]);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  double _quantity(dynamic value) => value is num ? value.toDouble() : double.tryParse('$value') ?? 0;
  int _amount(dynamic value) => value is num ? value.round() : int.tryParse('$value') ?? 0;
  String _qtyText(double value) => value.toStringAsFixed(value % 1 == 0 ? 0 : 2);

  List<Map<String, dynamic>> get _visibleProducts {
    final query = _search.text.trim().toLowerCase();
    return _products.where((product) {
      final low = _quantity(product['stock_quantity']) <= _quantity(product['minimum_quantity']);
      final matchesSearch = query.isEmpty || '${product['name']} ${product['sku'] ?? ''} ${product['category'] ?? ''}'.toLowerCase().contains(query);
      return matchesSearch && (!_lowStockOnly || low);
    }).toList();
  }

  Future<void> _createProduct() async {
    final form = GlobalKey<FormState>();
    final sku = TextEditingController();
    final name = TextEditingController();
    final category = TextEditingController();
    final unit = TextEditingController(text: 'unidad');
    final stock = TextEditingController(text: '0');
    final minimum = TextEditingController(text: '0');
    final cost = TextEditingController(text: '0');
    final price = TextEditingController(text: '0');
    try {
      final data = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Agregar producto'),
          content: Form(key: form, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextFormField(controller: name, decoration: const InputDecoration(labelText: 'Nombre *'), validator: (v) => (v == null || v.trim().isEmpty) ? 'Campo obligatorio' : null),
            const SizedBox(height: 10),
            TextFormField(controller: sku, decoration: const InputDecoration(labelText: 'SKU / código (opcional)')),
            const SizedBox(height: 10),
            TextFormField(controller: category, decoration: const InputDecoration(labelText: 'Categoría')),
            const SizedBox(height: 10),
            TextFormField(controller: unit, decoration: const InputDecoration(labelText: 'Unidad (unidad, litro, etc.)'), validator: (v) => (v == null || v.trim().isEmpty) ? 'Campo obligatorio' : null),
            const SizedBox(height: 10),
            TextFormField(controller: stock, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Stock inicial'), validator: _validQuantity),
            const SizedBox(height: 10),
            TextFormField(controller: minimum, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Alerta de stock mínimo'), validator: _validQuantity),
            const SizedBox(height: 10),
            TextFormField(controller: cost, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Costo unitario (CLP)'), validator: _validMoney),
            const SizedBox(height: 10),
            TextFormField(controller: price, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Precio de venta (CLP)'), validator: _validMoney),
          ]))),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
            FilledButton(onPressed: () {
              if (!form.currentState!.validate()) return;
              Navigator.pop(context, {
                'name': name.text.trim(),
                'unit': unit.text.trim(),
                'stock_quantity': double.parse(stock.text.trim().replaceAll(',', '.')),
                'minimum_quantity': double.parse(minimum.text.trim().replaceAll(',', '.')),
                'cost_clp': int.parse(cost.text.trim()),
                'price_clp': int.parse(price.text.trim()),
                if (sku.text.trim().isNotEmpty) 'sku': sku.text.trim(),
                if (category.text.trim().isNotEmpty) 'category': category.text.trim(),
              });
            }, child: const Text('Guardar producto')),
          ],
        ),
      );
      if (data == null) return;
      try {
        await widget.api.postJson('/api/v1/products', data);
        await _refresh();
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Producto agregado al inventario')));
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
      }
    } finally {
      sku.dispose(); name.dispose(); category.dispose(); unit.dispose(); stock.dispose(); minimum.dispose(); cost.dispose(); price.dispose();
    }
  }

  String? _validQuantity(String? value) {
    final quantity = double.tryParse((value ?? '').trim().replaceAll(',', '.'));
    return quantity == null || !quantity.isFinite || quantity < 0 ? 'Ingresa una cantidad igual o mayor que cero' : null;
  }

  String? _validMoney(String? value) {
    final amount = int.tryParse((value ?? '').trim());
    return amount == null || amount < 0 ? 'Ingresa un monto CLP válido' : null;
  }

  Future<void> _adjustStock(Map<String, dynamic> product) async {
    final form = GlobalKey<FormState>();
    final quantity = TextEditingController();
    final reason = TextEditingController();
    String movement = 'in';
    try {
      final data = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (context) => StatefulBuilder(builder: (context, updateDialog) => AlertDialog(
          title: Text('Ajustar stock · ${product['name']}'),
          content: Form(key: form, child: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<String>(
              initialValue: movement,
              decoration: const InputDecoration(labelText: 'Movimiento'),
              items: const [
                DropdownMenuItem(value: 'in', child: Text('Ingreso / recepción')),
                DropdownMenuItem(value: 'out', child: Text('Salida / merma')),
              ],
              onChanged: (value) { if (value != null) updateDialog(() => movement = value); },
            ),
            const SizedBox(height: 12),
            TextFormField(controller: quantity, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: 'Cantidad (${product['unit'] ?? 'unidad'})'), validator: (value) {
              final parsed = double.tryParse((value ?? '').trim().replaceAll(',', '.'));
              return parsed == null || !parsed.isFinite || parsed <= 0 ? 'Ingresa una cantidad mayor que cero' : null;
            }),
            const SizedBox(height: 12),
            TextFormField(controller: reason, decoration: const InputDecoration(labelText: 'Motivo *'), validator: (value) => (value == null || value.trim().length < 3) ? 'Describe el motivo del movimiento' : null),
          ])),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
            FilledButton(onPressed: () {
              if (!form.currentState!.validate()) return;
              final parsed = double.parse(quantity.text.trim().replaceAll(',', '.'));
              Navigator.pop(context, {
                'quantity_change': movement == 'in' ? parsed : -parsed,
                'reason': reason.text.trim(),
              });
            }, child: const Text('Registrar movimiento')),
          ],
        )),
      );
      if (data == null) return;
      await widget.api.postJson('/api/v1/products/${product['id']}/stock-movements', data);
      await _refresh();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Movimiento de stock registrado')));
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString().replaceFirst('Exception: ', ''))));
    } finally {
      quantity.dispose(); reason.dispose();
    }
  }

  Future<void> _showMovements(Map<String, dynamic> product) async {
    try {
      final result = await widget.api.get('/api/v1/products/${product['id']}/stock-movements');
      if (!mounted) return;
      final movements = result is List
          ? result.whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList()
          : <Map<String, dynamic>>[];
      await showModalBottomSheet<void>(
        context: context,
        useSafeArea: true,
        builder: (context) => Padding(
          padding: const EdgeInsets.all(16),
          child: ListView(shrinkWrap: true, children: [
            Text('Movimientos · ${product['name']}', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            if (movements.isEmpty) const Text('Todavía no hay movimientos para este producto.'),
            ...movements.take(50).map((movement) {
              final delta = _quantity(movement['quantity_change']);
              final date = DateTime.tryParse('${movement['created_at'] ?? ''}');
              final dateText = date == null ? '' : '${date.toLocal()}'.split('.').first;
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(delta >= 0 ? Icons.arrow_downward : Icons.arrow_upward, color: delta >= 0 ? GudexColors.success : Theme.of(context).colorScheme.error),
                title: Text('${delta >= 0 ? '+' : ''}${_qtyText(delta)} ${product['unit'] ?? 'unidad'} · ${movement['reason'] ?? 'movimiento'}'),
                subtitle: Text([dateText, movement['reference']].where((value) => value != null && '$value'.isNotEmpty).join(' · ')),
              );
            }),
          ]),
        ),
      );
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString().replaceFirst('Exception: ', ''))));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
      Text('No se pudo cargar el inventario.\n$_error', textAlign: TextAlign.center),
      const SizedBox(height: 12),
      OutlinedButton.icon(onPressed: _refresh, icon: const Icon(Icons.refresh), label: const Text('Reintentar')),
    ])));

    final visible = _visibleProducts;
    return Stack(children: [
      Column(children: [
        Padding(padding: const EdgeInsets.fromLTRB(12, 8, 12, 4), child: TextField(
          controller: _search,
          decoration: InputDecoration(labelText: 'Buscar producto', prefixIcon: const Icon(Icons.search), suffixIcon: IconButton(onPressed: () { _search.clear(); setState(() {}); }, icon: const Icon(Icons.clear))),
          onChanged: (_) => setState(() {}),
        )),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Mostrar solo stock bajo'),
          value: _lowStockOnly,
          onChanged: (value) => setState(() => _lowStockOnly = value),
        )),
        Expanded(child: visible.isEmpty
            ? RefreshIndicator(onRefresh: _refresh, child: ListView(children: [SizedBox(height: 280, child: Center(child: Text(_products.isEmpty ? 'No hay productos registrados.' : 'No hay productos que coincidan.')))]))
            : RefreshIndicator(onRefresh: _refresh, child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 2, 12, 88),
                itemCount: visible.length,
                itemBuilder: (context, index) => _productCard(visible[index]),
              ))),
      ]),
      if (widget.canManage) Positioned(right: 18, bottom: 18, child: FloatingActionButton.extended(
        onPressed: _createProduct,
        icon: const Icon(Icons.add),
        label: const Text('Nuevo producto'),
      )),
    ]);
  }

  Widget _productCard(Map<String, dynamic> product) {
    final stock = _quantity(product['stock_quantity']);
    final minimum = _quantity(product['minimum_quantity']);
    final low = stock <= minimum;
    return Card(child: ListTile(
      leading: CircleAvatar(
        backgroundColor: low ? Theme.of(context).colorScheme.errorContainer : Theme.of(context).colorScheme.secondaryContainer,
        child: Icon(low ? Icons.warning_amber_outlined : Icons.inventory_2_outlined),
      ),
      title: Text('${product['name'] ?? 'Producto'}'),
      subtitle: Text('${product['sku'] == null ? '' : '${product['sku']} · '}${product['category'] == null ? '' : '${product['category']} · '}Stock ${_qtyText(stock)} ${product['unit'] ?? 'unidad'} (mín. ${_qtyText(minimum)})\nCosto ${_amount(product['cost_clp'])} · Venta ${_amount(product['price_clp'])} CLP${low ? ' · STOCK BAJO' : ''}'),
      isThreeLine: true,
      trailing: widget.canManage ? Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(onPressed: () => _adjustStock(product), icon: const Icon(Icons.tune), tooltip: 'Ajustar stock'),
        PopupMenuButton<String>(
          tooltip: 'Acciones del producto',
          onSelected: (value) { if (value == 'social') { widget.onCreateSocialPost?.call(product); } else if (value == 'edit') { _editProduct(product); } else { _archiveProduct(product); } },
          itemBuilder: (context) => [
            if (widget.onCreateSocialPost != null) const PopupMenuItem(value: 'social', child: Text('Crear publicación')),
            PopupMenuItem(value: 'edit', child: ListTile(leading: Icon(Icons.edit_outlined), title: Text('Editar'))),
            PopupMenuItem(value: 'archive', child: ListTile(leading: Icon(Icons.delete_outline), title: Text('Archivar'))),
          ],
        ),
      ]) : null,
      onTap: () => _showMovements(product),
    ));
  }

  Future<void> _editProduct(Map<String, dynamic> product) async {
    final form = GlobalKey<FormState>();
    final name = TextEditingController(text: product['name']?.toString() ?? '');
    final sku = TextEditingController(text: product['sku']?.toString() ?? '');
    final category = TextEditingController(text: product['category']?.toString() ?? '');
    final unit = TextEditingController(text: product['unit']?.toString() ?? 'unidad');
    final minimum = TextEditingController(text: _quantity(product['minimum_quantity']).toString());
    final cost = TextEditingController(text: _amount(product['cost_clp']).toString());
    final price = TextEditingController(text: _amount(product['price_clp']).toString());
    try {
      final data = await showDialog<Map<String, dynamic>>(context: context, builder: (context) => AlertDialog(
        title: const Text('Editar producto'),
        content: Form(key: form, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextFormField(controller: name, decoration: const InputDecoration(labelText: 'Nombre *'), validator: (v) => v == null || v.trim().isEmpty ? 'Ingresa el nombre' : null),
          const SizedBox(height: 10), TextFormField(controller: sku, decoration: const InputDecoration(labelText: 'SKU')),
          const SizedBox(height: 10), TextFormField(controller: category, decoration: const InputDecoration(labelText: 'Categoría')),
          const SizedBox(height: 10), TextFormField(controller: unit, decoration: const InputDecoration(labelText: 'Unidad *'), validator: (v) => v == null || v.trim().isEmpty ? 'Ingresa la unidad' : null),
          const SizedBox(height: 10), TextFormField(controller: minimum, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Stock mínimo'), validator: _validQuantity),
          const SizedBox(height: 10), TextFormField(controller: cost, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Costo unitario (CLP)'), validator: _validMoney),
          const SizedBox(height: 10), TextFormField(controller: price, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Precio de venta (CLP)'), validator: _validMoney),
        ]))),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')), FilledButton(onPressed: () {
          if (!form.currentState!.validate()) return;
          Navigator.pop(context, {'name': name.text.trim(), 'sku': sku.text.trim(), 'category': category.text.trim(), 'unit': unit.text.trim(), 'minimum_quantity': double.parse(minimum.text.trim().replaceAll(',', '.')), 'cost_clp': int.parse(cost.text.trim()), 'price_clp': int.parse(price.text.trim())});
        }, child: const Text('Guardar cambios'))],
      ));
      if (data == null) return;
      await widget.api.patchJson('/api/v1/products/' + product['id'].toString(), data);
      await _refresh();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Producto actualizado')));
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString().replaceFirst('Exception: ', ''))));
    } finally { name.dispose(); sku.dispose(); category.dispose(); unit.dispose(); minimum.dispose(); cost.dispose(); price.dispose(); }
  }

  Future<void> _archiveProduct(Map<String, dynamic> product) async {
    final confirmed = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: const Text('Archivar producto'), content: Text('¿Archivar ${product['name']}? Ya no aparecerá en el inventario activo.'),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')), FilledButton.tonal(onPressed: () => Navigator.pop(context, true), child: const Text('Archivar'))],
    ));
    if (confirmed != true) return;
    try { await widget.api.delete('/api/v1/products/' + product['id'].toString()); await _refresh(); if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Producto archivado'))); }
    catch (error) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString().replaceFirst('Exception: ', '')))); }
  }
}
