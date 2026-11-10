// Pruebas de la app de Aula Remota.
//
// Se centran en lo que romperia sin avisar: que un fallo de red se convierta
// en un mensaje accionable en vez de en una excepcion suelta, y que los
// colores de estado sean los mismos en los dos temas.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aula_remota/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PIN de bloqueo', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('acepta el PIN correcto y rechaza el resto', () async {
      final a = Ajustes();
      await a.definirPin('418302');
      expect(a.comprobarPin('418302'), isTrue);
      expect(a.comprobarPin('418303'), isFalse);
      expect(a.comprobarPin(''), isFalse);
    });

    test('sin PIN definido no se entra con nada', () {
      expect(Ajustes().comprobarPin('000000'), isFalse);
    });

    test('el PIN no queda guardado en claro', () async {
      final a = Ajustes();
      await a.definirPin('418302');
      final p = await SharedPreferences.getInstance();
      // Lo unico que puede haber en disco es el hash y el sal.
      for (final k in p.getKeys()) {
        expect(p.get(k).toString(), isNot(contains('418302')),
            reason: 'la clave $k contiene el PIN tal cual');
      }
      expect(p.getString('pin_hash'), isNotNull);
      expect(p.getString('pin_sal'), isNotNull);
    });

    test('dos telefonos con el mismo PIN no comparten hash', () async {
      final a = Ajustes();
      await a.definirPin('418302');
      final primero = (await SharedPreferences.getInstance()).getString('pin_hash');

      SharedPreferences.setMockInitialValues({});
      final b = Ajustes();
      await b.definirPin('418302');
      final segundo = (await SharedPreferences.getInstance()).getString('pin_hash');

      // Si coincidieran, una tabla precalculada valdria para cualquier telefono.
      expect(primero, isNot(equals(segundo)));
    });

    test('quitar el bloqueo borra el PIN', () async {
      final a = Ajustes();
      await a.definirPin('418302');
      await a.quitarBloqueo();
      expect(a.tienePin, isFalse);
      expect(a.comprobarPin('418302'), isFalse);
    });
  });

  group('ApiError', () {
    test('lleva mensaje y pista accionable', () {
      final e = ApiError('El token no es valido', 'Revisa api_token.');
      expect(e.mensaje, 'El token no es valido');
      expect(e.pista, isNotNull);
      expect(e.toString(), contains('token'));
    });

    test('la pista es opcional', () {
      expect(ApiError('Fallo').pista, isNull);
    });
  });

  group('Tono', () {
    test('cada clave de estado devuelve un color distinto', () {
      const t = Tono.claro;
      final colores = {
        t.porClave('ok'), t.porClave('warn'), t.porClave('crit'), t.porClave('live'),
      };
      // Si dos estados comparten color, el usuario no puede distinguirlos.
      expect(colores.length, 4);
    });

    test('una clave desconocida no revienta', () {
      expect(Tono.claro.porClave('lo-que-sea'), isNotNull);
    });

    test('el modo oscuro define los mismos estados que el claro', () {
      for (final k in ['ok', 'warn', 'crit', 'live']) {
        expect(Tono.oscuro.porClave(k), isNotNull, reason: 'falta $k en oscuro');
        expect(Tono.oscuro.suaveporClave(k), isNotNull, reason: 'falta $k suave');
      }
    });
  });

  testWidgets('arranca sin configuracion y pide servidor y token',
      (WidgetTester tester) async {
    // La pantalla lee los colores de estado del ThemeExtension. Montarla sin
    // el revienta con un null, asi que el tema del test tiene que llevarlo,
    // igual que lo lleva la app de verdad.
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData.light().copyWith(extensions: const [Tono.claro]),
      home: const Config(primeraVez: true),
    ));
    await tester.pump();

    expect(find.text('Aula Remota'), findsOneWidget);
    expect(find.text('Direccion del servidor'), findsOneWidget);
    expect(find.text('Token de acceso'), findsOneWidget);
  });
}
