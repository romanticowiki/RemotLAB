// ============================================================================
// Aula Remota AR-77 â€” App administrativa
//
// Lee el estado real del laboratorio desde la API de supervision que corre en
// la instancia EC2. Es de SOLO LECTURA: no hay una sola llamada que reinicie,
// borre ni modifique nada del servidor.
// ============================================================================

import 'dart:async';

import 'package:flutter/material.dart';

import 'bloqueo.dart';
import 'escritorio.dart';
import 'nucleo.dart';

// Los colores, el cliente de la API y los ajustes viven en nucleo.dart para que
// bloqueo.dart y escritorio.dart puedan usarlos sin importaciones circulares.
// Se reexportan para que quien importe main.dart siga viendolo todo.
export 'nucleo.dart';

void main() => runApp(const AulaRemotaApp());


// ---------------------------------------------------------------- app

class AulaRemotaApp extends StatefulWidget {
  const AulaRemotaApp({super.key});
  @override
  State<AulaRemotaApp> createState() => _AulaRemotaAppState();
}

class _AulaRemotaAppState extends State<AulaRemotaApp> with WidgetsBindingObserver {
  /// Si la app esta tapada por la pantalla de bloqueo ahora mismo.
  bool _bloqueada = false;

  /// Cuando se fue a segundo plano. Nulo si esta en primer plano.
  DateTime? _desdeFondo;

  /// Volver de mirar una notificacion no deberia obligar a poner la huella
  /// otra vez: eso cansa y acaba con el usuario desactivando el bloqueo. Se
  /// vuelve a pedir solo si estuvo fuera mas de este tiempo.
  static const _gracia = Duration(seconds: 30);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ajustes.addListener(() => setState(() {}));
    ajustes.cargar().then((_) {
      if (mounted && ajustes.bloqueoActivo) setState(() => _bloqueada = true);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState estado) {
    if (!ajustes.bloqueoActivo) return;

    // "inactive" tambien cubre el momento en que aparece el dialogo del sistema
    // para la huella. Si se contara como irse al fondo, la propia peticion
    // biometrica dispararia otro bloqueo: un bucle del que no se sale.
    if (estado == AppLifecycleState.paused) {
      _desdeFondo = DateTime.now();
    } else if (estado == AppLifecycleState.resumed) {
      final fuera = _desdeFondo;
      _desdeFondo = null;
      if (fuera != null && DateTime.now().difference(fuera) > _gracia) {
        setState(() => _bloqueada = true);
      }
    }
  }

  ThemeData _tema(bool oscuro) {
    final base = oscuro ? ThemeData.dark() : ThemeData.light();
    return base.copyWith(
      scaffoldBackgroundColor: oscuro ? C.dBg : C.bg,
      colorScheme: base.colorScheme.copyWith(
        primary: oscuro ? C.dBrand : C.brand,
        surface: oscuro ? C.dSurface : C.surface,
      ),
      extensions: [oscuro ? Tono.oscuro : Tono.claro],
      textTheme: base.textTheme.apply(
        bodyColor: oscuro ? C.dText : C.text,
        displayColor: oscuro ? C.dText : C.text,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Aula Remota',
      debugShowCheckedModeBanner: false,
      theme: _tema(ajustes.oscuro),
      home: _inicio(),
    );
  }

  Widget _inicio() {
    if (!ajustes.cargado) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    // El bloqueo va por delante de todo, incluida la pantalla de configuracion:
    // ahi es donde se ve y se edita el token del servidor.
    if (_bloqueada) {
      return PantallaBloqueo(onEntrar: () => setState(() => _bloqueada = false));
    }
    return ajustes.configurado ? const Panel() : const Config(primeraVez: true);
  }
}

// ---------------------------------------------------------------- config

class Config extends StatefulWidget {
  final bool primeraVez;
  const Config({super.key, this.primeraVez = false});
  @override
  State<Config> createState() => _ConfigState();
}

class _ConfigState extends State<Config> {
  late final _srv = TextEditingController(text: ajustes.servidor);
  late final _tok = TextEditingController(text: ajustes.token);
  String? _probando;

  @override
  void initState() {
    super.initState();
    ajustes.addListener(_repintar);
  }

  void _repintar() { if (mounted) setState(() {}); }

  @override
  void dispose() {
    ajustes.removeListener(_repintar);
    super.dispose();
  }

  Future<void> _probar() async {
    setState(() => _probando = 'Conectando...');
    try {
      await Api(_srv.text.trim(), _tok.text.trim()).estado();
      await ajustes.guardar(s: _srv.text, t: _tok.text);
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const Panel()), (_) => false);
    } on ApiError catch (e) {
      setState(() => _probando = '${e.mensaje}${e.pista != null ? "\n${e.pista}" : ""}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<Tono>()!;
    return Scaffold(
      appBar: widget.primeraVez ? null : AppBar(
        title: const Text('Ajustes'),
        backgroundColor: Colors.transparent, elevation: 0,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (widget.primeraVez) ...[
              const SizedBox(height: 30),
              Container(
                width: 56, height: 56,
                decoration: BoxDecoration(color: t.brand, borderRadius: BorderRadius.circular(18)),
                child: const Icon(Icons.dns_outlined, color: Colors.white, size: 30),
              ),
              const SizedBox(height: 20),
              Text('Aula Remota',
                  style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800,
                      letterSpacing: -1, color: Theme.of(context).textTheme.bodyLarge!.color)),
              const SizedBox(height: 8),
              Text('Conecta con tu servidor para ver el estado del laboratorio.',
                  style: TextStyle(fontSize: 15.5, color: t.text2, height: 1.5)),
              const SizedBox(height: 28),
            ],
            _campo('Direccion del servidor', _srv, 'https://lab.example.com',
                'La IP publica de la instancia y el puerto de la API.', t),
            const SizedBox(height: 16),
            _campo('Token de acceso', _tok, 'el api_token de secrets.yml',
                'Se guarda solo en este telefono.', t, oculto: true),
            const SizedBox(height: 22),
            Text('Cada cuanto se actualiza',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: t.text2)),
            const SizedBox(height: 8),
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 5,  label: Text('5 s')),
                ButtonSegment(value: 10, label: Text('10 s')),
                ButtonSegment(value: 30, label: Text('30 s')),
                ButtonSegment(value: 60, label: Text('1 min')),
              ],
              selected: {ajustes.refrescoSeg},
              onSelectionChanged: (v) => ajustes.guardar(r: v.first),
              showSelectedIcon: false,
            ),
            const SizedBox(height: 6),
            Text('Mas seguido gasta mas bateria y datos.',
                style: TextStyle(fontSize: 12, color: t.text3)),

            if (!widget.primeraVez) ...[
              const SizedBox(height: 26),
              Divider(color: t.line, height: 1),
              const SizedBox(height: 22),
              _Seguridad(t: t),
            ],

            const SizedBox(height: 24),
            FilledButton(
              onPressed: _probando == 'Conectando...' ? null : _probar,
              style: FilledButton.styleFrom(
                backgroundColor: t.brand, minimumSize: const Size.fromHeight(54),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              child: Text(_probando == 'Conectando...'
                      ? 'Conectando...'
                      : (widget.primeraVez ? 'Conectar' : 'Guardar y probar'),
                  style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700)),
            ),
            if (_probando != null && _probando != 'Conectando...') ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: t.critSoft, borderRadius: BorderRadius.circular(16)),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(Icons.error_outline, color: t.crit, size: 20),
                  const SizedBox(width: 12),
                  Expanded(child: Text(_probando!,
                      style: TextStyle(fontSize: 13.5, color: t.crit, height: 1.5))),
                ]),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _campo(String etiqueta, TextEditingController c, String hint,
      String ayuda, Tono t, {bool oculto = false}) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(etiqueta, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: t.text2)),
      const SizedBox(height: 8),
      TextField(
        controller: c,
        obscureText: oculto,
        autocorrect: false,
        enableSuggestions: false,
        keyboardType: oculto ? TextInputType.text : TextInputType.url,
        style: const TextStyle(fontSize: 15),
        decoration: InputDecoration(
          hintText: hint,
          filled: true,
          fillColor: Theme.of(context).colorScheme.surface,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
      ),
      const SizedBox(height: 6),
      Text(ayuda, style: TextStyle(fontSize: 12, color: t.text3)),
    ]);
  }
}

/// Bloqueo de la app dentro de Ajustes.
///
/// El orden de la pantalla no es casual: primero se define el PIN y solo
/// despues aparece la opcion de huella. Si se pudiera activar la huella sin
/// PIN, un sensor averiado dejaria el laboratorio inaccesible desde el
/// telefono.
class _Seguridad extends StatefulWidget {
  final Tono t;
  const _Seguridad({required this.t});
  @override
  State<_Seguridad> createState() => _SeguridadState();
}

class _SeguridadState extends State<_Seguridad> {
  bool _hayBiometria = false;

  @override
  void initState() {
    super.initState();
    Biometria.disponible().then((v) {
      if (mounted) setState(() => _hayBiometria = v);
    });
  }

  Future<void> _cambiarBloqueo(bool activar) async {
    if (!activar) {
      final seguro = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Quitar el bloqueo'),
          content: const Text(
            'Cualquiera que tome el telefono desbloqueado podra ver el '
            'laboratorio y leer el token del servidor.',
            style: TextStyle(height: 1.5),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(backgroundColor: widget.t.crit),
              child: const Text('Quitar'),
            ),
          ],
        ),
      );
      if (seguro == true) await ajustes.quitarBloqueo();
      return;
    }

    final creado = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => const PantallaCrearPin()));
    if (creado != true) return;
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Bloqueo activado')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    final texto = Theme.of(context).textTheme.bodyLarge!.color;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Seguridad',
          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: t.text2)),
      const SizedBox(height: 12),
      Container(
        decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(18)),
        child: Column(children: [
          SwitchListTile(
            value: ajustes.bloqueoActivo,
            onChanged: _cambiarBloqueo,
            activeThumbColor: Colors.white,
            activeTrackColor: t.brand,
            contentPadding: const EdgeInsets.fromLTRB(16, 6, 12, 6),
            title: Text('Pedir identificacion al abrir',
                style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: texto)),
            subtitle: Text(
              ajustes.bloqueoActivo
                  ? 'Activo. Vuelve a pedirla si sales mas de 30 segundos.'
                  : 'Ahora mismo cualquiera que tome el telefono entra.',
              style: TextStyle(fontSize: 12.5, color: t.text3, height: 1.4),
            ),
          ),
          if (ajustes.bloqueoActivo) ...[
            Divider(color: t.line, height: 1, indent: 16, endIndent: 16),
            SwitchListTile(
              value: _hayBiometria && ajustes.usarBiometrico,
              onChanged: _hayBiometria
                  ? (v) => ajustes.guardar(biometrico: v)
                  : null,
              activeThumbColor: Colors.white,
              activeTrackColor: t.brand,
              contentPadding: const EdgeInsets.fromLTRB(16, 6, 12, 6),
              title: Text('Entrar con ${Biometria.nombre}',
                  style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600,
                      color: _hayBiometria ? texto : t.text3)),
              subtitle: Text(
                _hayBiometria
                    ? 'Tu ${Biometria.nombre} no sale del telefono. La app solo '
                        'recibe un si o un no.'
                    : 'Este telefono no tiene biometria configurada.',
                style: TextStyle(fontSize: 12.5, color: t.text3, height: 1.4),
              ),
            ),
            Divider(color: t.line, height: 1, indent: 16, endIndent: 16),
            ListTile(
              contentPadding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
              title: Text('Cambiar el PIN',
                  style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: texto)),
              trailing: Icon(Icons.chevron_right, color: t.text3),
              onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const PantallaCrearPin())),
            ),
          ],
        ]),
      ),
    ]);
  }
}

// ---------------------------------------------------------------- panel

class Panel extends StatefulWidget {
  const Panel({super.key});
  @override
  State<Panel> createState() => _PanelState();
}

class _PanelState extends State<Panel> with WidgetsBindingObserver {
  Map<String, dynamic>? _datos;
  ApiError? _error;
  bool _cargando = true;
  bool _refrescando = false;
  DateTime? _ultima;
  Timer? _timer;     // pide datos nuevos al servidor
  Timer? _tick;      // solo repinta el "hace N s"
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _cargar();
    _programar();

    // El contador de frescura sube cada segundo aunque no haya datos nuevos.
    // Sin esto la pantalla se queda congelada en "hace 0 s" y parece que la
    // app se colgo, cuando en realidad esta esperando el siguiente ciclo.
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _ultima != null) setState(() {});
    });
  }

  void _programar() {
    _timer?.cancel();
    _timer = Timer.periodic(Duration(seconds: ajustes.refrescoSeg),
        (_) => _cargar(silencioso: true));
  }

  // Al volver del segundo plano los temporizadores de Android pueden haberse
  // congelado. Se pide una lectura inmediata en vez de esperar al siguiente
  // ciclo, que es justo cuando el usuario mira la pantalla.
  @override
  void didChangeAppLifecycleState(AppLifecycleState estado) {
    if (estado == AppLifecycleState.resumed) {
      _cargar(silencioso: true);
      _programar();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _cargar({bool silencioso = false}) async {
    if (!silencioso) setState(() { _cargando = true; _error = null; });
    if (mounted) setState(() => _refrescando = true);
    try {
      final d = await Api(ajustes.servidor, ajustes.token).estado();
      if (!mounted) return;
      setState(() {
        _datos = d; _error = null; _cargando = false;
        _refrescando = false; _ultima = DateTime.now();
      });
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() { _error = e; _cargando = false; _refrescando = false; });
    }
  }

  String get _frescura {
    if (_refrescando) return 'actualizando';
    if (_ultima == null) return '';
    final s = DateTime.now().difference(_ultima!).inSeconds;
    if (s < 5) return 'ahora';
    if (s < 60) return 'hace $s s';
    return 'hace ${(s / 60).floor()} min';
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<Tono>()!;
    final vistas = [
      _Inicio(datos: _datos, frescura: _frescura,
          refrescando: _refrescando, onRefrescar: _cargar),
      _Servicios(datos: _datos),
      _Sesiones(datos: _datos),
      _Alertas(datos: _datos),
    ];

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent, elevation: 0, scrolledUnderElevation: 0,
        titleSpacing: 20,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(['Hola', 'Sistema', 'Sesiones', 'Alertas'][_tab],
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, letterSpacing: -0.5,
                  color: Theme.of(context).textTheme.bodyLarge!.color)),
          Text([
            'Asi va el laboratorio hoy',
            'Los servicios que lo sostienen',
            'Quien esta conectado ahora',
            'Lo que necesita tu atencion',
          ][_tab], style: TextStyle(fontSize: 12.5, color: t.text3)),
        ]),
        actions: [
          IconButton(
            icon: Icon(ajustes.oscuro ? Icons.light_mode_outlined : Icons.dark_mode_outlined),
            onPressed: () => ajustes.guardar(o: !ajustes.oscuro),
            tooltip: ajustes.oscuro ? 'Modo claro' : 'Modo oscuro',
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const Config())),
            tooltip: 'Ajustes',
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _error != null && _datos == null
          ? _ErrorVista(error: _error!, onReintentar: _cargar)
          : _cargando && _datos == null
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _cargar,
                  child: Stack(children: [
                    vistas[_tab],
                    if (_error != null)
                      Positioned(left: 16, right: 16, bottom: 16,
                          child: _AvisoSinConexion(error: _error!)),
                  ]),
                ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        backgroundColor: Theme.of(context).colorScheme.surface,
        indicatorColor: t.brandSoft,
        destinations: [
          const NavigationDestination(icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home), label: 'Inicio'),
          const NavigationDestination(icon: Icon(Icons.dns_outlined),
              selectedIcon: Icon(Icons.dns), label: 'Sistema'),
          const NavigationDestination(icon: Icon(Icons.desktop_windows_outlined),
              selectedIcon: Icon(Icons.desktop_windows), label: 'Sesiones'),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: _avisosAltos > 0,
              label: Text('$_avisosAltos'),
              backgroundColor: t.warn,
              child: const Icon(Icons.notifications_outlined),
            ),
            selectedIcon: const Icon(Icons.notifications),
            label: 'Alertas',
          ),
        ],
      ),
    );
  }

  int get _avisosAltos {
    final a = _datos?['alertas'] as List?;
    if (a == null) return 0;
    return a.where((x) => x['nivel'] == 'alta').length;
  }
}

// ---------------------------------------------------------------- widgets

class Tarjeta extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final Color? fondo;
  const Tarjeta({super.key, required this.child,
      this.padding = const EdgeInsets.all(18), this.fondo});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: fondo ?? Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(22),
      ),
      child: child,
    );
  }
}

class _Inicio extends StatelessWidget {
  final Map<String, dynamic>? datos;
  final String frescura;
  final bool refrescando;
  final Future<void> Function() onRefrescar;
  const _Inicio({this.datos, required this.frescura,
      required this.refrescando, required this.onRefrescar});

  @override
  Widget build(BuildContext context) {
    if (datos == null) return const SizedBox();
    final t = Theme.of(context).extension<Tono>()!;
    final d = datos!;
    final estado = d['estado'] as String;
    final r = d['recursos'] as Map<String, dynamic>;
    final mem = r['memoria'] as Map<String, dynamic>;
    final ses = d['sesiones'] as Map<String, dynamic>;
    final svc = (d['servicios'] as List).cast<Map<String, dynamic>>();
    final bien = svc.where((s) => s['estado'] == 'ok').length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        // Estado global
        Tarjeta(
          fondo: t.suaveporClave(estado),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(15)),
                child: Icon(
                    estado == 'ok' ? Icons.check_rounded
                        : estado == 'warn' ? Icons.error_outline : Icons.cancel_outlined,
                    color: t.porClave(estado), size: 24),
              ),
              const SizedBox(width: 13),
              Expanded(child: Text(d['estado_texto'],
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800,
                      letterSpacing: -1, color: t.porClave(estado)))),
              Text(frescura, style: TextStyle(fontSize: 11.5, color: t.text2)),
              IconButton(
                icon: refrescando
                    ? SizedBox(width: 15, height: 15,
                        child: CircularProgressIndicator(strokeWidth: 2, color: t.text2))
                    : Icon(Icons.refresh, size: 18, color: t.text2),
                onPressed: onRefrescar, tooltip: 'Revisar ahora',
              ),
            ]),
            const SizedBox(height: 10),
            Text(d['mensaje'],
                style: TextStyle(fontSize: 14, color: t.text2, height: 1.5)),
          ]),
        ),
        const SizedBox(height: 12),

        // Procesador y memoria
        Row(children: [
          Expanded(child: _Kpi(
            icono: Icons.memory, etiqueta: 'Procesador',
            valor: '${r['cpu']['por_ciento']}', unidad: '%',
            nota: _nota(r['cpu']['por_ciento'], 80, 92), t: t)),
          const SizedBox(width: 12),
          Expanded(child: _Kpi(
            icono: Icons.sd_card_outlined, etiqueta: 'Memoria',
            valor: '${mem['por_ciento']}', unidad: '%',
            nota: _nota(mem['por_ciento'], 80, 92), t: t,
            detalle: '${mem['usada_mb']} de ${mem['total_mb']} MB')),
        ]),
        const SizedBox(height: 12),

        // Sesiones
        Tarjeta(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            _Pastilla(icono: Icons.desktop_windows_outlined, t: t),
            const SizedBox(width: 11),
            Expanded(child: Text('Escritorios en uso',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: t.text2))),
            Text('${ses['activas']}',
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
            Text(' / ${ses['limite']}',
                style: TextStyle(fontSize: 14, color: t.text3)),
          ]),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: (ses['limite'] as int) == 0 ? 0 : (ses['activas'] as int) / (ses['limite'] as int),
              minHeight: 8, backgroundColor: t.surface2,
              valueColor: AlwaysStoppedAnimation(
                  (ses['activas'] as int) >= (ses['limite'] as int) ? t.warn : t.brand),
            ),
          ),
        ])),
        const SizedBox(height: 12),

        // Servicios resumen
        Tarjeta(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(bien == svc.length
              ? 'Los ${svc.length} servicios funcionan bien.'
              : '$bien de ${svc.length} funcionan bien.',
              style: TextStyle(fontSize: 13.5, color: t.text2)),
          const SizedBox(height: 14),
          Wrap(spacing: 14, runSpacing: 12, children: svc.map((s) =>
            SizedBox(width: (MediaQuery.of(context).size.width - 32 - 36 - 14) / 2,
              child: Row(children: [
                Container(width: 9, height: 9, decoration: BoxDecoration(
                    color: t.porClave(s['estado']), shape: BoxShape.circle)),
                const SizedBox(width: 9),
                Expanded(child: Text(s['nombre'],
                    style: TextStyle(fontSize: 13, color: t.text2),
                    overflow: TextOverflow.ellipsis)),
              ]))).toList()),
        ])),
        const SizedBox(height: 12),

        // Disco y encendido
        Tarjeta(child: Column(children: [
          _Fila(etiqueta: 'Disco',
              valor: '${r['disco']['por_ciento']}%',
              extra: '${r['disco']['usado_gb']} de ${r['disco']['total_gb']} GB', t: t),
          Divider(color: t.line, height: 24),
          _Fila(etiqueta: 'Memoria de intercambio',
              valor: '${mem['swap_usada_mb']} MB',
              extra: 'de ${mem['swap_total_mb']} MB', t: t),
          Divider(color: t.line, height: 24),
          _Fila(etiqueta: 'Encendido desde hace',
              valor: r['arranque']['texto'], extra: '', t: t),
        ])),
      ],
    );
  }

  String _nota(dynamic v, num warn, num crit) {
    final x = (v as num).toDouble();
    if (x >= crit) return 'Muy alto';
    if (x >= warn) return 'Alto';
    return 'Normal';
  }
}

class _Kpi extends StatelessWidget {
  final IconData icono;
  final String etiqueta, valor, unidad, nota;
  final String? detalle;
  final Tono t;
  const _Kpi({required this.icono, required this.etiqueta, required this.valor,
      required this.unidad, required this.nota, required this.t, this.detalle});

  @override
  Widget build(BuildContext context) {
    final alerta = nota != 'Normal';
    return Tarjeta(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        _Pastilla(icono: icono, t: t, tono: alerta ? (nota == 'Muy alto' ? 'crit' : 'warn') : null),
        const SizedBox(width: 11),
        Expanded(child: Text(etiqueta,
            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: t.text2),
            overflow: TextOverflow.ellipsis)),
      ]),
      const SizedBox(height: 14),
      Row(crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic, children: [
        Text(valor, style: TextStyle(fontSize: 30, fontWeight: FontWeight.w700,
            letterSpacing: -1.5,
            color: nota == 'Muy alto' ? t.crit : nota == 'Alto' ? t.warn : null,
            fontFeatures: const [FontFeature.tabularFigures()])),
        Text(unidad, style: TextStyle(fontSize: 15, color: t.text3)),
      ]),
      const SizedBox(height: 8),
      Text(detalle ?? nota, style: TextStyle(fontSize: 12,
          color: alerta ? (nota == 'Muy alto' ? t.crit : t.warn) : t.text3,
          fontWeight: alerta ? FontWeight.w600 : FontWeight.normal)),
    ]));
  }
}

class _Pastilla extends StatelessWidget {
  final IconData icono;
  final Tono t;
  final String? tono;
  const _Pastilla({required this.icono, required this.t, this.tono});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36, height: 36,
      decoration: BoxDecoration(
          color: tono == null ? t.surface2 : t.suaveporClave(tono!),
          borderRadius: BorderRadius.circular(12)),
      child: Icon(icono, size: 19, color: tono == null ? t.text2 : t.porClave(tono!)),
    );
  }
}

class _Fila extends StatelessWidget {
  final String etiqueta, valor, extra;
  final Tono t;
  const _Fila({required this.etiqueta, required this.valor, required this.extra, required this.t});
  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Expanded(child: Text(etiqueta, style: TextStyle(fontSize: 14, color: t.text2))),
      Text(valor, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
      if (extra.isNotEmpty) ...[
        const SizedBox(width: 6),
        Text(extra, style: TextStyle(fontSize: 12, color: t.text3)),
      ],
    ]);
  }
}

class _Servicios extends StatelessWidget {
  final Map<String, dynamic>? datos;
  const _Servicios({this.datos});
  @override
  Widget build(BuildContext context) {
    if (datos == null) return const SizedBox();
    final t = Theme.of(context).extension<Tono>()!;
    final svc = (datos!['servicios'] as List).cast<Map<String, dynamic>>();
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      itemCount: svc.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) {
        final s = svc[i];
        return Tarjeta(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            _Pastilla(icono: _icono(s['clave']), t: t,
                tono: s['estado'] == 'ok' ? null : s['estado']),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(s['nombre'], style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              const SizedBox(height: 3),
              Text(s['descripcion'], style: TextStyle(fontSize: 12.5, color: t.text3, height: 1.4)),
            ])),
            if (s['estado'] != 'ok')
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(color: t.suaveporClave(s['estado']),
                    borderRadius: BorderRadius.circular(99)),
                child: Text(s['estado_texto'], style: TextStyle(fontSize: 11.5,
                    fontWeight: FontWeight.w700, color: t.porClave(s['estado']))),
              ),
          ]),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(color: t.surface2, borderRadius: BorderRadius.circular(12)),
            child: Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Puerto', style: TextStyle(fontSize: 11, color: t.text3, fontWeight: FontWeight.w600)),
                const SizedBox(height: 3),
                Text('${s['puerto']}', style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
              ])),
              Expanded(flex: 2, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Evento reciente', style: TextStyle(fontSize: 11, color: t.text3, fontWeight: FontWeight.w600)),
                const SizedBox(height: 3),
                Text('${s['evento']}', style: TextStyle(fontSize: 12.5, color: t.text2, height: 1.4)),
              ])),
            ]),
          ),
        ]));
      },
    );
  }

  IconData _icono(String clave) => switch (clave) {
    'ec2' => Icons.cloud_outlined,
    'nginx_proxy' => Icons.shield_outlined,
    'guacamole_web' => Icons.web_outlined,
    'guacd' => Icons.swap_horiz,
    'guacamole_db' => Icons.storage_outlined,
    'vnc' => Icons.desktop_windows_outlined,
    _ => Icons.settings_outlined,
  };
}

class _Sesiones extends StatelessWidget {
  final Map<String, dynamic>? datos;
  const _Sesiones({this.datos});
  @override
  Widget build(BuildContext context) {
    if (datos == null) return const SizedBox();
    final t = Theme.of(context).extension<Tono>()!;
    final ses = datos!['sesiones'] as Map<String, dynamic>;
    final conex = (ses['conexiones'] as List).cast<Map<String, dynamic>>();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        Tarjeta(child: Row(children: [
          _Pastilla(icono: Icons.desktop_windows_outlined, t: t,
              tono: (ses['activas'] as int) >= (ses['limite'] as int) ? 'warn' : null),
          const SizedBox(width: 12),
          Expanded(child: Text('Escritorios en uso',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: t.text2))),
          Text('${ses['activas']}', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
          Text(' / ${ses['limite']}', style: TextStyle(fontSize: 15, color: t.text3)),
        ])),
        const SizedBox(height: 12),
        ...conex.map((c) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Tarjeta(child: Column(children: [
            Row(children: [
              Container(
                width: 42, height: 42,
                decoration: BoxDecoration(color: t.suaveporClave(c['estado']),
                    borderRadius: BorderRadius.circular(14)),
                child: Icon(c['activa'] ? Icons.person : Icons.person_outline,
                    size: 20, color: t.porClave(c['estado'])),
              ),
              const SizedBox(width: 13),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(c['conexion'], style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                const SizedBox(height: 3),
                Text(
                  c['activa'] == true
                      ? '${c['usuario'] ?? 'alguien'} - ${c['desde_texto'] ?? 'en curso'}'
                      : 'VNC ${c['puerto']}',
                  style: TextStyle(fontSize: 12.5, color: t.text3)),
              ])),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(color: t.suaveporClave(c['estado']),
                    borderRadius: BorderRadius.circular(99)),
                child: Text(c['estado_texto'], style: TextStyle(fontSize: 11.5,
                    fontWeight: FontWeight.w700, color: t.porClave(c['estado']))),
              ),
            ]),
            const SizedBox(height: 12),
            // Deshabilitado si el escritorio no esta escuchando: guacd no
            // tendria a que conectarse y la vista web se quedaria en una
            // pantalla negra sin explicar por que.
            _BotonEscritorio(conexion: c, t: t),
          ])),
        )),
      ],
    );
  }
}

class _BotonEscritorio extends StatelessWidget {
  final Map<String, dynamic> conexion;
  final Tono t;
  const _BotonEscritorio({required this.conexion, required this.t});

  @override
  Widget build(BuildContext context) {
    final listo = conexion['escritorio_listo'] == true;
    final enUso = conexion['activa'] == true;

    return SizedBox(
      width: double.infinity,
      child: FilledButton.tonalIcon(
        onPressed: listo
            ? () => Navigator.push(context, MaterialPageRoute(
                  builder: (_) => PantallaEscritorio(
                    conexion: conexion['conexion'] as String,
                    usuario: conexion['usuario'] as String?,
                  ),
                ))
            : null,
        icon: Icon(listo ? Icons.visibility_outlined : Icons.videocam_off_outlined,
            size: 18),
        label: Text(
          listo
              ? (enUso ? 'Ver lo que esta haciendo' : 'Abrir el escritorio')
              : 'El escritorio no responde',
          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
        ),
        style: FilledButton.styleFrom(
          backgroundColor: listo ? t.brandSoft : t.surface2,
          foregroundColor: listo ? t.brand : t.text3,
          minimumSize: const Size.fromHeight(42),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
    );
  }
}

class _Alertas extends StatelessWidget {
  final Map<String, dynamic>? datos;
  const _Alertas({this.datos});
  @override
  Widget build(BuildContext context) {
    if (datos == null) return const SizedBox();
    final t = Theme.of(context).extension<Tono>()!;
    final al = (datos!['alertas'] as List).cast<Map<String, dynamic>>();
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      itemCount: al.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) {
        final a = al[i];
        return Tarjeta(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            _Pastilla(
              icono: a['tono'] == 'ok' ? Icons.check_rounded : Icons.error_outline,
              t: t, tono: a['tono'] == 'mute' ? null : a['tono']),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                  color: a['nivel'] == 'alta' ? t.suaveporClave(a['tono']) : t.surface2,
                  borderRadius: BorderRadius.circular(99)),
              child: Text(
                {'alta': 'Alta', 'media': 'Media', 'baja': 'Baja'}[a['nivel']] ?? a['nivel'],
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700,
                    color: a['nivel'] == 'alta' ? t.porClave(a['tono']) : t.text3)),
            ),
          ]),
          const SizedBox(height: 13),
          Text(a['que'], style: const TextStyle(fontSize: 15.5,
              fontWeight: FontWeight.w700, height: 1.35)),
          const SizedBox(height: 11),
          Container(
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(color: t.surface2, borderRadius: BorderRadius.circular(12)),
            child: Text(a['consejo'], style: TextStyle(fontSize: 13, color: t.text2, height: 1.5)),
          ),
        ]));
      },
    );
  }
}

class _ErrorVista extends StatelessWidget {
  final ApiError error;
  final Future<void> Function() onReintentar;
  const _ErrorVista({required this.error, required this.onReintentar});
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<Tono>()!;
    return Center(child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(
          width: 80, height: 80,
          decoration: BoxDecoration(color: t.critSoft, borderRadius: BorderRadius.circular(28)),
          child: Icon(Icons.cloud_off_outlined, size: 38, color: t.crit),
        ),
        const SizedBox(height: 22),
        Text(error.mensaje, textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
        if (error.pista != null) ...[
          const SizedBox(height: 12),
          Text(error.pista!, textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14.5, color: t.text2, height: 1.5)),
        ],
        const SizedBox(height: 26),
        FilledButton(
          onPressed: onReintentar,
          style: FilledButton.styleFrom(backgroundColor: t.brand,
              minimumSize: const Size(200, 52),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
          child: const Text('Reintentar', style: TextStyle(fontWeight: FontWeight.w700)),
        ),
        TextButton(
          onPressed: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const Config())),
          child: const Text('Revisar los ajustes'),
        ),
      ]),
    ));
  }
}

class _AvisoSinConexion extends StatelessWidget {
  final ApiError error;
  const _AvisoSinConexion({required this.error});
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<Tono>()!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      decoration: BoxDecoration(color: t.warnSoft, borderRadius: BorderRadius.circular(16)),
      child: Row(children: [
        Icon(Icons.wifi_off, size: 18, color: t.warn),
        const SizedBox(width: 11),
        Expanded(child: Text('Mostrando los ultimos datos. ${error.mensaje}.',
            style: TextStyle(fontSize: 12.5, color: t.warn, fontWeight: FontWeight.w600))),
      ]),
    );
  }
}
