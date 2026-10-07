import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/constants.dart';
import '../services/api_client.dart';

class PosScreen extends StatefulWidget {
  const PosScreen({required this.api, super.key});
  final ApiClient api;

  @override
  State<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends State<PosScreen> {
  final _discountController = TextEditingController(text: '0');
  final _productSearch = TextEditingController();
  List<Map<String, dynamic>> _products = [];
  List<Map<String, dynamic>> _customers = [];
  List<Map<String, dynamic>> _readyOrders = [];
  List<Map<String, dynamic>> _sales = [];
  final Map<int, double> _cart = {};
  final List<Map<String, dynamic>> _serviceItems = [];
  int? _customerId;
  int? _workOrderId;
  int? _vehicleId;
  String _paymentMethod = 'cash';
  String _categoryFilter = 'Todos';
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _discountController.dispose();
    _productSearch.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        widget.api.get('/api/v1/products'),
        widget.api.get('/api/v1/customers'),
        widget.api.get('/api/v1/work-orders?status=ready'),
        widget.api.get('/api/v1/sales'),
      ]);
      if (!mounted) return;
      setState(() {
        _products = _asMaps(results[0]);
        _customers = _asMaps(results[1]);
        _readyOrders = _asMaps(results[2]);
        _sales = _asMaps(results[3]);
        _cart.removeWhere((id, quantity) {
          final product = _findProduct(id);
          return product == null ||
              quantity > _number(product['stock_quantity']);
        });
      });
    } catch (error) {
      if (mounted)
        setState(
            () => _error = error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> _asMaps(dynamic value) => value is List
      ? value
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList()
      : <Map<String, dynamic>>[];

  Map<String, dynamic>? _findProduct(int id) {
    for (final product in _products) {
      if (product['id'] == id) return product;
    }
    return null;
  }

  double _number(dynamic value) =>
      value is num ? value.toDouble() : double.tryParse('$value') ?? 0;
  int _money(dynamic value) =>
      value is num ? value.round() : int.tryParse('$value') ?? 0;

  int get _subtotal =>
      _cart.entries.fold(0, (total, entry) {
        final product = _findProduct(entry.key);
        if (product == null) return total;
        return total + (entry.value * _money(product['price_clp'])).round();
      }) +
      _serviceItems.fold<int>(
          0, (total, item) => total + _money(item['line_total_clp'])) +
      _readyOrderTotal;

  int get _discount => int.tryParse(_discountController.text.trim()) ?? 0;
  int get _readyOrderTotal => _workOrderId == null
      ? 0
      : _money(_readyOrders
          .firstWhere((order) => order['id'] == _workOrderId)['total_clp']);
  int get _total => (_subtotal - _discount).clamp(0, _subtotal).toInt();

  void _changeQuantity(Map<String, dynamic> product, double delta) {
    final id = product['id'] as int?;
    if (id == null) return;
    final next = (_cart[id] ?? 0) + delta;
    if (next <= 0) {
      setState(() => _cart.remove(id));
    } else if (next > _number(product['stock_quantity'])) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('La cantidad supera el stock disponible.')));
    } else {
      setState(() => _cart[id] = next);
    }
  }

  Future<void> _addServiceLine() async {
    final description = TextEditingController();
    final quantity = TextEditingController(text: '1');
    final price = TextEditingController();
    try {
      final line = await showDialog<Map<String, dynamic>>(
          context: context,
          builder: (context) => AlertDialog(
                title: const Text('Agregar servicio o trabajo'),
                content: Column(mainAxisSize: MainAxisSize.min, children: [
                  TextField(
                      controller: description,
                      autofocus: true,
                      decoration:
                          const InputDecoration(labelText: 'Descripción *')),
                  const SizedBox(height: 10),
                  TextField(
                      controller: quantity,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration:
                          const InputDecoration(labelText: 'Cantidad / horas')),
                  const SizedBox(height: 10),
                  TextField(
                      controller: price,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                          labelText: 'Precio unitario (CLP)',
                          prefixText: '\$')),
                ]),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancelar')),
                  FilledButton(
                      onPressed: () {
                        final qty = double.tryParse(
                            quantity.text.trim().replaceAll(',', '.'));
                        final unitPrice = int.tryParse(price.text
                            .trim()
                            .replaceAll('.', '')
                            .replaceAll(',', ''));
                        if (description.text.trim().isEmpty ||
                            qty == null ||
                            qty <= 0 ||
                            unitPrice == null ||
                            unitPrice < 0) return;
                        Navigator.pop(context, {
                          'description': description.text.trim(),
                          'quantity': qty,
                          'unit_price_clp': unitPrice,
                          'line_total_clp': (qty * unitPrice).round()
                        });
                      },
                      child: const Text('Agregar')),
                ],
              ));
      if (line != null && mounted) setState(() => _serviceItems.add(line));
    } finally {
      description.dispose();
      quantity.dispose();
      price.dispose();
    }
  }

  Future<void> _printSaleReceipt(Map<String, dynamic> sale) async {
    try {
      await openGudexPdf(widget.api, '/api/v1/sales/${sale['id']}/receipt.pdf',
          'Gudex-comprobante-${sale['id']}.pdf');
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('No se pudo abrir el comprobante: $error')));
    }
  }

  bool _hasPendingCheckout(Map<String, dynamic> sale) {
    final payments = sale['payments'];
    return payments is List &&
        payments.any((payment) =>
            payment is Map && payment['status'] == 'pending_external');
  }

  Future<void> _cancelCheckout(Map<String, dynamic> sale) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancelar cobro de Mercado Pago'),
        content: Text(
            'La venta ${sale['receipt_code']} quedará disponible para cobrarse por otro medio. '
            'Si el cliente igual paga el enlace, ese pago quedará marcado para devolución.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Volver')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Cancelar cobro')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _saving = true);
    try {
      await widget.api.post('/api/v1/sales/${sale['id']}/mercado-pago/cancel');
      await _refresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                'Cobro cancelado. Ya puedes registrar el pago de ${sale['receipt_code']} por otro medio.')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                'No se pudo cancelar el cobro: ${error.toString().replaceFirst('Exception: ', '')}')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _checkout() async {
    if (_cart.isEmpty && _serviceItems.isEmpty && _workOrderId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Agrega al menos un producto o servicio a la venta.')));
      return;
    }
    if (_discount < 0 || _discount > _subtotal) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('El descuento debe estar entre cero y el subtotal.')));
      return;
    }
    final total = _total;
    final method = _paymentMethod;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar venta'),
        content: Text(method == 'mercado_pago_checkout'
            ? 'Se creará un checkout de Mercado Pago por ${_formatMoney(total)}. La venta se marcará pagada solo cuando el backend verifique la notificación.'
            : 'Se registrará la venta por ${_formatMoney(total)} y se descontarán los productos del inventario.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Confirmar')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _saving = true);
    Map<String, dynamic>? sale;
    try {
      final result = await widget.api.postJson('/api/v1/sales', {
        if (_customerId != null) 'customer_id': _customerId,
        if (_vehicleId != null) 'vehicle_id': _vehicleId,
        if (_workOrderId != null) 'work_order_id': _workOrderId,
        'discount_clp': _discount,
        'lines': [
          ..._cart.entries.map((entry) {
            final product =
                _products.firstWhere((item) => item['id'] == entry.key);
            return {
              'product_id': entry.key,
              'description': product['name'],
              'quantity': entry.value,
              'unit_price_clp': _money(product['price_clp']),
            };
          }),
          ..._serviceItems.map((item) => {
                'description': item['description'],
                'quantity': item['quantity'],
                'unit_price_clp': item['unit_price_clp'],
              }),
          if (_workOrderId != null)
            {
              'description': 'Orden de trabajo #$_workOrderId',
              'quantity': 1,
              'unit_price_clp': _readyOrderTotal,
            },
        ],
      });
      sale = Map<String, dynamic>.from(result as Map);
      setState(() {
        _cart.clear();
        _serviceItems.clear();
        _discountController.text = '0';
        _workOrderId = null;
        _vehicleId = null;
      });

      if (total > 0) {
        await widget.api.postJson('/api/v1/sales/${sale['id']}/payments', {
          'method': method,
          'amount_clp': total,
        });
        if (method == 'mercado_pago_checkout') {
          final checkout = await widget.api
              .post('/api/v1/sales/${sale['id']}/mercado-pago/checkout');
          final checkoutUrl = '${checkout['checkout_url'] ?? ''}';
          if (!checkoutUrl.startsWith('https://') ||
              !await launchUrl(Uri.parse(checkoutUrl),
                  mode: LaunchMode.platformDefault)) {
            throw Exception(
                'Venta ${sale['receipt_code']} creada. No se pudo abrir el checkout de Mercado Pago.');
          }
        }
      }
      await _refresh();
      if (!mounted) return;
      final message = method == 'mercado_pago_checkout' && total > 0
          ? 'Checkout de Mercado Pago iniciado para la venta ${sale['receipt_code']}; espera la confirmación del pago.'
          : 'Venta ${sale['receipt_code']} registrada correctamente.';
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    } catch (error) {
      if (sale != null) {
        await _refresh();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'Venta ${sale['receipt_code']} creada, pero no se pudo registrar el pago: ${error.toString().replaceFirst('Exception: ', '')}'),
          duration: const Duration(seconds: 7),
        ));
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(error.toString().replaceFirst('Exception: ', ''))));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _formatMoney(int amount) => '\$${amount.toString()} CLP';

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
          child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('No se pudo cargar el POS.\n$_error',
              textAlign: TextAlign.center),
          const SizedBox(height: 12),
          OutlinedButton.icon(
              onPressed: _refresh,
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar')),
        ]),
      ));
    }
    final available =
        _products.where((product) => product['active'] != false).toList();
    return LayoutBuilder(builder: (context, constraints) {
      final desktop = constraints.maxWidth >= 920;
      return Column(children: [
        Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 10),
            child: Row(children: [
              Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(14)),
                  child: Icon(Icons.point_of_sale_outlined,
                      color: Theme.of(context).colorScheme.onPrimaryContainer)),
              const SizedBox(width: 12),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text('Punto de venta',
                        style: Theme.of(context)
                            .textTheme
                            .headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w800)),
                    Text('Productos, servicios y cobros',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant)),
                  ])),
              IconButton(
                  tooltip: 'Actualizar datos',
                  onPressed: _refresh,
                  icon: const Icon(Icons.refresh)),
            ])),
        Expanded(
            child: desktop
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: Column(children: [
                      Expanded(
                          child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                            Expanded(
                                flex: 6,
                                child: _catalogPanel(available, desktop: true)),
                            const SizedBox(width: 14),
                            Expanded(
                                flex: 5, child: _checkoutPanel(desktop: true)),
                          ])),
                      const SizedBox(height: 10),
                      SizedBox(height: 156, child: _salesPanel()),
                    ]))
                : RefreshIndicator(
                    onRefresh: _refresh,
                    child: ListView(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                        children: [
                          _catalogPanel(available, desktop: false),
                          const SizedBox(height: 10),
                          _checkoutPanel(desktop: false),
                          const SizedBox(height: 10),
                          SizedBox(height: 320, child: _salesPanel()),
                        ]))),
      ]);
    });
  }

  Widget _catalogPanel(List<Map<String, dynamic>> available,
      {required bool desktop}) {
    final query = _productSearch.text.trim().toLowerCase();
    final categories = <String>{
      'Todos',
      ...available
          .map((product) => product['category']?.toString() ?? 'Sin categoría')
    }.toList();
    final filtered = available.where((product) {
      final category = product['category']?.toString() ?? 'Sin categoría';
      final matchesCategory =
          _categoryFilter == 'Todos' || category == _categoryFilter;
      final matchesSearch = query.isEmpty ||
          '${product['name']} ${product['sku'] ?? ''} $category'
              .toLowerCase()
              .contains(query);
      return matchesCategory && matchesSearch;
    }).toList();
    return Card(
        child: Padding(
            padding: const EdgeInsets.all(16),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text('Catálogo',
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text('${filtered.length} productos disponibles',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant)),
                    ])),
                IconButton(
                    tooltip: 'Limpiar búsqueda',
                    onPressed: _productSearch.text.isEmpty
                        ? null
                        : () {
                            _productSearch.clear();
                            setState(() {});
                          },
                    icon: const Icon(Icons.backspace_outlined))
              ]),
              const SizedBox(height: 10),
              TextField(
                  controller: _productSearch,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search),
                      labelText: 'Buscar producto, SKU o categoría',
                      isDense: true,
                      suffixText: '⌘K')),
              const SizedBox(height: 10),
              SizedBox(
                  height: 38,
                  child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: categories.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 6),
                      itemBuilder: (_, index) {
                        final category = categories[index];
                        return ChoiceChip(
                            label: Text(category),
                            selected: _categoryFilter == category,
                            onSelected: (_) =>
                                setState(() => _categoryFilter = category));
                      })),
              const SizedBox(height: 6),
              if (filtered.isEmpty)
                if (desktop)
                  Expanded(
                      child: Center(
                          child: Text(available.isEmpty
                              ? 'No hay productos disponibles.'
                              : 'No hay resultados para esa búsqueda.')))
                else
                  Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                          child: Text(available.isEmpty
                              ? 'No hay productos disponibles.'
                              : 'No hay resultados para esa búsqueda.')))
              else if (desktop)
                Expanded(
                    child: ListView.separated(
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) =>
                            _productTile(filtered[index])))
              else
                ...filtered.map(_productTile),
            ])));
  }

  Widget _checkoutPanel({required bool desktop}) => Card(
      child: SingleChildScrollView(
          padding: EdgeInsets.zero,
          child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            Text('Venta actual',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleLarge
                                    ?.copyWith(fontWeight: FontWeight.w700)),
                            Text(
                                '${_cart.length + _serviceItems.length} líneas · ${_formatMoney(_subtotal)}',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant))
                          ])),
                      if (_cart.isNotEmpty || _serviceItems.isNotEmpty)
                        IconButton(
                            tooltip: 'Vaciar venta',
                            icon: const Icon(Icons.delete_sweep_outlined),
                            onPressed: _saving
                                ? null
                                : () => setState(() {
                                      _cart.clear();
                                      _serviceItems.clear();
                                      _discountController.text = '0';
                                    }))
                    ]),
                    const SizedBox(height: 8),
                    if (desktop)
                      SizedBox(
                          height: 112,
                          child: ListView(padding: EdgeInsets.zero, children: [
                            if (_cart.isEmpty && _serviceItems.isEmpty)
                              const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 20),
                                  child: Text(
                                      'Agrega productos o servicios para comenzar.')),
                            ..._cart.entries.map(_cartTile),
                            ..._serviceItems
                                .asMap()
                                .entries
                                .map((entry) => ListTile(
                                      contentPadding: EdgeInsets.zero,
                                      title: Text(
                                          entry.value['description'] as String),
                                      subtitle: Text(
                                          'Servicio · ${entry.value['quantity']} × ${_formatMoney(_money(entry.value['unit_price_clp']))}'),
                                      trailing: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(_formatMoney(_money(entry
                                                .value['line_total_clp']))),
                                            IconButton(
                                                tooltip: 'Quitar servicio',
                                                onPressed: () => setState(() =>
                                                    _serviceItems
                                                        .removeAt(entry.key)),
                                                icon: const Icon(Icons.close))
                                          ]),
                                    )),
                            Align(
                                alignment: Alignment.centerLeft,
                                child: TextButton.icon(
                                    onPressed: _addServiceLine,
                                    icon: const Icon(Icons.build_outlined),
                                    label: const Text(
                                        'Agregar servicio / trabajo'))),
                          ]))
                    else ...[
                      if (_cart.isEmpty && _serviceItems.isEmpty)
                        const Padding(
                            padding: EdgeInsets.symmetric(vertical: 20),
                            child: Text(
                                'Agrega productos o servicios para comenzar.')),
                      ..._cart.entries.map(_cartTile),
                      ..._serviceItems.asMap().entries.map((entry) => ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(entry.value['description'] as String),
                            subtitle: Text(
                                'Servicio · ${entry.value['quantity']} × ${_formatMoney(_money(entry.value['unit_price_clp']))}'),
                            trailing:
                                Row(mainAxisSize: MainAxisSize.min, children: [
                              Text(_formatMoney(
                                  _money(entry.value['line_total_clp']))),
                              IconButton(
                                  tooltip: 'Quitar servicio',
                                  onPressed: () => setState(
                                      () => _serviceItems.removeAt(entry.key)),
                                  icon: const Icon(Icons.close))
                            ]),
                          )),
                      Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                              onPressed: _addServiceLine,
                              icon: const Icon(Icons.build_outlined),
                              label: const Text('Agregar servicio / trabajo'))),
                    ],
                    const SizedBox(height: 8),
                    DropdownButtonFormField<int?>(
                      initialValue: _customerId,
                      decoration: const InputDecoration(
                          labelText: 'Cliente (opcional)', isDense: true),
                      items: [
                        const DropdownMenuItem<int?>(
                            value: null, child: Text('Venta sin cliente')),
                        ..._customers.map((customer) => DropdownMenuItem<int?>(
                            value: customer['id'] as int?,
                            child: Text('${customer['full_name']}')))
                      ],
                      onChanged: (value) => setState(() => _customerId = value),
                    ),
                    if (_readyOrders.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      DropdownButtonFormField<int?>(
                        initialValue: _workOrderId,
                        decoration: const InputDecoration(
                            labelText: 'Orden lista para pago',
                            isDense: true,
                            prefixIcon:
                                Icon(Icons.assignment_turned_in_outlined)),
                        items: [
                          const DropdownMenuItem<int?>(
                              value: null, child: Text('Sin orden de trabajo')),
                          ..._readyOrders.map((order) => DropdownMenuItem<int?>(
                              value: order['id'] as int?,
                              child: Text(
                                  '${order['code']} · ${_formatMoney(_money(order['total_clp']))}'))),
                        ],
                        onChanged: (value) {
                          final order = value == null
                              ? null
                              : _readyOrders
                                  .firstWhere((item) => item['id'] == value);
                          setState(() {
                            _workOrderId = value;
                            _customerId =
                                order?['customer_id'] as int? ?? _customerId;
                            _vehicleId = order?['vehicle_id'] as int?;
                          });
                        },
                      ),
                    ],
                    const SizedBox(height: 10),
                    TextField(
                        controller: _discountController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                            labelText: 'Descuento (CLP)',
                            prefixText: '\$',
                            isDense: true),
                        onChanged: (_) => setState(() {})),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      initialValue: _paymentMethod,
                      decoration: const InputDecoration(
                          labelText: 'Medio de pago', isDense: true),
                      items: const [
                        DropdownMenuItem(
                            value: 'cash', child: Text('Efectivo')),
                        DropdownMenuItem(
                            value: 'card',
                            child: Text('Tarjeta / Mercado Pago Point')),
                        DropdownMenuItem(
                            value: 'transfer', child: Text('Transferencia')),
                        DropdownMenuItem(
                            value: 'mercado_pago_checkout',
                            child: Text('Mercado Pago Checkout Pro')),
                      ],
                      onChanged: (value) {
                        if (value != null)
                          setState(() => _paymentMethod = value);
                      },
                    ),
                    const Divider(height: 22),
                    Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                            color:
                                Theme.of(context).colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(14)),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Total a cobrar',
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelLarge
                                      ?.copyWith(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onPrimaryContainer)),
                              const SizedBox(height: 2),
                              Text(_formatMoney(_total),
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineSmall
                                      ?.copyWith(
                                          fontWeight: FontWeight.w800,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onPrimaryContainer)),
                            ])),
                    const SizedBox(height: 8),
                    _totalRow('Subtotal', _subtotal),
                    _totalRow(
                        'Descuento', _discount.clamp(0, _subtotal).toInt()),
                    _totalRow('Total', _total, emphasize: true),
                    const SizedBox(height: 10),
                    SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                            onPressed: _saving ||
                                    (_cart.isEmpty &&
                                        _serviceItems.isEmpty &&
                                        _workOrderId == null)
                                ? null
                                : _checkout,
                            icon: _saving
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2))
                                : const Icon(Icons.lock_outline),
                            label: Text(_saving
                                ? 'Guardando…'
                                : 'Cobrar ${_formatMoney(_total)}'))),
                  ]))));

  Widget _salesPanel() => Card(
      child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Ventas recientes',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Expanded(
                child: _sales.isEmpty
                    ? const Center(child: Text('Todavía no hay ventas.'))
                    : ListView.separated(
                        itemCount: _sales.length.clamp(0, 10).toInt(),
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final sale = _sales[index];
                          return ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.receipt_long_outlined,
                                color: GudexColors.primary),
                            title: Text(
                                '${sale['receipt_code']} · ${_formatMoney(_money(sale['total_clp']))}'),
                            subtitle: Text(
                                'Estado: ${spanishStatus(sale['status'])}${_hasPendingCheckout(sale) ? ' · Cobro Mercado Pago pendiente' : ''} · ${sale['created_at'] ?? ''}'),
                            trailing:
                                Row(mainAxisSize: MainAxisSize.min, children: [
                              if (_hasPendingCheckout(sale))
                                IconButton(
                                    tooltip: 'Cancelar cobro de Mercado Pago',
                                    icon: const Icon(Icons.cancel_outlined),
                                    color: Theme.of(context).colorScheme.error,
                                    onPressed: _saving
                                        ? null
                                        : () => _cancelCheckout(sale)),
                              IconButton(
                                  tooltip: 'Abrir comprobante PDF',
                                  icon:
                                      const Icon(Icons.picture_as_pdf_outlined),
                                  onPressed: () => _printSaleReceipt(sale)),
                            ]),
                          );
                        },
                      )),
          ])));

  Widget _productTile(Map<String, dynamic> product) {
    final id = product['id'] as int?;
    final stock = _number(product['stock_quantity']);
    final quantity = id == null ? 0 : (_cart[id] ?? 0);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
          backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
          child: Icon(Icons.inventory_2_outlined,
              color: Theme.of(context).colorScheme.onSecondaryContainer)),
      title: Text('${product['name'] ?? 'Producto'}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
              'Stock ${stock.toStringAsFixed(stock % 1 == 0 ? 0 : 2)} ${product['unit'] ?? ''}  ·  ${_formatMoney(_money(product['price_clp']))}')),
      trailing: stock <= 0
          ? const Chip(label: Text('Sin stock'))
          : FilledButton.tonalIcon(
              onPressed: () => _changeQuantity(product, 1),
              icon: Icon(quantity == 0 ? Icons.add_shopping_cart : Icons.add),
              label: Text(quantity == 0
                  ? 'Agregar'
                  : quantity.toStringAsFixed(quantity % 1 == 0 ? 0 : 2))),
    );
  }

  Widget _cartTile(MapEntry<int, double> entry) {
    final product = _products.firstWhere((item) => item['id'] == entry.key);
    final lineTotal = (entry.value * _money(product['price_clp'])).round();
    return Row(children: [
      Expanded(
          child: Text(
              '${product['name']} × ${entry.value.toStringAsFixed(entry.value % 1 == 0 ? 0 : 2)}')),
      IconButton(
          onPressed: () => _changeQuantity(product, -1),
          icon: const Icon(Icons.remove_circle_outline),
          tooltip: 'Quitar una unidad'),
      Text(_formatMoney(lineTotal)),
    ]);
  }

  Widget _totalRow(String label, int value, {bool emphasize = false}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child:
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(label,
              style: emphasize
                  ? const TextStyle(fontWeight: FontWeight.bold)
                  : null),
          Text(_formatMoney(value),
              style: emphasize
                  ? Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold)
                  : null),
        ]),
      );
}
