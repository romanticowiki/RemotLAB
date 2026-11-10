// ============================================================================
// Ver el escritorio de un alumno desde el telefono.
//
// POR QUE UNA VISTA WEB Y NO UN CLIENTE VNC EN DART
// -------------------------------------------------
// Guacamole ya resuelve el problema entero: habla RFB con el servidor VNC,
// comprime, escala, gestiona teclado, raton y portapapeles, y se reconecta
// solo. Reimplementar eso en Dart serian semanas para acabar con menos
// funciones. La app abre el mismo portal que usa el maestro desde el navegador,
// con la sesion ya iniciada por la API.
//
// EL ALUMNO NO PIERDE SU SESION
// -----------------------------
// El servidor VNC arranca con -AlwaysShared (rol vnc de Ansible). Sin esa
// bandera, TigerVNC expulsa al visor anterior cuando entra uno nuevo: abrir el
// escritorio desde aqui echaria al alumno de su propia clase. Con ella, los dos
// ven la misma pantalla a la vez.
//
// MODO OBSERVAR
// -------------
// Al entrar, la vista NO acepta toques. Guacamole da control real de teclado y
// raton, y un roce accidental en el telefono mueve el raton del alumno en mitad
// de su examen. Tomar el control es un acto deliberado: hay que pulsar un boton
// que ademas avisa de lo que implica.
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'nucleo.dart';

class PantallaEscritorio extends StatefulWidget {
  final String conexion;

  /// Quien esta usando ese escritorio ahora, si es que hay alguien.
  final String? usuario;

  const PantallaEscritorio({super.key, required this.conexion, this.usuario});

  @override
  State<PantallaEscritorio> createState() => _PantallaEscritorioState();
}

class _PantallaEscritorioState extends State<PantallaEscritorio> {
  WebViewController? _web;
  ApiError? _error;
  bool _cargando = true;
  bool _control = false;
  int _progreso = 0;

  @override
  void initState() {
    super.initState();
    // Horizontal: un escritorio 1280x800 en vertical se ve como una tira
    // ilegible. Al salir se restaura, en dispose().
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _abrir();
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
  }

  Future<void> _abrir() async {
    setState(() { _cargando = true; _error = null; });
    try {
      final acceso =
          await Api(ajustes.servidor, ajustes.token).escritorio(widget.conexion);

      final c = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        // Guacamole pinta sobre un canvas negro. Sin esto se ve un parpadeo
        // blanco en cada carga que en modo oscuro molesta bastante.
        ..setBackgroundColor(Colors.black)
        ..setNavigationDelegate(NavigationDelegate(
          onProgress: (p) { if (mounted) setState(() => _progreso = p); },
          onPageFinished: (_) { if (mounted) setState(() => _cargando = false); },
          onWebResourceError: (e) {
            // Los recursos secundarios fallan a veces sin que la sesion se
            // rompa. Solo se convierte en pantalla de error si falla el
            // documento principal.
            if (!e.isForMainFrame!) return;
            if (!mounted) return;
            setState(() {
              _cargando = false;
              _error = ApiError('No se pudo abrir el portal',
                  'El puerto 8080 tiene que estar abierto en el security group.');
            });
          },
        ))
        ..loadRequest(Uri.parse(acceso.url));

      if (!mounted) return;
      setState(() { _web = c; });
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() { _error = e; _cargando = false; });
    }
  }

  void _cambiarControl() {
    if (_control) {
      setState(() => _control = false);
      return;
    }
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tomar el control'),
        content: Text(
          widget.usuario == null
              ? 'Vas a manejar el teclado y el raton de este escritorio.'
              : '${widget.usuario} esta usando este escritorio ahora mismo. '
                  'Si tomas el control, vera moverse su raton.',
          style: const TextStyle(height: 1.5),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar')),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              setState(() => _control = true);
            },
            child: const Text('Tomar el control'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<Tono>()!;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        titleSpacing: 4,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.conexion,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          Text(
            _control
                ? 'Tienes el control'
                : (widget.usuario != null
                    ? 'Observando a ${widget.usuario}'
                    : 'Solo observando'),
            style: TextStyle(
                fontSize: 11.5,
                color: _control ? t.warn : Colors.white70),
          ),
        ]),
        actions: [
          if (_error == null)
            TextButton.icon(
              onPressed: _cambiarControl,
              icon: Icon(_control ? Icons.visibility_outlined : Icons.mouse_outlined,
                  size: 18),
              label: Text(_control ? 'Solo mirar' : 'Controlar'),
              style: TextButton.styleFrom(
                  foregroundColor: _control ? t.warn : Colors.white),
            ),
          const SizedBox(width: 4),
        ],
        bottom: _cargando
            ? PreferredSize(
                preferredSize: const Size.fromHeight(2),
                child: LinearProgressIndicator(
                  value: _progreso == 0 ? null : _progreso / 100,
                  minHeight: 2,
                  backgroundColor: Colors.white12,
                  color: t.brand,
                ),
              )
            : null,
      ),
      body: _error != null
          ? _Fallo(error: _error!, onReintentar: _abrir, t: t)
          : _web == null
              ? const Center(child: CircularProgressIndicator())
              : Stack(children: [
                  // AbsorbPointer es lo que implementa el modo observar: la
                  // vista se pinta y se actualiza igual, pero ningun toque
                  // llega hasta ella.
                  AbsorbPointer(
                    absorbing: !_control,
                    child: WebViewWidget(controller: _web!),
                  ),
                  if (!_control && !_cargando)
                    Positioned(
                      left: 0, right: 0, bottom: 12,
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: const Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.visibility_outlined,
                                size: 15, color: Colors.white70),
                            SizedBox(width: 7),
                            Text('Tus toques no llegan al escritorio',
                                style: TextStyle(fontSize: 11.5, color: Colors.white70)),
                          ]),
                        ),
                      ),
                    ),
                ]),
    );
  }
}

class _Fallo extends StatelessWidget {
  final ApiError error;
  final VoidCallback onReintentar;
  final Tono t;
  const _Fallo({required this.error, required this.onReintentar, required this.t});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.desktop_access_disabled_outlined, size: 44, color: t.crit),
          const SizedBox(height: 16),
          Text(error.mensaje,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 17, fontWeight: FontWeight.w700, color: Colors.white)),
          if (error.pista != null) ...[
            const SizedBox(height: 8),
            Text(error.pista!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 13.5, height: 1.5, color: Colors.white70)),
          ],
          const SizedBox(height: 22),
          FilledButton(
            onPressed: onReintentar,
            style: FilledButton.styleFrom(backgroundColor: t.brand),
            child: const Text('Reintentar'),
          ),
        ]),
      ),
    );
  }
}
