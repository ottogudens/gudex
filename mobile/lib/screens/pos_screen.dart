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
  final _checkoutKey = GlobalKey();
  final _discountController = TextEditingController(text: '0');
  final _productSearch = TextEditingController();
  final _serviceSearch = TextEditingController();
  List<Map<String, dynamic>> _products = [];
  List<Map<String, dynamic>> _services = [];
  List<Map<String, dynamic>> _customers = [];
  List<Map<String, dynamic>> _readyOrders = [];
  List<Map<String, dynamic>> _sales = [];
  final Map<int, double> _cart = {};
  final Map<int, Map<String, dynamic>> _cartProducts = {};
  Map<String, dynamic>? _selectedOrder;
  String? _paymentNotice;
  final List<Map<String, dynamic>> _serviceItems = [];
  int? _customerId;
  int? _workOrderId;
  int? _vehicleId;
  String _paymentMethod = 'cash';
  String _categoryFilter = 'Todos';
  String _serviceCategoryFilter = 'Todos';
  String _posLayout = 'compact';
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
    _serviceSearch.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        widget.api.getAll('/api/v1/products'),
        widget.api.get('/api/v1/services'),
        widget.api.getAll('/api/v1/customers'),
        widget.api.getAll('/api/v1/work-orders?status=ready'),
        widget.api.get('/api/v1/sales'),
      ]);
      if (!mounted) return;
      setState(() {
        _products = _asMaps(results[0]);
        _services = _asMaps(results[1]);
        _customers = _asMaps(results[2]);
        _readyOrders = _asMaps(results[3]);
        _sales = _asMaps(results[4]);
      });
    } catch (error) {
      if (mounted)
        setState(
          () => _error = error.toString().replaceFirst('Exception: ', ''),
        );
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
        final product = _findProduct(entry.key) ?? _cartProducts[entry.key];
        if (product == null) return total;
        return total + (entry.value * _money(product['price_clp'])).round();
      }) +
      _serviceItems.fold<int>(
        0,
        (total, item) => total + _money(item['line_total_clp']),
      ) +
      _readyOrderTotal;

  int get _discount => int.tryParse(_discountController.text.trim()) ?? 0;
  Map<String, dynamic>? get _readyOrder {
    for (final order in _readyOrders) {
      if (order['id'] == _workOrderId) return order;
    }
    return null;
  }

  int get _readyOrderTotal => _workOrderId == null
      ? 0
      : _money((_readyOrder ?? _selectedOrder)?['total_clp']);
  bool get _hasCartConflict =>
      _cart.entries.any((entry) {
        final product = _findProduct(entry.key);
        return product == null ||
            product['active'] == false ||
            entry.value > _number(product['stock_quantity']);
      }) ||
      (_workOrderId != null && _readyOrder == null);

  int get _total => (_subtotal - _discount).clamp(0, _subtotal).toInt();

  void _changeQuantity(Map<String, dynamic> product, double delta) {
    final id = product['id'] as int?;
    if (id == null) return;
    _cartProducts[id] = Map<String, dynamic>.from(product);
    final next = (_cart[id] ?? 0) + delta;
    if (next <= 0) {
      setState(() => _cart.remove(id));
    } else if (delta > 0 && next > _number(product['stock_quantity'])) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('La cantidad supera el stock disponible.'),
        ),
      );
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
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: description,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Descripción *'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: quantity,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Cantidad / horas',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: price,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Precio unitario (CLP)',
                  prefixText: '\$',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () {
                final qty = double.tryParse(
                  quantity.text.trim().replaceAll(',', '.'),
                );
                final unitPrice = int.tryParse(
                  price.text.trim().replaceAll('.', '').replaceAll(',', ''),
                );
                if (description.text.trim().isEmpty ||
                    qty == null ||
                    qty <= 0 ||
                    unitPrice == null ||
                    unitPrice < 0) return;
                Navigator.pop(context, {
                  'description': description.text.trim(),
                  'quantity': qty,
                  'unit_price_clp': unitPrice,
                  'line_total_clp': (qty * unitPrice).round(),
                });
              },
              child: const Text('Agregar'),
            ),
          ],
        ),
      );
      if (line != null && mounted) setState(() => _serviceItems.add(line));
    } finally {
      description.dispose();
      quantity.dispose();
      price.dispose();
    }
  }

  Future<void> _printSaleReceipt(Map<String, dynamic> sale) async {
    try {
      await openGudexPdf(
        widget.api,
        '/api/v1/sales/${sale['id']}/receipt.pdf',
        'Gudex-comprobante-${sale['id']}.pdf',
      );
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo abrir el comprobante: $error')),
        );
    }
  }

  bool _hasPendingCheckout(Map<String, dynamic> sale) {
    final payments = sale['payments'];
    return payments is List &&
        payments.any(
          (payment) =>
              payment is Map && payment['status'] == 'pending_external',
        );
  }

  Future<void> _cancelCheckout(Map<String, dynamic> sale) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancelar cobro de Mercado Pago'),
        content: Text(
          'La venta ${sale['receipt_code']} quedará disponible para cobrarse por otro medio. '
          'Si el cliente igual paga el enlace, ese pago quedará marcado para devolución.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Volver'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cancelar cobro'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _saving = true);
    try {
      await widget.api.post('/api/v1/sales/${sale['id']}/mercado-pago/cancel');
      await _refresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Cobro cancelado. Ya puedes registrar el pago de ${sale['receipt_code']} por otro medio.',
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'No se pudo cancelar el cobro: ${error.toString().replaceFirst('Exception: ', '')}',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _showSales() async {
    await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (context) => SizedBox(
            height: MediaQuery.sizeOf(context).height * .8,
            child: _salesPanel(inSheet: true)));
  }

  Future<void> _recoverSale(Map<String, dynamic> sale) async {
    if (_saving) return;
    final pending = _hasPendingCheckout(sale);
    final paid = _asMaps(sale['payments'])
        .where((p) => p['status'] == 'recorded')
        .fold<int>(0, (total, p) => total + _money(p['amount_clp']));
    final balance = _money(sale['total_clp']) - paid;
    if (balance <= 0 || sale['status'] != 'open') return;
    final method = await showDialog<String>(
        context: context,
        builder: (context) => SimpleDialog(
              title: Text(
                  '${sale['receipt_code']} · saldo ${_formatMoney(balance)}'),
              children: [
                if (pending)
                  SimpleDialogOption(
                      onPressed: () =>
                          Navigator.pop(context, 'mercado_pago_checkout'),
                      child: const Text('Reabrir checkout pendiente'))
                else ...[
                  for (final option in {
                    'cash': 'Registrar efectivo recibido',
                    'card': 'Registrar tarjeta cobrada',
                    'transfer': 'Registrar transferencia recibida',
                    if (paid == 0) 'mercado_pago_checkout': 'Abrir Checkout Pro'
                  }.entries)
                    SimpleDialogOption(
                        onPressed: () => Navigator.pop(context, option.key),
                        child: Text(option.value)),
                ],
                SimpleDialogOption(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Volver')),
              ],
            ));
    if (method == null || !mounted || _saving) return;
    setState(() => _saving = true);
    try {
      if (method == 'mercado_pago_checkout') {
        final checkout = await widget.api
            .post('/api/v1/sales/${sale['id']}/mercado-pago/checkout');
        final url = Uri.tryParse('${checkout['checkout_url'] ?? ''}');
        if (url == null ||
            url.scheme != 'https' ||
            !await launchUrl(url, mode: LaunchMode.platformDefault)) {
          throw Exception(
              'No se pudo abrir el enlace. El estado del pago no ha sido confirmado.');
        }
      } else {
        await widget.api.postJson('/api/v1/sales/${sale['id']}/payments',
            {'method': method, 'amount_clp': balance});
      }
      if (mounted)
        setState(() => _paymentNotice =
            'Venta ${sale['receipt_code']}: ${method == 'mercado_pago_checkout' ? 'checkout abierto; esperando confirmación del pago' : 'pago registrado'}.');
    } catch (error) {
      if (mounted)
        setState(() => _paymentNotice =
            'Venta ${sale['receipt_code']}: ${error.toString().replaceFirst('Exception: ', '')}. Actualiza y revisa su estado antes de reintentar.');
    } finally {
      if (mounted) {
        await _refresh();
        if (mounted) setState(() => _saving = false);
      }
    }
  }

  Future<void> _checkout() async {
    if (_saving || _hasCartConflict) return;
    if (_cart.isEmpty && _serviceItems.isEmpty && _workOrderId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Agrega al menos un producto o servicio a la venta.'),
        ),
      );
      return;
    }
    if (_discount < 0 || _discount > _subtotal) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('El descuento debe estar entre cero y el subtotal.'),
        ),
      );
      return;
    }
    final total = _total;
    final method = _paymentMethod;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar venta'),
        content: Text(
          method == 'mercado_pago_checkout'
              ? 'Se creará un checkout de Mercado Pago por ${_formatMoney(total)}. La venta se marcará pagada solo cuando el backend verifique la notificación.'
              : 'Se registrará la venta por ${_formatMoney(total)} y se descontarán los productos del inventario.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirmar'),
          ),
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
            final product = _products.firstWhere(
              (item) => item['id'] == entry.key,
            );
            return {
              'product_id': entry.key,
              'description': product['name'],
              'quantity': entry.value,
              'unit_price_clp': _money(product['price_clp']),
            };
          }),
          ..._serviceItems.map(
            (item) => {
              'description': item['description'],
              'quantity': item['quantity'],
              'unit_price_clp': item['unit_price_clp'],
            },
          ),
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
        _paymentNotice =
            'Venta ${sale!['receipt_code']} creada. Pago pendiente de confirmación.';
        _cart.clear();
        _cartProducts.clear();
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
          final checkout = await widget.api.post(
            '/api/v1/sales/${sale['id']}/mercado-pago/checkout',
          );
          final checkoutUrl = '${checkout['checkout_url'] ?? ''}';
          if (!checkoutUrl.startsWith('https://') ||
              !await launchUrl(
                Uri.parse(checkoutUrl),
                mode: LaunchMode.platformDefault,
              )) {
            throw Exception(
              'Venta ${sale['receipt_code']} creada. No se pudo abrir el checkout de Mercado Pago.',
            );
          }
        }
      }
      await _refresh();
      if (!mounted) return;
      final message = method == 'mercado_pago_checkout' && total > 0
          ? 'Checkout de Mercado Pago iniciado para la venta ${sale['receipt_code']}; espera la confirmación del pago.'
          : 'Venta ${sale['receipt_code']} registrada correctamente.';
      setState(() => _paymentNotice = message);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    } catch (error) {
      if (sale != null) {
        await _refresh();
        if (!mounted) return;
        setState(
          () => _paymentNotice =
              'Venta ${sale!['receipt_code']} creada. Revisa su estado en Ventas antes de volver a cobrar: ${error.toString().replaceFirst('Exception: ', '')}',
        );
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_paymentNotice!),
            duration: const Duration(seconds: 7),
          ),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.toString().replaceFirst('Exception: ', '')),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _formatMoney(int amount) => formatClp(amount);

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'No se pudo cargar el POS.\n$_error',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _refresh,
                icon: const Icon(Icons.refresh),
                label: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
    }
    final available =
        _products.where((product) => product['active'] != false).toList();
    return LayoutBuilder(
      builder: (context, constraints) {
        final desktop = constraints.maxWidth >= 920;
        return Column(
          children: [
            if (_paymentNotice != null)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Semantics(
                  liveRegion: true,
                  child: Text(_paymentNotice!),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 10),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      Icons.point_of_sale_outlined,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Punto de venta',
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        Text(
                          'Productos, servicios y cobros',
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                      tooltip: 'Ver ventas y recuperar cobro',
                      onPressed: _showSales,
                      icon: const Icon(Icons.receipt_long_outlined)),
                  IconButton(
                    tooltip: 'Actualizar datos',
                    onPressed: _refresh,
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
            ),
            Expanded(
              child: desktop
                  ? _desktopPos(available, constraints.maxHeight)
                  : RefreshIndicator(
                      onRefresh: _refresh,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                        children: [
                          _mobileCatalogs(available),
                          const SizedBox(height: 10),
                          KeyedSubtree(
                              key: _checkoutKey,
                              child: _checkoutPanel(desktop: false)),
                          const SizedBox(height: 10),
                          SizedBox(height: 320, child: _salesPanel()),
                        ],
                      ),
                    ),
            ),
            if (!desktop)
              SafeArea(
                  top: false,
                  child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: SizedBox(
                          width: double.infinity,
                          child: FilledButton.tonal(
                            onPressed: () {
                              final target = _checkoutKey.currentContext;
                              if (target != null)
                                Scrollable.ensureVisible(target,
                                    duration:
                                        const Duration(milliseconds: 250));
                            },
                            child:
                                Text('Revisar venta · ${_formatMoney(_total)}'),
                          )))),
          ],
        );
      },
    );
  }

  Widget _desktopPos(List<Map<String, dynamic>> available, double height) {
    final layout = _posLayout;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Column(
        children: [
          _layoutSelector(),
          const SizedBox(height: 8),
          Expanded(
            child: layout == 'compact'
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(flex: 3, child: _desktopCatalogs(available)),
                      const SizedBox(width: 14),
                      Expanded(flex: 2, child: _checkoutPanel(desktop: true)),
                    ],
                  )
                : layout == 'catalog'
                    ? Column(
                        children: [
                          Expanded(
                            flex: 6,
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Expanded(child: _desktopCatalogs(available)),
                                const SizedBox(width: 12),
                                Expanded(child: _checkoutPanel(desktop: true)),
                              ],
                            ),
                          ),
                          const SizedBox(height: 10),
                          SizedBox(height: 176, child: _salesPanel()),
                        ],
                      )
                    : Column(
                        children: [
                          Expanded(
                            flex: 7,
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Expanded(
                                  flex: 5,
                                  child: _desktopCatalogs(available),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  flex: 6,
                                  child: _checkoutPanel(desktop: true),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 10),
                          SizedBox(height: 116, child: _salesPanel()),
                        ],
                      ),
          ),
        ],
      ),
    );
  }

  Widget _layoutSelector() => Align(
        alignment: Alignment.centerRight,
        child: SegmentedButton<String>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(
              value: 'compact',
              icon: Icon(Icons.view_agenda_outlined),
              label: Text('Compacta'),
            ),
            ButtonSegment(
              value: 'catalog',
              icon: Icon(Icons.grid_view_outlined),
              label: Text('Catálogo'),
            ),
            ButtonSegment(
              value: 'checkout',
              icon: Icon(Icons.point_of_sale_outlined),
              label: Text('Cobro'),
            ),
          ],
          selected: {_posLayout},
          onSelectionChanged: (value) =>
              setState(() => _posLayout = value.first),
        ),
      );

  Widget _desktopCatalogs(List<Map<String, dynamic>> available) => Column(
        children: [
          Expanded(child: _catalogPanel(available, desktop: true)),
          const SizedBox(height: 10),
          Expanded(child: _serviceCatalogPanel(desktop: true)),
        ],
      );

  Widget _mobileCatalogs(List<Map<String, dynamic>> available) => Column(
        children: [
          SizedBox(height: 360, child: _catalogPanel(available, desktop: true)),
          const SizedBox(height: 10),
          SizedBox(height: 360, child: _serviceCatalogPanel(desktop: true)),
        ],
      );

  Widget _serviceCatalogPanel({required bool desktop}) {
    final categories = <String>{
      'Todos',
      ..._services.map(
        (service) => service['category']?.toString() ?? 'Sin categoría',
      ),
    }.toList();
    final query = _serviceSearch.text.trim().toLowerCase();
    final filtered = _services.where((service) {
      final category = service['category']?.toString() ?? 'Sin categoría';
      return (_serviceCategoryFilter == 'Todos' ||
              category == _serviceCategoryFilter) &&
          (query.isEmpty ||
              '${service['name']} ${service['code']} $category'
                  .toLowerCase()
                  .contains(query));
    }).toList();
    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.tertiaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.build_circle_outlined,
                    color: Theme.of(context).colorScheme.onTertiaryContainer,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Servicios',
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        '${filtered.length} servicios disponibles',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Limpiar búsqueda de servicios',
                  onPressed: _serviceSearch.text.isEmpty
                      ? null
                      : () {
                          _serviceSearch.clear();
                          setState(() {});
                        },
                  icon: const Icon(Icons.backspace_outlined),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _serviceSearch,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                labelText: 'Buscar servicio, código o categoría',
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
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
                    selected: _serviceCategoryFilter == category,
                    onSelected: (_) =>
                        setState(() => _serviceCategoryFilter = category),
                  );
                },
              ),
            ),
            const SizedBox(height: 4),
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Text(
                        _services.isEmpty
                            ? 'No hay servicios en el catálogo.'
                            : 'No se encontraron servicios.',
                      ),
                    )
                  : ListView.separated(
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) =>
                          _serviceTile(filtered[index]),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _serviceTile(Map<String, dynamic> service) {
    final id = service['id'];
    final price = _money(service['price_clp']);
    final alreadyAdded = _serviceItems.any((item) => item['service_id'] == id);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: CircleAvatar(
        backgroundColor: Theme.of(context).colorScheme.tertiaryContainer,
        child: Icon(
          Icons.handyman_outlined,
          color: Theme.of(context).colorScheme.onTertiaryContainer,
        ),
      ),
      title: Text(
        service['name']?.toString() ?? 'Servicio',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        '${service['category'] ?? 'Servicio'} · ${service['code']}  ·  ${_formatMoney(price)}',
      ),
      trailing: FilledButton.tonalIcon(
        onPressed: alreadyAdded
            ? null
            : () => setState(
                  () => _serviceItems.add({
                    'service_id': id,
                    'description': service['name'],
                    'quantity': 1.0,
                    'unit_price_clp': price,
                    'line_total_clp': price,
                  }),
                ),
        icon: Icon(alreadyAdded ? Icons.check : Icons.add),
        label: Text(alreadyAdded ? 'Agregado' : 'Agregar'),
      ),
    );
  }

  Widget _catalogPanel(
    List<Map<String, dynamic>> available, {
    required bool desktop,
  }) {
    final query = _productSearch.text.trim().toLowerCase();
    final categories = <String>{
      'Todos',
      ...available.map(
        (product) => product['category']?.toString() ?? 'Sin categoría',
      ),
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
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Catálogo',
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${filtered.length} productos disponibles',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Limpiar búsqueda',
                  onPressed: _productSearch.text.isEmpty
                      ? null
                      : () {
                          _productSearch.clear();
                          setState(() {});
                        },
                  icon: const Icon(Icons.backspace_outlined),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _productSearch,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                labelText: 'Buscar producto, SKU o categoría',
                isDense: true,
                suffixText: '⌘K',
              ),
            ),
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
                        setState(() => _categoryFilter = category),
                  );
                },
              ),
            ),
            const SizedBox(height: 6),
            if (filtered.isEmpty)
              if (desktop)
                Expanded(
                  child: Center(
                    child: Text(
                      available.isEmpty
                          ? 'No hay productos disponibles.'
                          : 'No hay resultados para esa búsqueda.',
                    ),
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text(
                      available.isEmpty
                          ? 'No hay productos disponibles.'
                          : 'No hay resultados para esa búsqueda.',
                    ),
                  ),
                )
            else if (desktop)
              Expanded(
                child: ListView.separated(
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) =>
                      _productTile(filtered[index]),
                ),
              )
            else
              ...filtered.map(_productTile),
          ],
        ),
      ),
    );
  }

  Widget _checkoutButton() => SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: _saving ||
                  _hasCartConflict ||
                  (_cart.isEmpty &&
                      _serviceItems.isEmpty &&
                      _workOrderId == null)
              ? null
              : _checkout,
          icon: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.lock_outline),
          label: Text(
            _saving ? 'Guardando…' : 'Cobrar ${_formatMoney(_total)}',
          ),
        ),
      );

  Widget _checkoutPanel({required bool desktop}) {
    final content = SingleChildScrollView(
      padding: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Venta actual',
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        '${_cart.length + _serviceItems.length} líneas · ${_formatMoney(_subtotal)}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                ),
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
                            }),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (desktop)
              SizedBox(
                height: 112,
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    if (_cart.isEmpty && _serviceItems.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 20),
                        child: Text(
                          'Agrega productos o servicios para comenzar.',
                        ),
                      ),
                    ..._cart.entries.map(_cartTile),
                    ..._serviceItems.asMap().entries.map(
                          (entry) => ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(entry.value['description'] as String),
                            subtitle: Text(
                              'Servicio · ${entry.value['quantity']} × ${_formatMoney(_money(entry.value['unit_price_clp']))}',
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  _formatMoney(
                                    _money(entry.value['line_total_clp']),
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Quitar servicio',
                                  onPressed: () => setState(
                                    () => _serviceItems.removeAt(entry.key),
                                  ),
                                  icon: const Icon(Icons.close),
                                ),
                              ],
                            ),
                          ),
                        ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: _addServiceLine,
                        icon: const Icon(Icons.build_outlined),
                        label: const Text('Agregar servicio / trabajo'),
                      ),
                    ),
                  ],
                ),
              )
            else ...[
              if (_cart.isEmpty && _serviceItems.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Text('Agrega productos o servicios para comenzar.'),
                ),
              ..._cart.entries.map(_cartTile),
              ..._serviceItems.asMap().entries.map(
                    (entry) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(entry.value['description'] as String),
                      subtitle: Text(
                        'Servicio · ${entry.value['quantity']} × ${_formatMoney(_money(entry.value['unit_price_clp']))}',
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_formatMoney(
                              _money(entry.value['line_total_clp']))),
                          IconButton(
                            tooltip: 'Quitar servicio',
                            onPressed: () => setState(
                                () => _serviceItems.removeAt(entry.key)),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                    ),
                  ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _addServiceLine,
                  icon: const Icon(Icons.build_outlined),
                  label: const Text('Agregar servicio / trabajo'),
                ),
              ),
            ],
            const SizedBox(height: 8),
            DropdownButtonFormField<int?>(
              isExpanded: true,
              key: ValueKey('customer-$_customerId'),
              initialValue: _customers.any((c) => c['id'] == _customerId)
                  ? _customerId
                  : null,
              decoration: const InputDecoration(
                labelText: 'Cliente (opcional)',
                isDense: true,
              ),
              items: [
                const DropdownMenuItem<int?>(
                  value: null,
                  child: Text('Venta sin cliente'),
                ),
                ..._customers.map(
                  (customer) => DropdownMenuItem<int?>(
                    value: customer['id'] as int?,
                    child: Text('${customer['full_name']}'),
                  ),
                ),
              ],
              onChanged: (value) => setState(() => _customerId = value),
            ),
            if (_readyOrders.isNotEmpty) ...[
              const SizedBox(height: 10),
              DropdownButtonFormField<int?>(
                isExpanded: true,
                key: ValueKey('order-$_workOrderId-${_readyOrder != null}'),
                initialValue: _readyOrder == null ? null : _workOrderId,
                decoration: const InputDecoration(
                  labelText: 'Orden lista para pago',
                  isDense: true,
                  prefixIcon: Icon(Icons.assignment_turned_in_outlined),
                ),
                items: [
                  const DropdownMenuItem<int?>(
                    value: null,
                    child: Text('Sin orden de trabajo'),
                  ),
                  ..._readyOrders.map(
                    (order) => DropdownMenuItem<int?>(
                      value: order['id'] as int?,
                      child: Text(
                        '${order['code']} · ${_formatMoney(_money(order['total_clp']))}',
                      ),
                    ),
                  ),
                ],
                onChanged: (value) {
                  final order = value == null
                      ? null
                      : _readyOrders.firstWhere((item) => item['id'] == value);
                  setState(() {
                    _workOrderId = value;
                    _selectedOrder = order;
                    _customerId = order?['customer_id'] as int? ?? _customerId;
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
                isDense: true,
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: _paymentMethod,
              decoration: const InputDecoration(
                labelText: 'Medio de pago',
                isDense: true,
              ),
              items: const [
                DropdownMenuItem(value: 'cash', child: Text('Efectivo')),
                DropdownMenuItem(
                  value: 'card',
                  child: Text('Tarjeta / Mercado Pago Point'),
                ),
                DropdownMenuItem(
                  value: 'transfer',
                  child: Text('Transferencia'),
                ),
                DropdownMenuItem(
                  value: 'mercado_pago_checkout',
                  child: Text('Mercado Pago Checkout Pro'),
                ),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _paymentMethod = value);
              },
            ),
            const Divider(height: 22),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Total a cobrar',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color:
                              Theme.of(context).colorScheme.onPrimaryContainer,
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _formatMoney(_total),
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color:
                              Theme.of(context).colorScheme.onPrimaryContainer,
                        ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            _totalRow('Subtotal', _subtotal),
            _totalRow('Descuento', _discount.clamp(0, _subtotal).toInt()),
            _totalRow('Total', _total, emphasize: true),
            if (_hasCartConflict)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'Revisa la venta: hay productos sin stock suficiente o una orden que ya no está lista para pago. Ajusta o quita las líneas indicadas.',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (_workOrderId != null && _readyOrder == null)
              TextButton(
                onPressed: () => setState(() {
                  _workOrderId = null;
                  _selectedOrder = null;
                  _vehicleId = null;
                }),
                child: const Text('Quitar orden no disponible'),
              ),
            const SizedBox(height: 10),
            if (!desktop) _checkoutButton(),
          ],
        ),
      ),
    );

    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: desktop
          ? Column(children: [
              Expanded(child: content),
              const Divider(height: 1),
              Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    if (_hasCartConflict)
                      Text('Revisa las líneas marcadas antes de cobrar.',
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.error)),
                    _checkoutButton(),
                  ])),
            ])
          : content,
    );
  }

  Widget _salesPanel({bool inSheet = false}) => Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Ventas recientes',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Expanded(
                child: _sales.isEmpty
                    ? const Center(child: Text('Todavía no hay ventas.'))
                    : ListView.separated(
                        itemCount: _sales.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final sale = _sales[index];
                          return ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(
                              Icons.receipt_long_outlined,
                              color: GudexColors.primary,
                            ),
                            title: Text(
                              '${sale['receipt_code']} · ${_formatMoney(_money(sale['total_clp']))}',
                            ),
                            subtitle: Text(
                              'Estado: ${spanishStatus(sale['status'])}${_hasPendingCheckout(sale) ? ' · Cobro Mercado Pago pendiente' : ''} · ${sale['created_at'] ?? ''}',
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (sale['status'] == 'open')
                                  IconButton(
                                      tooltip: 'Continuar cobro',
                                      icon: const Icon(Icons.payments_outlined),
                                      onPressed: _saving
                                          ? null
                                          : () {
                                              if (inSheet)
                                                Navigator.pop(context);
                                              _recoverSale(sale);
                                            }),
                                if (_hasPendingCheckout(sale))
                                  IconButton(
                                    tooltip: 'Cancelar cobro de Mercado Pago',
                                    icon: const Icon(Icons.cancel_outlined),
                                    color: Theme.of(context).colorScheme.error,
                                    onPressed: _saving
                                        ? null
                                        : () => _cancelCheckout(sale),
                                  ),
                                IconButton(
                                  tooltip: 'Abrir comprobante PDF',
                                  icon:
                                      const Icon(Icons.picture_as_pdf_outlined),
                                  onPressed: () => _printSaleReceipt(sale),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      );

  Widget _productTile(Map<String, dynamic> product) {
    final id = product['id'] as int?;
    final stock = _number(product['stock_quantity']);
    final quantity = id == null ? 0 : (_cart[id] ?? 0);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
        child: Icon(
          Icons.inventory_2_outlined,
          color: Theme.of(context).colorScheme.onSecondaryContainer,
        ),
      ),
      title: Text(
        '${product['name'] ?? 'Producto'}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          'Stock ${stock.toStringAsFixed(stock % 1 == 0 ? 0 : 2)} ${product['unit'] ?? ''}  ·  ${_formatMoney(_money(product['price_clp']))}',
        ),
      ),
      trailing: stock <= 0
          ? const Chip(label: Text('Sin stock'))
          : FilledButton.tonalIcon(
              onPressed: () => _changeQuantity(product, 1),
              icon: Icon(quantity == 0 ? Icons.add_shopping_cart : Icons.add),
              label: Text(
                quantity == 0
                    ? 'Agregar'
                    : quantity.toStringAsFixed(quantity % 1 == 0 ? 0 : 2),
              ),
            ),
    );
  }

  Widget _cartTile(MapEntry<int, double> entry) {
    final available = _findProduct(entry.key);
    final product = available ??
        _cartProducts[entry.key] ??
        {'id': entry.key, 'name': 'Producto #${entry.key}', 'price_clp': 0};
    final conflict =
        available == null || entry.value > _number(available['stock_quantity']);
    final lineTotal = (entry.value * _money(product['price_clp'])).round();
    return Row(
      children: [
        Expanded(
          child: Text(
            '${product['name']} × ${entry.value.toStringAsFixed(entry.value % 1 == 0 ? 0 : 2)}${conflict ? ' · Revisar stock' : ''}',
          ),
        ),
        IconButton(
          onPressed: () => _changeQuantity(product, -1),
          icon: const Icon(Icons.remove_circle_outline),
          tooltip: 'Quitar una unidad',
        ),
        Flexible(child: Text(_formatMoney(lineTotal))),
        IconButton(
          onPressed: () => setState(() => _cart.remove(entry.key)),
          tooltip: 'Quitar producto',
          icon: const Icon(Icons.close),
        ),
      ],
    );
  }

  Widget _totalRow(String label, int value, {bool emphasize = false}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: emphasize
                  ? const TextStyle(fontWeight: FontWeight.bold)
                  : null,
            ),
            Text(
              _formatMoney(value),
              style: emphasize
                  ? Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold)
                  : null,
            ),
          ],
        ),
      );
}
