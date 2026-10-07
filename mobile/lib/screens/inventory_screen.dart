import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/inventory_provider.dart';
import 'widgets/inventory_editor.dart';

import '../core/constants.dart';
import '../services/api_client.dart';
import 'bulk_import_screen.dart';

class InventoryScreen extends ConsumerStatefulWidget {
  const InventoryScreen({
    required this.api,
    required this.canManage,
    this.onCreateSocialPost,
    super.key,
  });
  final ApiClient api;
  final bool canManage;
  final void Function(Map<String, dynamic>)? onCreateSocialPost;

  @override
  ConsumerState<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends ConsumerState<InventoryScreen> {
  final _search = TextEditingController();
  bool _lowStockOnly = false;

  Future<void> _refresh() async {
    try {
      ref.invalidate(inventoryProvider(widget.api));
      await ref.read(inventoryProvider(widget.api).future);
    } catch (_) {
      // The provider exposes the failure while retaining the previous data.
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  double _quantity(dynamic value) =>
      value is num ? value.toDouble() : double.tryParse('$value') ?? 0;
  int _amount(dynamic value) =>
      value is num ? value.round() : int.tryParse('$value') ?? 0;
  String _qtyText(double value) =>
      value.toStringAsFixed(value % 1 == 0 ? 0 : 2);

  List<Map<String, dynamic>> _visibleProducts(
    List<Map<String, dynamic>> products,
  ) {
    final query = _search.text.trim().toLowerCase();
    return products.where((product) {
      final low = _quantity(product['stock_quantity']) <=
          _quantity(product['minimum_quantity']);
      final matchesSearch = query.isEmpty ||
          '${product['name']} ${product['sku'] ?? ''} ${product['category'] ?? ''}'
              .toLowerCase()
              .contains(query);
      return matchesSearch && (!_lowStockOnly || low);
    }).toList();
  }

  Future<void> _editProduct([
    Map<String, dynamic>? product,
    bool stockAdjustment = false,
  ]) async {
    final saved = await showInventoryEditor(
      context,
      api: widget.api,
      product: product,
      stockAdjustment: stockAdjustment,
    );
    if (saved == true && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Cambios guardados')));
      await _refresh();
    }
  }

  Future<void> _createProduct() => _editProduct();
  Future<void> _adjustStock(Map<String, dynamic> product) =>
      _editProduct(product, true);

  Future<void> _showMovements(Map<String, dynamic> product) async {
    try {
      final result = await widget.api.get(
        '/api/v1/products/${product['id']}/stock-movements',
      );
      if (!mounted) return;
      final movements = result is List
          ? result
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList()
          : <Map<String, dynamic>>[];
      await showModalBottomSheet<void>(
        context: context,
        useSafeArea: true,
        builder: (context) => Padding(
          padding: const EdgeInsets.all(16),
          child: ListView(
            shrinkWrap: true,
            children: [
              Text(
                'Movimientos · ${product['name']}',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              if (movements.isEmpty)
                const Text('Todavía no hay movimientos para este producto.'),
              ...movements.take(50).map((movement) {
                final delta = _quantity(movement['quantity_change']);
                final date = DateTime.tryParse(
                  '${movement['created_at'] ?? ''}',
                );
                final dateText =
                    date == null ? '' : '${date.toLocal()}'.split('.').first;
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    delta >= 0 ? Icons.arrow_downward : Icons.arrow_upward,
                    color: delta >= 0
                        ? GudexColors.success
                        : Theme.of(context).colorScheme.error,
                  ),
                  title: Text(
                    '${delta >= 0 ? '+' : ''}${_qtyText(delta)} ${product['unit'] ?? 'unidad'} · ${movement['reason'] ?? 'movimiento'}',
                  ),
                  subtitle: Text(
                    [dateText, movement['reference']]
                        .where((value) => value != null && '$value'.isNotEmpty)
                        .join(' · '),
                  ),
                );
              }),
            ],
          ),
        ),
      );
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.toString().replaceFirst('Exception: ', '')),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(inventoryProvider(widget.api));
    final products = state.valueOrNull ?? <Map<String, dynamic>>[];
    final visible = _visibleProducts(products);
    return LayoutBuilder(
      builder: (context, constraints) {
        final table = constraints.maxWidth >= 960 &&
            MediaQuery.textScalerOf(context).scale(14) < 22;
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    'Inventario',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  Text('${visible.length} productos'),
                  IconButton(
                    onPressed: state.isLoading ? null : _refresh,
                    tooltip: 'Actualizar inventario',
                    icon: const Icon(Icons.refresh),
                  ),
                  if (widget.canManage) ...[
                    OutlinedButton.icon(
                      onPressed: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => BulkImportScreen(
                              api: widget.api,
                              kind: 'products',
                            ),
                          ),
                        );
                        if (mounted) await _refresh();
                      },
                      icon: const Icon(Icons.table_view_outlined),
                      label: const Text('Carga masiva'),
                    ),
                    FilledButton.icon(
                      onPressed: _createProduct,
                      icon: const Icon(Icons.add),
                      label: const Text('Nuevo producto'),
                    ),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: TextField(
                controller: _search,
                decoration: InputDecoration(
                  labelText: 'Buscar por nombre, SKU o categoría',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: IconButton(
                    tooltip: 'Limpiar búsqueda',
                    onPressed: () {
                      _search.clear();
                      setState(() {});
                    },
                    icon: const Icon(Icons.clear),
                  ),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: FilterChip(
                  label: const Text('Stock bajo'),
                  selected: _lowStockOnly,
                  onSelected: (value) => setState(() => _lowStockOnly = value),
                ),
              ),
            ),
            if (state.isLoading) const LinearProgressIndicator(),
            if (state.hasError)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    Text(
                      'No se pudo actualizar el inventario. ${state.error}',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                    if (products.isNotEmpty)
                      const Text('Se muestran los últimos datos disponibles.'),
                    OutlinedButton(
                      onPressed: state.isLoading ? null : _refresh,
                      child: const Text('Reintentar'),
                    ),
                  ],
                ),
              ),
            if (table && visible.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    const Expanded(flex: 3, child: Text('Producto / SKU')),
                    const Expanded(flex: 2, child: Text('Stock / mínimo')),
                    const Expanded(flex: 2, child: Text('Costo / venta CLP')),
                    SizedBox(
                      width: widget.canManage ? 192 : 48,
                      child: const Text('Acciones'),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _refresh,
                child: ListView.builder(
                  key: const PageStorageKey('inventory-list'),
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                  itemCount: visible.isEmpty ? 1 : visible.length,
                  itemBuilder: (context, index) => visible.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            state.isLoading
                                ? 'Cargando inventario…'
                                : state.hasError && products.isEmpty
                                    ? 'Inventario no disponible.'
                                    : products.isEmpty
                                        ? 'No hay productos registrados.'
                                        : 'No hay productos que coincidan.',
                          ),
                        )
                      : _productCard(visible[index], table: table),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _productCard(Map<String, dynamic> product, {required bool table}) {
    final stock = _quantity(product['stock_quantity']);
    final minimum = _quantity(product['minimum_quantity']);
    final low = stock <= minimum;
    final identity = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${product['name'] ?? 'Producto'}',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        Text(
          [
            product['sku'],
            product['category'],
          ].where((value) => value != null && '$value'.isNotEmpty).join(' · '),
        ),
      ],
    );
    final quantity = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${_qtyText(stock)} ${product['unit'] ?? 'unidad'} · mín. ${_qtyText(minimum)}',
        ),
        if (low)
          Text(
            '⚠ Stock bajo',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
      ],
    );
    final prices = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Costo ${formatClp(_amount(product['cost_clp']))}'),
        Text('Venta ${formatClp(_amount(product['price_clp']))}'),
      ],
    );
    final actions = Wrap(
      children: [
        IconButton(
          onPressed: () => _showMovements(product),
          tooltip: 'Ver movimientos',
          icon: const Icon(Icons.history),
        ),
        if (widget.canManage) ...[
          IconButton(
            onPressed: () => _editProduct(product),
            tooltip: 'Editar producto',
            icon: const Icon(Icons.edit_outlined),
          ),
          IconButton(
            onPressed: () => _adjustStock(product),
            tooltip: 'Ajustar stock',
            icon: const Icon(Icons.tune),
          ),
          PopupMenuButton<String>(
            tooltip: 'Más acciones',
            onSelected: (value) {
              if (value == 'social') {
                widget.onCreateSocialPost?.call(product);
              } else {
                _archiveProduct(product);
              }
            },
            itemBuilder: (_) => [
              if (widget.onCreateSocialPost != null)
                const PopupMenuItem(
                  value: 'social',
                  child: Text('Crear publicación'),
                ),
              const PopupMenuItem(value: 'archive', child: Text('Archivar')),
            ],
          ),
        ],
      ],
    );
    return Card(
      key: ValueKey(product['id']),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: table
            ? Row(
                children: [
                  Expanded(flex: 3, child: identity),
                  Expanded(flex: 2, child: quantity),
                  Expanded(flex: 2, child: prices),
                  SizedBox(width: widget.canManage ? 192 : 48, child: actions),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  identity,
                  const SizedBox(height: 12),
                  quantity,
                  const SizedBox(height: 8),
                  prices,
                  const Divider(),
                  actions,
                ],
              ),
      ),
    );
  }

  Future<void> _archiveProduct(Map<String, dynamic> product) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Archivar producto'),
        content: Text(
          '¿Archivar ${product['name']}? Ya no aparecerá en el inventario activo.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Archivar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.api.delete('/api/v1/products/' + product['id'].toString());
      await _refresh();
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Producto archivado')));
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.toString().replaceFirst('Exception: ', '')),
          ),
        );
    }
  }
}
