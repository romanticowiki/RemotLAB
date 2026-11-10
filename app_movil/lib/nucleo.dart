// ============================================================================
// Nucleo compartido: colores, cliente de la API y ajustes persistentes.
//
// Vive fuera de main.dart para que las pantallas de bloqueo y de escritorio
// remoto puedan usarlo sin que se formen importaciones circulares. main.dart
// lo reexporta, asi que desde fuera la app se sigue viendo como un solo modulo.
// ============================================================================

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

// ---------------------------------------------------------------- colores

class C {
  static const brand = Color(0xFF096957);
  static const brandSoft = Color(0xFFDFF3EE);
  static const ok = Color(0xFF146B34);
  static const okSoft = Color(0xFFE1F5E8);
  static const warn = Color(0xFF8F4408);
  static const warnSoft = Color(0xFFFCF2E2);
  static const crit = Color(0xFFA81A1A);
  static const critSoft = Color(0xFFFCE9E9);

  static const bg = Color(0xFFEFF3F1);
  static const surface = Colors.white;
  static const surface2 = Color(0xFFF2F6F4);
  static const line = Color(0xFFE3EAE7);
  static const text = Color(0xFF14201D);
  static const text2 = Color(0xFF5A6763);
  static const text3 = Color(0xFF5D6A66);

  // Modo oscuro
  static const dBrand = Color(0xFF2DD4B0);
  static const dBrandSoft = Color(0xFF123833);
  static const dOk = Color(0xFF4ADE80);
  static const dOkSoft = Color(0xFF14321F);
  static const dWarn = Color(0xFFFBBF24);
  static const dWarnSoft = Color(0xFF3A2B0C);
  static const dCrit = Color(0xFFF87171);
  static const dCritSoft = Color(0xFF3B1B1B);
  static const dBg = Color(0xFF0E1412);
  static const dSurface = Color(0xFF182120);
  static const dSurface2 = Color(0xFF1F2A28);
  static const dLine = Color(0xFF2A3634);
  static const dText = Color(0xFFE9EFEC);
  static const dText2 = Color(0xFFA4B0AC);
  static const dText3 = Color(0xFF8D9B97);
}

/// Los colores de estado viven aqui y no sueltos por los widgets: un color
/// significa lo mismo en toda la app y en los dos temas.
@immutable
class Tono extends ThemeExtension<Tono> {
  final Color brand, brandSoft, ok, okSoft, warn, warnSoft, crit, critSoft;
  final Color surface2, line, text2, text3;

  const Tono({
    required this.brand, required this.brandSoft,
    required this.ok, required this.okSoft,
    required this.warn, required this.warnSoft,
    required this.crit, required this.critSoft,
    required this.surface2, required this.line,
    required this.text2, required this.text3,
  });

  static const claro = Tono(
    brand: C.brand, brandSoft: C.brandSoft, ok: C.ok, okSoft: C.okSoft,
    warn: C.warn, warnSoft: C.warnSoft, crit: C.crit, critSoft: C.critSoft,
    surface2: C.surface2, line: C.line, text2: C.text2, text3: C.text3);

  static const oscuro = Tono(
    brand: C.dBrand, brandSoft: C.dBrandSoft, ok: C.dOk, okSoft: C.dOkSoft,
    warn: C.dWarn, warnSoft: C.dWarnSoft, crit: C.dCrit, critSoft: C.dCritSoft,
    surface2: C.dSurface2, line: C.dLine, text2: C.dText2, text3: C.dText3);

  Color porClave(String k) =>
      k == 'ok' ? ok : k == 'warn' ? warn : k == 'crit' ? crit : k == 'live' ? brand : text3;
  Color suaveporClave(String k) =>
      k == 'ok' ? okSoft : k == 'warn' ? warnSoft : k == 'crit' ? critSoft : k == 'live' ? brandSoft : surface2;

  @override
  Tono copyWith() => this;
  @override
  Tono lerp(ThemeExtension<Tono>? other, double t) => other as Tono? ?? this;
}

// ---------------------------------------------------------------- API

class ApiError implements Exception {
  final String mensaje;
  final String? pista;
  ApiError(this.mensaje, [this.pista]);
  @override
  String toString() => mensaje;
}

/// Datos que hacen falta para abrir el escritorio de una conexion.
class AccesoEscritorio {
  /// URL del portal de Guacamole con la sesion ya iniciada.
  final String url;

  /// Segundos que la API garantiza que esa sesion sigue siendo valida.
  final int venceEn;

  final String conexion;

  AccesoEscritorio({required this.url, required this.venceEn, required this.conexion});
}

class Api {
  final String base;
  final String token;
  Api(this.base, this.token);

  Map<String, String> get _cabeceras => {'Authorization': 'Bearer $token'};

  Future<Map<String, dynamic>> estado() async =>
      await _pedir('/api/v1/estado') as Map<String, dynamic>;

  /// Pide a la API una sesion de Guacamole para esa conexion.
  ///
  /// La contrasena de Guacamole nunca llega al telefono: la API se autentica
  /// por su cuenta y devuelve la URL ya firmada. Si el APK se descompila, ahi
  /// no hay credenciales del laboratorio que sacar.
  Future<AccesoEscritorio> escritorio(String conexion) async {
    final d = await _pedir(
        '/api/v1/escritorio?conexion=${Uri.encodeQueryComponent(conexion)}',
        segundos: 20) as Map<String, dynamic>;
    return AccesoEscritorio(
      url: d['url'] as String,
      venceEn: (d['vence_en'] as num?)?.toInt() ?? 1800,
      conexion: d['conexion'] as String? ?? conexion,
    );
  }

  Future<dynamic> _pedir(String ruta, {int segundos = 12}) async {
    final uri = Uri.parse('$base$ruta');
    try {
      final r = await http
          .get(uri, headers: _cabeceras)
          .timeout(Duration(seconds: segundos));

      if (r.statusCode == 401) {
        throw ApiError('El token no es valido',
            'Revisa api_token en secrets.yml del servidor.');
      }
      if (r.statusCode != 200) {
        // La API manda el motivo en el cuerpo. Ensenarlo tal cual convierte un
        // "502" opaco en algo que se puede arreglar sin abrir una terminal.
        String detalle = 'El servidor respondio ${r.statusCode}';
        String? pista;
        try {
          final e = json.decode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
          if (e['error'] != null) detalle = e['error'] as String;
          if (e['detalle'] != null) pista = e['detalle'] as String;
        } catch (_) {
          // Cuerpo no-JSON: nos quedamos con el codigo, que ya dice algo.
        }
        throw ApiError(detalle, pista);
      }
      return json.decode(utf8.decode(r.bodyBytes));
    } on TimeoutException {
      throw ApiError('El servidor no respondio a tiempo',
          'Puede estar apagado, o el puerto 8000 cerrado en el security group.');
    } on FormatException {
      throw ApiError('La respuesta no es JSON valido');
    } catch (e) {
      if (e is ApiError) rethrow;
      throw ApiError('No se pudo conectar',
          'Comprueba la direccion del servidor y tu conexion.');
    }
  }
}

// ---------------------------------------------------------------- ajustes

class Ajustes extends ChangeNotifier {
  String servidor = '';
  String token = '';
  bool oscuro = false;
  int refrescoSeg = 10;
  bool cargado = false;

  // Bloqueo de la app
  bool bloqueoActivo = false;
  bool usarBiometrico = true;
  String _pinSal = '';
  String _pinHash = '';

  bool get tienePin => _pinHash.isNotEmpty;

  Future<void> cargar() async {
    final p = await SharedPreferences.getInstance();
    servidor = p.getString('servidor') ?? '';
    token = p.getString('token') ?? '';
    oscuro = p.getBool('oscuro') ?? false;
    refrescoSeg = p.getInt('refresco') ?? 10;
    bloqueoActivo = p.getBool('bloqueo') ?? false;
    usarBiometrico = p.getBool('biometrico') ?? true;
    _pinSal = p.getString('pin_sal') ?? '';
    _pinHash = p.getString('pin_hash') ?? '';
    cargado = true;
    notifyListeners();
  }

  Future<void> guardar({String? s, String? t, bool? o, int? r,
      bool? bloqueo, bool? biometrico}) async {
    final p = await SharedPreferences.getInstance();
    if (s != null) { servidor = s.trim(); await p.setString('servidor', servidor); }
    if (t != null) { token = t.trim(); await p.setString('token', token); }
    if (o != null) { oscuro = o; await p.setBool('oscuro', o); }
    if (r != null) { refrescoSeg = r; await p.setInt('refresco', r); }
    if (bloqueo != null) { bloqueoActivo = bloqueo; await p.setBool('bloqueo', bloqueo); }
    if (biometrico != null) { usarBiometrico = biometrico; await p.setBool('biometrico', biometrico); }
    notifyListeners();
  }

  /// Guarda el PIN como SHA-256 de (sal + PIN), nunca en claro.
  ///
  /// El sal es distinto en cada telefono. Sin el, un PIN de 6 digitos son solo
  /// un millon de combinaciones: cualquiera con el fichero de preferencias
  /// tendria una tabla precalculada de todos los hashes posibles en segundos.
  /// Con sal por dispositivo esa tabla hay que rehacerla para cada telefono.
  ///
  /// Que quede claro lo que esto es y lo que no: protege frente a alguien que
  /// toma el telefono desbloqueado, no frente a un analisis forense del
  /// dispositivo. Lo que de verdad guarda el token es el cifrado de Android.
  Future<void> definirPin(String pin) async {
    final p = await SharedPreferences.getInstance();
    final azar = Random.secure();
    final sal = List<int>.generate(16, (_) => azar.nextInt(256));
    _pinSal = base64Encode(sal);
    _pinHash = _hashear(pin, _pinSal);
    await p.setString('pin_sal', _pinSal);
    await p.setString('pin_hash', _pinHash);
    notifyListeners();
  }

  bool comprobarPin(String pin) {
    if (_pinHash.isEmpty) return false;
    // Comparacion en tiempo constante: con == , el tiempo de respuesta filtra
    // cuantos caracteres del hash coinciden. Aqui casi no importa (son 6
    // digitos y hay bloqueo por intentos), pero comparar hashes asi es la
    // costumbre correcta y no cuesta nada.
    final calculado = _hashear(pin, _pinSal);
    var iguales = calculado.length == _pinHash.length ? 0 : 1;
    for (var i = 0; i < calculado.length && i < _pinHash.length; i++) {
      iguales |= calculado.codeUnitAt(i) ^ _pinHash.codeUnitAt(i);
    }
    return iguales == 0;
  }

  Future<void> quitarBloqueo() async {
    final p = await SharedPreferences.getInstance();
    _pinSal = '';
    _pinHash = '';
    bloqueoActivo = false;
    await p.remove('pin_sal');
    await p.remove('pin_hash');
    await p.setBool('bloqueo', false);
    notifyListeners();
  }

  static String _hashear(String pin, String sal) =>
      sha256.convert(utf8.encode('$sal|$pin')).toString();

  bool get configurado => servidor.isNotEmpty && token.isNotEmpty;
}

final ajustes = Ajustes();
