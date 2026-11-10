// ============================================================================
// Bloqueo de la app: huella o rostro, con PIN como respaldo.
//
// COMO FUNCIONA DE VERDAD LA BIOMETRIA
// ------------------------------------
// La app NUNCA ve la huella ni la cara. Le pide al sistema operativo "valida a
// quien tenga este telefono en la mano" y recibe un si o un no. El dato
// biometrico se queda dentro del enclave seguro del chip, al que ninguna app
// tiene acceso. Por eso este fichero no guarda nada biometrico: solo un
// booleano que dice si hay que preguntar.
//
// POR QUE SIEMPRE HAY PIN
// -----------------------
// La huella falla: dedos mojados, pantalla rota, sensor sucio, o un telefono
// que directamente no tiene sensor. Si la biometria fuera el unico camino, un
// fallo del sensor dejaria al administrador fuera de su propio laboratorio.
// Por eso el PIN se define ANTES de ofrecer la huella, no despues. Es el mismo
// orden que usan las apps de banco, y por el mismo motivo.
//
// TRES INTENTOS Y ESPERA
// ----------------------
// Un PIN de 6 digitos se prueba entero en minutos si se deja teclear sin
// limite. Tras 3 fallos hay una espera que crece; no bloquea para siempre,
// porque dejar al dueno fuera de forma permanente por teclear mal es peor
// remedio que la enfermedad.
// ============================================================================

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

import 'nucleo.dart';

final _auth = LocalAuthentication();

/// Que puede ofrecer este telefono. Se consulta una vez y se recuerda: la
/// llamada cruza al codigo nativo y en pantallas que se repintan seguido se
/// notaria.
class Biometria {
  static bool? _disponible;
  static List<BiometricType> tipos = const [];

  static Future<bool> disponible() async {
    if (_disponible != null) return _disponible!;
    try {
      final soportado = await _auth.isDeviceSupported();
      final hay = await _auth.canCheckBiometrics;
      tipos = await _auth.getAvailableBiometrics();
      _disponible = soportado && hay && tipos.isNotEmpty;
    } catch (_) {
      _disponible = false;
    }
    return _disponible!;
  }

  /// Nombre en castellano de lo que el telefono realmente tiene, para no
  /// prometer "huella" en un telefono que solo hace reconocimiento facial.
  static String get nombre {
    if (tipos.contains(BiometricType.face)) return 'reconocimiento facial';
    if (tipos.contains(BiometricType.iris)) return 'lector de iris';
    if (tipos.contains(BiometricType.fingerprint) ||
        tipos.contains(BiometricType.strong)) {
      return 'huella';
    }
    return 'biometria';
  }

  static IconData get icono =>
      tipos.contains(BiometricType.face) ? Icons.face_outlined : Icons.fingerprint;

  /// Devuelve true si el sistema valido a la persona.
  ///
  /// Los fallos se traducen a un texto util en vez de propagar la excepcion:
  /// "noBiometricsEnrolled" no le dice nada a nadie, "no tienes ninguna huella
  /// registrada en el telefono" si.
  static Future<(bool, String?)> pedir(String motivo) async {
    try {
      final ok = await _auth.authenticate(
        localizedReason: motivo,
        biometricOnly: true,
        persistAcrossBackgrounding: true,
      );
      return (ok, ok ? null : 'No se reconocio. Intenta otra vez o usa tu PIN.');
    } on LocalAuthException catch (e) {
      return (false, switch (e.code) {
        LocalAuthExceptionCode.noBiometricsEnrolled =>
          'No tienes ninguna huella ni rostro registrado en el telefono.',
        LocalAuthExceptionCode.noBiometricHardware =>
          'Este telefono no tiene sensor biometrico.',
        LocalAuthExceptionCode.biometricLockout =>
          'El telefono bloqueo el sensor por demasiados intentos. Usa tu PIN.',
        LocalAuthExceptionCode.userCanceled => null, // cancelar no es un error
        _ => 'No se pudo usar $nombre. Entra con tu PIN.',
      });
    } catch (_) {
      return (false, 'No se pudo usar ${Biometria.nombre}. Entra con tu PIN.');
    }
  }
}

// ---------------------------------------------------------------- desbloqueo

/// Pantalla que tapa la app hasta que la persona se identifica.
class PantallaBloqueo extends StatefulWidget {
  /// Se llama cuando la identificacion es correcta.
  final VoidCallback onEntrar;
  const PantallaBloqueo({super.key, required this.onEntrar});

  @override
  State<PantallaBloqueo> createState() => _PantallaBloqueoState();
}

class _PantallaBloqueoState extends State<PantallaBloqueo> {
  String _pin = '';
  String? _aviso;
  bool _mostrandoPin = false;
  bool _hayBiometria = false;
  int _fallos = 0;
  DateTime? _esperaHasta;
  Timer? _cuenta;

  @override
  void initState() {
    super.initState();
    _arrancar();
  }

  @override
  void dispose() {
    _cuenta?.cancel();
    super.dispose();
  }

  Future<void> _arrancar() async {
    _hayBiometria = await Biometria.disponible();
    if (!mounted) return;
    // Si hay biometria y esta activada, se lanza sola al abrir: es lo que hace
    // que la app se sienta como una app de banco y no como un formulario.
    if (_hayBiometria && ajustes.usarBiometrico) {
      _intentarBiometria();
    } else {
      setState(() => _mostrandoPin = true);
    }
  }

  Future<void> _intentarBiometria() async {
    final (ok, error) = await Biometria.pedir('Entra a Aula Remota');
    if (!mounted) return;
    if (ok) {
      widget.onEntrar();
      return;
    }
    setState(() {
      _mostrandoPin = true;
      _aviso = error;
    });
  }

  bool get _enEspera =>
      _esperaHasta != null && DateTime.now().isBefore(_esperaHasta!);

  int get _segundosRestantes =>
      _esperaHasta == null ? 0 : _esperaHasta!.difference(DateTime.now()).inSeconds + 1;

  void _teclear(String d) {
    if (_enEspera || _pin.length >= 6) return;
    HapticFeedback.selectionClick();
    setState(() {
      _pin += d;
      _aviso = null;
    });
    if (_pin.length == 6) _comprobar();
  }

  void _borrar() {
    if (_pin.isEmpty) return;
    HapticFeedback.selectionClick();
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  void _comprobar() {
    if (ajustes.comprobarPin(_pin)) {
      widget.onEntrar();
      return;
    }
    HapticFeedback.heavyImpact();
    _fallos++;
    setState(() {
      _pin = '';
      if (_fallos >= 3) {
        // 15 s, 30 s, 60 s... Crece rapido pero nunca deja fuera para siempre.
        final espera = 15 * (1 << (_fallos - 3));
        _esperaHasta = DateTime.now().add(Duration(seconds: espera.clamp(15, 300)));
        _aviso = null;
        _cuenta?.cancel();
        _cuenta = Timer.periodic(const Duration(seconds: 1), (t) {
          if (!mounted) { t.cancel(); return; }
          setState(() {});
          if (!_enEspera) t.cancel();
        });
      } else {
        _aviso = 'PIN incorrecto. Te quedan ${3 - _fallos} intentos.';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<Tono>()!;
    final texto = Theme.of(context).textTheme.bodyLarge!.color;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(children: [
            const Spacer(flex: 2),
            Container(
              width: 92, height: 92,
              decoration: BoxDecoration(
                  color: t.brandSoft, borderRadius: BorderRadius.circular(30)),
              child: Icon(_hayBiometria && ajustes.usarBiometrico
                      ? Biometria.icono : Icons.lock_outline,
                  size: 44, color: t.brand),
            ),
            const SizedBox(height: 24),
            Text('Confirma que eres tu',
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800,
                    letterSpacing: -0.8, color: texto)),
            const SizedBox(height: 8),
            Text(
              _mostrandoPin
                  ? 'Escribe tu PIN de 6 digitos.'
                  : 'Usa tu ${Biometria.nombre} para entrar.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, color: t.text2, height: 1.5),
            ),
            const SizedBox(height: 28),

            if (_mostrandoPin) ...[
              _Puntos(largo: _pin.length, t: t),
              const SizedBox(height: 18),
              if (_enEspera)
                _Aviso(
                  tono: 'warn', t: t,
                  texto: 'Demasiados intentos. Espera $_segundosRestantes s.',
                )
              else if (_aviso != null)
                _Aviso(tono: 'crit', t: t, texto: _aviso!),
              const Spacer(),
              _Teclado(
                habilitado: !_enEspera,
                onDigito: _teclear,
                onBorrar: _borrar,
                t: t,
              ),
              const SizedBox(height: 12),
              if (_hayBiometria && ajustes.usarBiometrico)
                TextButton.icon(
                  onPressed: _enEspera ? null : _intentarBiometria,
                  icon: Icon(Biometria.icono, size: 20),
                  label: Text('Usar ${Biometria.nombre}'),
                  style: TextButton.styleFrom(foregroundColor: t.brand),
                ),
            ] else ...[
              const Spacer(),
              FilledButton.icon(
                onPressed: _intentarBiometria,
                icon: Icon(Biometria.icono),
                label: const Text('Validar con el dispositivo'),
                style: FilledButton.styleFrom(
                  backgroundColor: t.brand,
                  minimumSize: const Size.fromHeight(54),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                ),
              ),
              const SizedBox(height: 6),
              TextButton(
                onPressed: () => setState(() => _mostrandoPin = true),
                style: TextButton.styleFrom(foregroundColor: t.brand),
                child: const Text('Usar PIN'),
              ),
            ],
            const SizedBox(height: 12),
          ]),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- crear PIN

/// Define el PIN por primera vez: se teclea, y luego se repite para confirmar.
///
/// La repeticion no es burocracia: un PIN mal tecleado una sola vez deja la app
/// inaccesible con un codigo que nadie conoce, y la unica salida seria
/// reinstalar y volver a configurar servidor y token.
class PantallaCrearPin extends StatefulWidget {
  const PantallaCrearPin({super.key});
  @override
  State<PantallaCrearPin> createState() => _PantallaCrearPinState();
}

class _PantallaCrearPinState extends State<PantallaCrearPin> {
  String _pin = '';
  String? _primero;
  String? _aviso;

  void _teclear(String d) {
    if (_pin.length >= 6) return;
    HapticFeedback.selectionClick();
    setState(() { _pin += d; _aviso = null; });
    if (_pin.length == 6) _siguiente();
  }

  void _borrar() {
    if (_pin.isEmpty) return;
    HapticFeedback.selectionClick();
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  Future<void> _siguiente() async {
    if (_primero == null) {
      // Cuatro digitos iguales o una escalera se adivinan a la primera mirando
      // el rastro de dedos en la pantalla.
      if (_esDebil(_pin)) {
        setState(() {
          _aviso = 'Ese PIN es muy facil de adivinar. Prueba otro.';
          _pin = '';
        });
        return;
      }
      setState(() { _primero = _pin; _pin = ''; });
      return;
    }
    if (_primero != _pin) {
      HapticFeedback.heavyImpact();
      setState(() {
        _aviso = 'No coincide con el primero. Empieza otra vez.';
        _primero = null;
        _pin = '';
      });
      return;
    }
    await ajustes.definirPin(_pin);
    await ajustes.guardar(bloqueo: true);
    if (mounted) Navigator.of(context).pop(true);
  }

  static bool _esDebil(String p) {
    if (p.split('').toSet().length == 1) return true;          // 111111
    var sube = true, baja = true;
    for (var i = 1; i < p.length; i++) {
      if (p.codeUnitAt(i) != p.codeUnitAt(i - 1) + 1) sube = false;
      if (p.codeUnitAt(i) != p.codeUnitAt(i - 1) - 1) baja = false;
    }
    return sube || baja;                                        // 123456 / 654321
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<Tono>()!;
    final texto = Theme.of(context).textTheme.bodyLarge!.color;
    return Scaffold(
      appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(children: [
            const SizedBox(height: 10),
            Text(_primero == null ? 'Elige un PIN' : 'Repitelo',
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800,
                    letterSpacing: -0.8, color: texto)),
            const SizedBox(height: 8),
            Text(
              _primero == null
                  ? 'Seis digitos. Es tu respaldo si la huella falla.'
                  : 'Para asegurarnos de que no hubo un error al teclear.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, color: t.text2, height: 1.5),
            ),
            const SizedBox(height: 28),
            _Puntos(largo: _pin.length, t: t),
            const SizedBox(height: 18),
            if (_aviso != null) _Aviso(tono: 'crit', t: t, texto: _aviso!),
            const Spacer(),
            _Teclado(habilitado: true, onDigito: _teclear, onBorrar: _borrar, t: t),
            const SizedBox(height: 24),
          ]),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- piezas

class _Puntos extends StatelessWidget {
  final int largo;
  final Tono t;
  const _Puntos({required this.largo, required this.t});
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(6, (i) {
        final lleno = i < largo;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          margin: const EdgeInsets.symmetric(horizontal: 7),
          width: lleno ? 15 : 13,
          height: lleno ? 15 : 13,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: lleno ? t.brand : t.surface2,
            border: lleno ? null : Border.all(color: t.line, width: 1.5),
          ),
        );
      }),
    );
  }
}

class _Aviso extends StatelessWidget {
  final String tono, texto;
  final Tono t;
  const _Aviso({required this.tono, required this.texto, required this.t});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
          color: t.suaveporClave(tono), borderRadius: BorderRadius.circular(14)),
      child: Text(texto,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, height: 1.4, color: t.porClave(tono))),
    );
  }
}

/// Teclado propio y no el del sistema: el teclado numerico de Android ocupa
/// media pantalla, muestra sugerencias y deja el PIN a un portapapeles de
/// distancia. Con teclas grandes tambien se acierta sin mirar.
class _Teclado extends StatelessWidget {
  final bool habilitado;
  final void Function(String) onDigito;
  final VoidCallback onBorrar;
  final Tono t;
  const _Teclado({required this.habilitado, required this.onDigito,
      required this.onBorrar, required this.t});

  @override
  Widget build(BuildContext context) {
    final texto = Theme.of(context).textTheme.bodyLarge!.color;
    Widget tecla(String d) => _Tecla(
          onTap: habilitado ? () => onDigito(d) : null,
          t: t,
          hijo: Text(d, style: TextStyle(fontSize: 26, fontWeight: FontWeight.w600,
              color: habilitado ? texto : t.text3)),
        );

    return Column(children: [
      for (final fila in [['1','2','3'], ['4','5','6'], ['7','8','9']])
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: fila.map(tecla).toList()),
        ),
      Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
        // Hueco para que el 0 quede centrado bajo el 8, como en cualquier
        // teclado numerico: mover el 0 rompe la memoria muscular.
        const SizedBox(width: 78, height: 62),
        tecla('0'),
        _Tecla(
          onTap: habilitado ? onBorrar : null,
          t: t,
          hijo: Icon(Icons.backspace_outlined, size: 22, color: t.text2),
        ),
      ]),
    ]);
  }
}

class _Tecla extends StatelessWidget {
  final VoidCallback? onTap;
  final Widget hijo;
  final Tono t;
  const _Tecla({required this.onTap, required this.hijo, required this.t});
  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Container(
          width: 78, height: 62,
          alignment: Alignment.center,
          decoration: BoxDecoration(
              color: t.surface2, borderRadius: BorderRadius.circular(22)),
          child: hijo,
        ),
      ),
    );
  }
}
