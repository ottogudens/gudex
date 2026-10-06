part of 'main.dart';

const _socialRoot = '/api/v1/social';
const _socialStates = {
  'draft': 'Borrador',
  'review': 'En revisión',
  'approved': 'Aprobado',
  'planned': 'Planificado',
  'published': 'Publicado manualmente'
};
const _socialNetworks = {
  'instagram': 'Instagram',
  'facebook': 'Facebook',
  'linkedin': 'LinkedIn'
};

DateTime? _socialDate(dynamic value) {
  if (value == null) return null;
  final text = value.toString();
  return DateTime.tryParse(
          text.endsWith('Z') || RegExp(r'[+-]\d\d:\d\d$').hasMatch(text)
              ? text
              : '${text}Z')
      ?.toLocal();
}

String _socialDateLabel(BuildContext context, dynamic value) {
  final date = _socialDate(value);
  if (date == null) return 'Sin fecha';
  return '${MaterialLocalizations.of(context).formatMediumDate(date)} · ${TimeOfDay.fromDateTime(date).format(context)}';
}

Future<String?> _socialPickImage() async {
  final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['png', 'jpg', 'jpeg', 'webp'],
      withData: true);
  if (result == null) return null;
  final bytes = result.files.single.bytes;
  if (bytes == null || bytes.length > 5 * 1024 * 1024)
    throw Exception('Selecciona una imagen de hasta 5 MB');
  return base64Encode(bytes);
}

class _SocialScreen extends StatefulWidget {
  const _SocialScreen({required this.api});
  final ApiClient api;
  @override
  State<_SocialScreen> createState() => _SocialScreenState();
}

class _SocialScreenState extends State<_SocialScreen> {
  List<Map<String, dynamic>> _posts = [];
  Map<String, dynamic>? _brand;
  String? _error;
  bool _loading = true;
  String _filter = 'all';
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime? _day;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        widget.api.get('$_socialRoot/posts'),
        widget.api.get('$_socialRoot/brand')
      ]);
      if (!mounted) return;
      setState(() {
        _posts = (results[0] as List)
            .map((v) => Map<String, dynamic>.from(v as Map))
            .toList();
        _brand = Map<String, dynamic>.from(results[1] as Map);
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (mounted)
        setState(() {
          _error = e.toString();
          _loading = false;
        });
    }
  }

  Future<void> _open([Map<String, dynamic>? post]) async {
    await Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) =>
                _SocialEditor(api: widget.api, postId: post?['id'] as int?)));
    if (mounted) await _load();
  }

  Widget _postCard(Map<String, dynamic> post) => Card(
          child: ListTile(
        leading: const Icon(Icons.campaign_outlined),
        title: Text(post['title'].toString()),
        subtitle: Text(
            '${_socialNetworks[post['network']]} · ${_socialStates[post['status']]}${post['planned_at'] == null ? '' : '\n${_socialDateLabel(context, post['planned_at'])}'}'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _open(post),
      ));
  Widget _publications() {
    final visible = _posts
        .where((p) => _filter == 'all' || p['status'] == _filter)
        .toList();
    return ListView(padding: const EdgeInsets.all(12), children: [
      Wrap(spacing: 8, runSpacing: 8, children: [
        FilledButton.icon(
            onPressed: () => _open(),
            icon: const Icon(Icons.add),
            label: const Text('Nueva publicación')),
        OutlinedButton.icon(
            onPressed: _load,
            icon: const Icon(Icons.refresh),
            label: const Text('Actualizar')),
      ]),
      const SizedBox(height: 16),
      const Text(
          'Crea contenido desde tu catálogo, revísalo y descarga la imagen con su texto.'),
      const SizedBox(height: 12),
      Wrap(
          spacing: 6,
          children: {'all': 'Todas', ..._socialStates}
              .entries
              .map((e) => ChoiceChip(
                  label: Text(e.value),
                  selected: _filter == e.key,
                  onSelected: (_) => setState(() => _filter = e.key)))
              .toList()),
      const SizedBox(height: 12),
      if (visible.isEmpty)
        const Padding(
            padding: EdgeInsets.all(24),
            child: Text(
                'No hay publicaciones en esta vista. Crea tu primer borrador.')),
      ...visible.map(_postCard),
    ]);
  }

  Widget _calendar() {
    final days = DateTime(_month.year, _month.month + 1, 0).day;
    final offset = (_month.weekday - 1) % 7;
    final dated = _posts
        .where((p) => p['planned_at'] != null || p['published_at'] != null)
        .where((p) {
      final date = _socialDate(p['planned_at'] ?? p['published_at'])!;
      return date.year == _month.year &&
          date.month == _month.month &&
          (_day == null || date.day == _day!.day);
    }).toList()
      ..sort((a, b) => _socialDate(a['planned_at'] ?? a['published_at'])!
          .compareTo(_socialDate(b['planned_at'] ?? b['published_at'])!));
    return ListView(padding: const EdgeInsets.all(12), children: [
      const Text(
          'Planificación editorial · Las fechas se muestran en la zona horaria de este dispositivo. Publica manualmente en la red elegida.'),
      Row(children: [
        IconButton(
            tooltip: 'Mes anterior',
            onPressed: () => setState(() {
                  _month = DateTime(_month.year, _month.month - 1);
                  _day = null;
                }),
            icon: const Icon(Icons.chevron_left)),
        Expanded(
            child: Text(
                MaterialLocalizations.of(context).formatMonthYear(_month),
                textAlign: TextAlign.center)),
        IconButton(
            tooltip: 'Mes siguiente',
            onPressed: () => setState(() {
                  _month = DateTime(_month.year, _month.month + 1);
                  _day = null;
                }),
            icon: const Icon(Icons.chevron_right))
      ]),
      Row(
          children: ['L', 'M', 'M', 'J', 'V', 'S', 'D']
              .map((d) => Expanded(child: Center(child: Text(d))))
              .toList()),
      GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: ((offset + days + 6) ~/ 7) * 7,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7, mainAxisExtent: 58),
          itemBuilder: (context, index) {
            final day = index - offset + 1;
            if (day < 1 || day > days) return const SizedBox.shrink();
            final count = _posts.where((p) {
              final date = _socialDate(p['planned_at'] ?? p['published_at']);
              return date != null &&
                  date.year == _month.year &&
                  date.month == _month.month &&
                  date.day == day;
            }).length;
            return TextButton(
                onPressed: () => setState(() => _day = _day?.day == day
                    ? null
                    : DateTime(_month.year, _month.month, day)),
                style: TextButton.styleFrom(
                    backgroundColor: _day?.day == day
                        ? Theme.of(context).colorScheme.secondaryContainer
                        : null),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text('$day'),
                  if (count > 0)
                    Text('$count publ.', style: const TextStyle(fontSize: 10))
                ]));
          }),
      if (_day != null)
        TextButton(
            onPressed: () => setState(() => _day = null),
            child: const Text('Ver todo el mes')),
      if (dated.isEmpty)
        const Padding(
            padding: EdgeInsets.all(24),
            child: Text('No hay publicaciones para estas fechas.')),
      ...dated.map(_postCard),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null)
      return Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(_error!),
        FilledButton(onPressed: _load, child: const Text('Reintentar'))
      ]));
    return DefaultTabController(
        length: 4,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Contenido y redes',
              style: Theme.of(context).textTheme.headlineSmall),
          const TabBar(isScrollable: true, tabs: [
            Tab(text: 'Publicaciones'),
            Tab(text: 'Calendario'),
            Tab(text: 'Marca'),
            Tab(text: 'Cuentas')
          ]),
          Expanded(
              child: TabBarView(children: [
            _publications(),
            _calendar(),
            _SocialBrandForm(api: widget.api, initial: _brand!),
            ListView(padding: const EdgeInsets.all(16), children: [
              const Text('Conexión de cuentas · Próxima etapa'),
              const SizedBox(height: 12),
              ..._socialNetworks.values.map((name) => Card(
                  child: ListTile(
                      leading: const Icon(Icons.link_off),
                      title: Text(name),
                      subtitle: const Text(
                          'Sin conectar. Descarga el material aprobado y publícalo manualmente.')))),
            ]),
          ])),
        ]));
  }
}

class _SocialBrandForm extends StatefulWidget {
  const _SocialBrandForm({required this.api, required this.initial});
  final ApiClient api;
  final Map<String, dynamic> initial;
  @override
  State<_SocialBrandForm> createState() => _SocialBrandFormState();
}

class _SocialBrandFormState extends State<_SocialBrandForm> {
  final _form = GlobalKey<FormState>();
  late final Map<String, TextEditingController> _fields;
  late String _logo;
  bool _busy = false;
  static const _labels = {
    'name': 'Nombre de marca',
    'tone': 'Tono de voz',
    'audience': 'Público',
    'primary_color': 'Color principal (#RRGGBB)',
    'accent_color': 'Color de acento (#RRGGBB)',
    'call_to_action': 'Llamada a la acción',
    'contact': 'Contacto público (opcional)'
  };
  @override
  void initState() {
    super.initState();
    _fields = {
      for (final key in _labels.keys)
        key: TextEditingController(text: widget.initial[key]?.toString() ?? '')
    };
    _logo = widget.initial['logo_base64']?.toString() ?? '';
  }

  @override
  void dispose() {
    for (final controller in _fields.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await widget.api.putJson('$_socialRoot/brand', {
        for (final e in _fields.entries) e.key: e.value.text.trim(),
        'logo_base64': _logo
      });
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Marca guardada. Se aplicará a las nuevas publicaciones.')));
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AbsorbPointer(
      absorbing: _busy,
      child: Form(
          key: _form,
          child: ListView(padding: const EdgeInsets.all(16), children: [
            const Text(
                'La identidad de marca se guarda con cada publicación para conservar el diseño aprobado. El tono y público se utilizan al generar con IA.'),
            for (final e in _fields.entries)
              Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: TextFormField(
                      controller: e.value,
                      decoration: InputDecoration(labelText: _labels[e.key]),
                      maxLength: {
                        'name': 80,
                        'tone': 300,
                        'audience': 300,
                        'primary_color': 7,
                        'accent_color': 7,
                        'call_to_action': 120,
                        'contact': 120
                      }[e.key],
                      validator: (v) {
                        if (e.key != 'contact' &&
                            (v == null || v.trim().isEmpty))
                          return 'Completa este campo';
                        if (e.key.endsWith('color') &&
                            !RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(v ?? ''))
                          return 'Usa un color como #ED0606';
                        return null;
                      })),
            if (_logo.isNotEmpty) Image.memory(base64Decode(_logo), height: 90),
            Wrap(spacing: 8, children: [
              OutlinedButton.icon(
                  onPressed: () async {
                    try {
                      final image = await _socialPickImage();
                      if (image != null && mounted)
                        setState(() => _logo = image);
                    } catch (e) {
                      if (context.mounted)
                        ScaffoldMessenger.of(context)
                            .showSnackBar(SnackBar(content: Text('$e')));
                    }
                  },
                  icon: const Icon(Icons.image_outlined),
                  label: const Text('Elegir logo')),
              if (_logo.isNotEmpty)
                TextButton(
                    onPressed: () => setState(() => _logo = ''),
                    child: const Text('Quitar logo'))
            ]),
            const SizedBox(height: 12),
            FilledButton(
                onPressed: _busy ? null : _save,
                child: Text(_busy ? 'Guardando…' : 'Guardar marca')),
          ])));
}

class _SocialEditor extends StatefulWidget {
  const _SocialEditor({required this.api, this.postId, this.product});
  final ApiClient api;
  final int? postId;
  final Map<String, dynamic>? product;
  @override
  State<_SocialEditor> createState() => _SocialEditorState();
}

class _SocialEditorState extends State<_SocialEditor> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController(),
      _source = TextEditingController(),
      _brief = TextEditingController(),
      _caption = TextEditingController(),
      _headline = TextEditingController();
  Map<String, dynamic>? _post;
  List<Map<String, dynamic>> _products = [], _services = [];
  String _network = 'instagram',
      _format = 'square',
      _objective = 'inform',
      _image = '';
  int? _productId;
  bool _busy = false, _loading = true, _dirty = false;
  String? _error;
  Future<Uint8List>? _preview;
  String get _status => _post?['status']?.toString() ?? 'draft';
  bool get _editable => _status == 'draft' || _status == 'review';
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [_title, _source, _brief, _caption, _headline]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final products = await widget.api.get('/api/v1/products');
      final services = await widget.api.get('/api/v1/services') as List;
      final post = widget.postId == null
          ? null
          : Map<String, dynamic>.from(await widget.api
              .get('$_socialRoot/posts/${widget.postId}') as Map);
      if (!mounted) return;
      setState(() {
        _products = (products as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _services =
            services.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        if (post != null) {
          _apply(post);
        } else if (widget.product != null) {
          _productId = widget.product!['id'] as int;
          _title.text = widget.product!['name'].toString();
          _source.text = _title.text;
          _dirty = true;
        }
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (mounted)
        setState(() {
          _loading = false;
          _error = '$e';
        });
    }
  }

  void _apply(Map<String, dynamic> post) {
    _post = post;
    _title.text = post['title'];
    _source.text = post['source_name'];
    _brief.text = post['brief'];
    _caption.text = post['caption'];
    _headline.text = post['headline'];
    _productId = post['product_id'] as int?;
    _network = post['network'];
    _format = post['format'];
    _objective = post['objective'];
    _image = post['image_base64'];
    _dirty = false;
    _preview =
        widget.api.getBytes('$_socialRoot/posts/${post['id']}/preview.png');
  }

  Map<String, dynamic> _payload() => {
        'title': _title.text.trim(),
        'source_name': _source.text.trim(),
        'brief': _brief.text.trim(),
        'caption': _caption.text.trim(),
        'headline': _headline.text.trim(),
        'product_id': _productId,
        'network': _network,
        'format': _format,
        'objective': _objective,
        'image_base64': _image
      };
  Future<void> _run(Future<void> Function() task) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await task();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _save() async {
    if (!_form.currentState!.validate()) return false;
    final data = _post == null
        ? await widget.api.postJson('$_socialRoot/posts', _payload())
        : await widget.api
            .putJson('$_socialRoot/posts/${_post!['id']}', _payload());
    if (mounted) setState(() => _apply(Map<String, dynamic>.from(data as Map)));
    return true;
  }

  Future<void> _generate(bool ai) => _run(() async {
        if (!await _save()) return;
        final data = await widget.api.postJson(
            '$_socialRoot/posts/${_post!['id']}/generate', {'use_ai': ai});
        if (mounted)
          setState(() => _apply(Map<String, dynamic>.from(data as Map)));
      });
  Future<void> _statusChange(String status, {DateTime? planned}) =>
      _run(() async {
        if (_dirty && !await _save()) return;
        if (status == _status) return;
        final data = await widget.api
            .postJson('$_socialRoot/posts/${_post!['id']}/status', {
          'status': status,
          if (planned != null) 'planned_at': planned.toUtc().toIso8601String()
        });
        if (mounted)
          setState(() => _apply(Map<String, dynamic>.from(data as Map)));
      });
  Future<void> _plan() async {
    final now = DateTime.now();
    final date = await showDatePicker(
        context: context,
        initialDate: now.add(const Duration(days: 1)),
        firstDate: now,
        lastDate: now.add(const Duration(days: 730)));
    if (date == null || !mounted) return;
    final time = await showTimePicker(
        context: context, initialTime: const TimeOfDay(hour: 10, minute: 0));
    if (time != null && mounted)
      await _statusChange('planned',
          planned: DateTime(
              date.year, date.month, date.day, time.hour, time.minute));
  }

  Future<void> _export() => _run(() async {
        final bytes = await widget.api
            .getBytes('$_socialRoot/posts/${_post!['id']}/export');
        await FilePicker.saveFile(
            dialogTitle: 'Exportar publicación',
            fileName: 'gudex-publicacion-${_post!['id']}.zip',
            type: FileType.custom,
            allowedExtensions: ['zip'],
            bytes: bytes);
      });
  Future<bool> _confirm(String title, String message) async =>
      await showDialog<bool>(
          context: context,
          builder: (ctx) =>
              AlertDialog(title: Text(title), content: Text(message), actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Cancelar')),
                FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Confirmar'))
              ])) ??
      false;
  Widget _field(TextEditingController controller, String label, int max,
          {int lines = 1, bool required = false}) =>
      Padding(
          padding: const EdgeInsets.only(top: 12),
          child: TextFormField(
              controller: controller,
              enabled: _editable,
              minLines: lines,
              maxLines: lines == 1 ? 1 : lines + 3,
              maxLength: max,
              decoration: InputDecoration(labelText: label),
              onChanged: (_) => setState(() => _dirty = true),
              validator: (v) => required && (v == null || v.trim().isEmpty)
                  ? 'Completa este campo'
                  : null));
  Widget _select(String label, String value, Map<String, String> options,
          void Function(String) change) =>
      Padding(
          padding: const EdgeInsets.only(top: 12),
          child: DropdownButtonFormField<String>(
              key: ValueKey('$label:$value'),
              initialValue: value,
              decoration: InputDecoration(labelText: label),
              items: options.entries
                  .map((e) =>
                      DropdownMenuItem(value: e.key, child: Text(e.value)))
                  .toList(),
              onChanged: !_editable
                  ? null
                  : (v) {
                      if (v != null)
                        setState(() {
                          change(v);
                          _dirty = true;
                        });
                    }));
  Widget _editor() => Form(
      key: _form,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (_editable)
          DropdownButtonFormField<int>(
              key: ValueKey(_productId),
              initialValue: _products.any((p) => p['id'] == _productId)
                  ? _productId
                  : null,
              isExpanded: true,
              decoration: const InputDecoration(
                  labelText: 'Producto del inventario (opcional)'),
              items: [
                const DropdownMenuItem<int>(
                    value: null, child: Text('Contenido general o servicio')),
                ..._products.map((p) => DropdownMenuItem<int>(
                    value: p['id'] as int,
                    child: Text(p['name'].toString(),
                        overflow: TextOverflow.ellipsis)))
              ],
              onChanged: (id) => setState(() {
                    _productId = id;
                    _dirty = true;
                    if (id != null) {
                      final p = _products.firstWhere((p) => p['id'] == id);
                      _source.text = p['name'].toString();
                      if (_title.text.isEmpty) _title.text = _source.text;
                    }
                  })),
        if (_editable && _productId == null)
          Padding(
              padding: const EdgeInsets.only(top: 12),
              child: DropdownButtonFormField<String>(
                  isExpanded: true,
                  decoration: const InputDecoration(
                      labelText: 'Elegir servicio del catálogo (opcional)'),
                  items: _services
                      .map((s) => DropdownMenuItem(
                          value: s['code'].toString(),
                          child: Text(s['name'].toString(),
                              overflow: TextOverflow.ellipsis)))
                      .toList(),
                  onChanged: (code) {
                    if (code != null)
                      setState(() {
                        _source.text = _services
                            .firstWhere((s) => s['code'] == code)['name']
                            .toString();
                        if (_title.text.isEmpty) _title.text = _source.text;
                        _dirty = true;
                      });
                  })),
        _field(_title, 'Título interno', 100, required: true),
        _field(_source, 'Producto o servicio a promocionar', 120),
        _select('Red', _network, _socialNetworks, (v) => _network = v),
        _select(
            'Formato de imagen',
            _format,
            {
              'square': 'Cuadrado · 1080 × 1080',
              'portrait': 'Vertical · 1080 × 1350',
              'story': 'Historia · 1080 × 1920'
            },
            (v) => _format = v),
        _select(
            'Objetivo',
            _objective,
            {
              'inform': 'Informar',
              'sell': 'Promocionar',
              'engage': 'Generar interacción'
            },
            (v) => _objective = v),
        _field(_brief, 'Idea, promoción y condiciones verificadas', 1500,
            lines: 3),
        if (_editable)
          Wrap(spacing: 8, runSpacing: 8, children: [
            OutlinedButton.icon(
                onPressed: () => _generate(false),
                icon: const Icon(Icons.auto_fix_high),
                label: const Text('Generar con plantilla')),
            OutlinedButton.icon(
                onPressed: () => _generate(true),
                icon: const Icon(Icons.auto_awesome),
                label: const Text('Generar con IA'))
          ]),
        if (_editable)
          const Text(
              'Generar reemplaza el texto y titular. La IA utiliza la configuración del asistente de Gudex; la plantilla funciona sin conexión a un proveedor IA.',
              style: TextStyle(fontSize: 12)),
        _field(_headline, 'Titular de la imagen', 140),
        _field(_caption, 'Texto de la publicación', 2200, lines: 5),
        if (_image.isNotEmpty) Image.memory(base64Decode(_image), height: 130),
        if (_editable)
          Wrap(spacing: 8, children: [
            OutlinedButton.icon(
                onPressed: () async {
                  try {
                    final image = await _socialPickImage();
                    if (image != null && mounted)
                      setState(() {
                        _image = image;
                        _dirty = true;
                      });
                  } catch (e) {
                    if (mounted) setState(() => _error = '$e');
                  }
                },
                icon: const Icon(Icons.add_photo_alternate_outlined),
                label: const Text('Elegir fotografía')),
            if (_image.isNotEmpty)
              TextButton(
                  onPressed: () => setState(() {
                        _image = '';
                        _dirty = true;
                      }),
                  child: const Text('Quitar foto'))
          ]),
        const SizedBox(height: 12),
        if (_editable)
          FilledButton.icon(
              onPressed: () => _run(() async {
                    await _save();
                  }),
              icon: const Icon(Icons.save_outlined),
              label: const Text('Guardar y actualizar vista previa')),
      ]));
  Widget _previewPanel() =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Vista previa del diseño guardado',
            style: Theme.of(context).textTheme.titleMedium),
        if (_dirty)
          const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(
                  'Hay cambios sin guardar. Guarda para actualizar la vista previa.')),
        if (_preview == null)
          const Padding(
              padding: EdgeInsets.all(36),
              child: Text('Guarda el borrador para ver el diseño.'))
        else
          FutureBuilder<Uint8List>(
              future: _preview,
              builder: (context, snapshot) {
                if (snapshot.hasError)
                  return Text(
                      'No se pudo cargar la vista previa: ${snapshot.error}');
                if (!snapshot.hasData)
                  return const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(child: CircularProgressIndicator()));
                return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Image.memory(snapshot.data!,
                        fit: BoxFit.contain,
                        semanticLabel: 'Diseño de la publicación'));
              }),
        if (_post != null) ...[
          Chip(label: Text(_socialStates[_status] ?? _status)),
          if (_post!['planned_at'] != null)
            Text(
                'Planificada: ${_socialDateLabel(context, _post!['planned_at'])}'),
          if (_post!['generation_method'] == 'ai')
            const Text(
                'Texto generado con IA. Verifica los datos antes de aprobar.'),
          if (!_dirty) SelectableText(_post!['caption'].toString()),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            if (_status == 'draft')
              FilledButton(
                  onPressed: () => _statusChange('review'),
                  child: const Text('Enviar a revisión')),
            if (_status == 'review' && !_dirty)
              FilledButton(
                  onPressed: () => _statusChange('approved'),
                  child: const Text('Aprobar publicación')),
            if ({'review', 'approved', 'planned'}.contains(_status))
              OutlinedButton(
                  onPressed: () => _statusChange('draft'),
                  child: const Text('Volver a borrador')),
            if ({'approved', 'planned'}.contains(_status))
              OutlinedButton(
                  onPressed: _status == 'planned'
                      ? () => _statusChange('approved')
                      : _plan,
                  child: Text(_status == 'planned'
                      ? 'Quitar del calendario'
                      : 'Planificar fecha')),
            if ({'approved', 'planned', 'published'}.contains(_status))
              FilledButton.icon(
                  onPressed: _export,
                  icon: const Icon(Icons.download),
                  label: const Text('Descargar PNG + texto')),
            if ({'approved', 'planned'}.contains(_status))
              OutlinedButton(
                  onPressed: () async {
                    if (await _confirm('Confirmar publicación manual',
                        '¿Ya publicaste este contenido en ${_socialNetworks[_network]}? Gudex solo registrará tu confirmación.'))
                      await _statusChange('published');
                  },
                  child: const Text('Ya lo publiqué')),
            if (_status == 'draft')
              TextButton(
                  onPressed: () async {
                    if (await _confirm(
                        'Eliminar borrador', 'Se eliminará este borrador.'))
                      await _run(() async {
                        await widget.api
                            .delete('$_socialRoot/posts/${_post!['id']}');
                        if (mounted) {
                          _dirty = false;
                          Navigator.pop(context);
                        }
                      });
                  },
                  child: const Text('Eliminar borrador')),
          ]),
          const SizedBox(height: 12),
          const Text(
              'La planificación no publica automáticamente. Descarga el material y súbelo a la cuenta correspondiente.'),
        ],
      ]);
  @override
  Widget build(BuildContext context) => PopScope(
      canPop: !_dirty && !_busy,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop || _busy) return;
        if (await _confirm('Cambios sin guardar',
                '¿Salir y descartar los cambios sin guardar?') &&
            mounted) {
          setState(() => _dirty = false);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) Navigator.pop(context);
          });
        }
      },
      child: Scaffold(
        appBar: AppBar(
            title: Text(
                _post == null ? 'Nueva publicación' : 'Editar publicación')),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : AbsorbPointer(
                absorbing: _busy,
                child: Column(children: [
                  if (_busy) const LinearProgressIndicator(),
                  if (_error != null)
                    Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(_error!,
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.error))),
                  if (_error != null && _products.isEmpty && _post == null)
                    TextButton(
                        onPressed: _load,
                        child: const Text('Reintentar carga')),
                  Expanded(
                      child: SingleChildScrollView(
                          padding: const EdgeInsets.all(20),
                          child: Center(
                              child: ConstrainedBox(
                                  constraints:
                                      const BoxConstraints(maxWidth: 1180),
                                  child: LayoutBuilder(
                                      builder: (context, constraints) =>
                                          constraints.maxWidth >= 800
                                              ? Row(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                      Expanded(
                                                          child: _editor()),
                                                      const SizedBox(width: 32),
                                                      Expanded(
                                                          child:
                                                              _previewPanel())
                                                    ])
                                              : Column(children: [
                                                  _editor(),
                                                  const SizedBox(height: 24),
                                                  _previewPanel()
                                                ])))))),
                ])),
      ));
}
