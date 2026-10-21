import 'package:flutter/material.dart';

import '../services/api_client.dart';

class CashboxScreen extends StatefulWidget {
  const CashboxScreen({required this.api, super.key});
  final ApiClient api;

  @override
  State<CashboxScreen> createState() => _CashboxScreenState();
}

class _CashboxScreenState extends State<CashboxScreen> {
  late Future<_CashboxData> _data;

  @override
  void initState() {
    super.initState();
    _data = _load();
  }

  Future<_CashboxData> _load() async {
    final loaded = await Future.wait([
      widget.api.get('/api/v1/cash/summary'),
      widget.api.get('/api/v1/cash/movements?limit=80'),
      widget.api.get('/api/v1/cash/accounts'),
    ]);
    return _CashboxData(
      loaded[0] is Map ? Map<String, dynamic>.from(loaded[0] as Map) : {},
      _maps(loaded[1]),
      _maps(loaded[2]),
    );
  }

  List<Map<String, dynamic>> _maps(dynamic raw) => raw is List
      ? raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
      : [];

  Future<void> _refresh() async {
    setState(() => _data = _load());
    await _data;
  }

  int _amount(String text) => int.tryParse(text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
  String _money(dynamic value) =>
      '\$${(value is num ? value.toInt() : int.tryParse('$value') ?? 0).toString().replaceAllMapped(RegExp(r'(?=(\d{3})+(?!\d))'), (m) => '.')}';

  Future<void> _addExpense(List<Map<String, dynamic>> accounts) async {
    if (accounts.isEmpty) return;
    int accountId = accounts.first['id'] as int;
    final amount = TextEditingController();
    final category = TextEditingController(text: 'Gasto operativo');
    final note = TextEditingController();
    final supplier = TextEditingController();
    try {
      final accepted = await showDialog<bool>(context: context, builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('Registrar egreso'),
          content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<int>(initialValue: accountId, decoration: const InputDecoration(labelText: 'Sale desde'), items: accounts.map((a) => DropdownMenuItem(value: a['id'] as int, child: Text(a['name'].toString()))).toList(), onChanged: (value) => update(() => accountId = value ?? accountId)),
            const SizedBox(height: 10), TextField(controller: amount, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Monto (CLP)')),
            const SizedBox(height: 10), TextField(controller: category, decoration: const InputDecoration(labelText: 'Categoría')),
            const SizedBox(height: 10), TextField(controller: note, maxLines: 2, decoration: const InputDecoration(labelText: 'Detalle del gasto')),
            const SizedBox(height: 10), TextField(controller: supplier, decoration: const InputDecoration(labelText: 'Proveedor / destinatario (opcional)')),
          ])),
          actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Registrar egreso'))],
        ),
      ));
      if (accepted != true || _amount(amount.text) <= 0 || note.text.trim().length < 2) return;
      await widget.api.postJson('/api/v1/cash/expenses', {'account_id': accountId, 'amount_clp': _amount(amount.text), 'category': category.text.trim(), 'note': note.text.trim(), if (supplier.text.trim().isNotEmpty) 'counterparty': supplier.text.trim()});
      if (mounted) await _refresh();
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString().replaceFirst('Exception: ', ''))));
    } finally { amount.dispose(); category.dispose(); note.dispose(); supplier.dispose(); }
  }

  Future<void> _transfer(List<Map<String, dynamic>> accounts) async {
    if (accounts.length < 2) return;
    int from = accounts.first['id'] as int;
    int to = accounts[1]['id'] as int;
    final amount = TextEditingController();
    final note = TextEditingController();
    try {
      final accepted = await showDialog<bool>(context: context, builder: (context) => StatefulBuilder(builder: (context, update) => AlertDialog(
        title: const Text('Transferencia interna'),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          DropdownButtonFormField<int>(initialValue: from, decoration: const InputDecoration(labelText: 'Desde'), items: accounts.map((a) => DropdownMenuItem(value: a['id'] as int, child: Text(a['name'].toString()))).toList(), onChanged: (value) => update(() => from = value ?? from)),
          const SizedBox(height: 10), DropdownButtonFormField<int>(initialValue: to, decoration: const InputDecoration(labelText: 'Hacia'), items: accounts.map((a) => DropdownMenuItem(value: a['id'] as int, child: Text(a['name'].toString()))).toList(), onChanged: (value) => update(() => to = value ?? to)),
          const SizedBox(height: 10), TextField(controller: amount, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Monto (CLP)')),
          const SizedBox(height: 10), TextField(controller: note, decoration: const InputDecoration(labelText: 'Motivo (opcional)')),
        ])),
        actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Transferir'))],
      )));
      if (accepted != true || from == to || _amount(amount.text) <= 0) return;
      await widget.api.postJson('/api/v1/cash/transfers', {'from_account_id': from, 'to_account_id': to, 'amount_clp': _amount(amount.text), 'note': note.text.trim()});
      if (mounted) await _refresh();
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString().replaceFirst('Exception: ', ''))));
    } finally { amount.dispose(); note.dispose(); }
  }

  Future<void> _openShift(List<Map<String, dynamic>> accounts) async {
    if (accounts.isEmpty) return;
    int accountId = accounts.first['id'] as int;
    final opening = TextEditingController(text: '0');
    try {
      final accepted = await showDialog<bool>(context: context, builder: (context) => StatefulBuilder(builder: (context, update) => AlertDialog(
        title: const Text('Abrir turno de caja'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          DropdownButtonFormField<int>(initialValue: accountId, decoration: const InputDecoration(labelText: 'Caja o cuenta'), items: accounts.map((a) => DropdownMenuItem(value: a['id'] as int, child: Text(a['name'].toString()))).toList(), onChanged: (value) => update(() => accountId = value ?? accountId)),
          const SizedBox(height: 10), TextField(controller: opening, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Monto de apertura (CLP)')),
        ]),
        actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Abrir turno'))],
      )));
      if (accepted != true || _amount(opening.text) < 0) return;
      await widget.api.postJson('/api/v1/cash/closures/open', {'account_id': accountId, 'opening_amount_clp': _amount(opening.text)});
      if (mounted) await _refresh();
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString().replaceFirst('Exception: ', ''))));
    } finally { opening.dispose(); }
  }

  Future<void> _closeShift(Map<String, dynamic> closure) async {
    final count = TextEditingController();
    try {
      final accepted = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
        title: const Text('Cerrar turno de caja'),
        content: TextField(controller: count, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Efectivo o saldo contado (CLP)')),
        actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Cerrar y comparar'))],
      ));
      if (accepted != true || _amount(count.text) < 0) return;
      await widget.api.postJson('/api/v1/cash/closures/${closure['id']}/close', {'closing_amount_clp': _amount(count.text)});
      if (mounted) await _refresh();
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString().replaceFirst('Exception: ', ''))));
    } finally { count.dispose(); }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<_CashboxData>(
    future: _data,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
      if (snapshot.hasError) return Center(child: FilledButton.icon(onPressed: _refresh, icon: const Icon(Icons.refresh), label: const Text('Reintentar cargar caja')));
      final data = snapshot.data!;
      final summary = data.summary;
      final accounts = data.accounts;
      final accountRows = _maps(summary['accounts']);
      final openClosures = _maps(summary['open_closures']);
      return RefreshIndicator(onRefresh: _refresh, child: ListView(padding: const EdgeInsets.fromLTRB(18, 18, 18, 32), children: [
        Row(children: [
          const Icon(Icons.account_balance_wallet_outlined, size: 34), const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Caja central', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)), const Text('Todos los cobros, egresos y transferencias en un solo libro.')]))
        ]),
        const SizedBox(height: 18),
        Wrap(spacing: 12, runSpacing: 12, children: [
          _Metric(label: 'Ingresos', value: _money(summary['income_clp']), color: Colors.green),
          _Metric(label: 'Egresos', value: _money(summary['expense_clp']), color: Colors.red),
          _Metric(label: 'Flujo neto', value: _money(summary['net_clp']), color: Theme.of(context).colorScheme.primary),
        ]),
        const SizedBox(height: 18),
        Wrap(spacing: 10, runSpacing: 10, children: [
          FilledButton.icon(onPressed: () => _addExpense(accounts), icon: const Icon(Icons.remove_circle_outline), label: const Text('Registrar egreso')),
          OutlinedButton.icon(onPressed: () => _transfer(accounts), icon: const Icon(Icons.swap_horiz), label: const Text('Transferir entre cuentas')),
          OutlinedButton.icon(onPressed: () => _openShift(accounts), icon: const Icon(Icons.lock_open_outlined), label: const Text('Abrir turno')),
          OutlinedButton.icon(onPressed: _refresh, icon: const Icon(Icons.refresh), label: const Text('Actualizar')),
        ]),
        if (openClosures.isNotEmpty) ...[
          const SizedBox(height: 12),
          Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Turnos de caja abiertos', style: TextStyle(fontWeight: FontWeight.w800)),
            ...openClosures.map((closure) => ListTile(contentPadding: EdgeInsets.zero, title: Text('Caja #${closure['account_id']} · apertura ${_money(closure['opening_amount_clp'])}'), trailing: FilledButton.tonal(onPressed: () => _closeShift(closure), child: const Text('Cerrar')))),
          ]))),
        ],
        const SizedBox(height: 22), Text('Saldos por caja y cuenta', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        ...accountRows.map((row) => Card(child: ListTile(leading: const Icon(Icons.account_balance_outlined), title: Text((row['account'] is Map ? row['account']['name'] : 'Cuenta').toString()), subtitle: Text('Entradas ${_money(row['incoming_clp'])} · Salidas ${_money(row['outgoing_clp'])}'), trailing: Text(_money(row['balance_clp']), style: const TextStyle(fontWeight: FontWeight.w800))))),
        const SizedBox(height: 22), Text('Últimos movimientos', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        if (data.movements.isEmpty) const Card(child: Padding(padding: EdgeInsets.all(18), child: Text('Aún no hay movimientos. Los cobros de ventas confirmados aparecerán automáticamente aquí.'))),
        ...data.movements.map((row) {
          final outgoing = {'expense', 'transfer_out', 'reversal'}.contains(row['direction']);
          return Card(child: ListTile(leading: CircleAvatar(backgroundColor: (outgoing ? Colors.red : Colors.green).withValues(alpha: .12), child: Icon(outgoing ? Icons.arrow_upward : Icons.arrow_downward, color: outgoing ? Colors.red : Colors.green)), title: Text('${row['category'] ?? 'Movimiento'} · ${row['account_name'] ?? ''}'), subtitle: Text('${row['note'] ?? ''}${row['reference'] == null ? '' : '\nRef. ${row['reference']}'}'), isThreeLine: row['reference'] != null, trailing: Text('${outgoing ? '-' : '+'}${_money(row['amount_clp'])}', style: TextStyle(fontWeight: FontWeight.w800, color: outgoing ? Colors.red : Colors.green))));
        }),
      ]));
    },
  );
}

class _CashboxData {
  const _CashboxData(this.summary, this.movements, this.accounts);
  final Map<String, dynamic> summary;
  final List<Map<String, dynamic>> movements;
  final List<Map<String, dynamic>> accounts;
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value, required this.color});
  final String label;
  final String value;
  final Color color;
  @override
  Widget build(BuildContext context) => SizedBox(width: 220, child: Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label), const SizedBox(height: 6), Text(value, style: Theme.of(context).textTheme.titleLarge?.copyWith(color: color, fontWeight: FontWeight.w800))]))));
}
