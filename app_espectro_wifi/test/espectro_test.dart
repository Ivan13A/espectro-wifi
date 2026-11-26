// Pruebas del incremento 2: forma espectral, escala, conjunto sin solapamiento
// y que la pantalla se dibuje sin errores. Se corren con: flutter test
import 'package:app_espectro_wifi/main.dart';
import 'package:app_espectro_wifi/modelo/canales.dart';
import 'package:app_espectro_wifi/modelo/forma_espectral.dart';
import 'package:app_espectro_wifi/pantallas/pantalla_espectro.dart';
import 'package:app_espectro_wifi/vista/escala_espectro.dart';
import 'package:app_espectro_wifi/vista/pintor_espectro.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

List<int> numeros(List<Canal> cs) => [for (final c in cs) c.numero];

void main() {
  group('Tabla OFDM (subportadoras × 312,5 kHz)', () {
    test('tramo ocupado = (2·N_SR + 1)·Δf', () {
      expect(TablaOfdm.legacy20.tramoOcupadoMHz, closeTo(16.5625, 1e-9));
      expect(TablaOfdm.ht20.tramoOcupadoMHz, closeTo(17.8125, 1e-9));
      expect(TablaOfdm.ht40.tramoOcupadoMHz, closeTo(36.5625, 1e-9));
      expect(TablaOfdm.vht80.tramoOcupadoMHz, closeTo(76.5625, 1e-9));
      expect(TablaOfdm.vht160.tramoOcupadoMHz, closeTo(156.5625, 1e-9));
    });

    test('solo usadas = N_ST·Δf', () {
      expect(TablaOfdm.legacy20.soloUsadasMHz, closeTo(16.25, 1e-9));
      expect(TablaOfdm.ht20.soloUsadasMHz, closeTo(17.5, 1e-9));
    });

    test('el tramo ocupado nunca pasa del ancho nominal', () {
      for (final w in CatalogoCanales.anchos5) {
        final o = TablaOfdm.paraAncho(w);
        expect(o.tramoOcupadoMHz, lessThan(w.toDouble()));
      }
    });
  });

  group('Forma espectral', () {
    final c6dsss = CatalogoCanales.canales24(Modo24.dsss22)[5];
    final c6ofdm = CatalogoCanales.canales24(Modo24.ofdm20)[5];

    test('DSSS: sinc² con pico en el centro y nulos a ±11 MHz', () {
      expect(amplitudRelativa(c6dsss, 2437), 1);
      expect(amplitudRelativa(c6dsss, 2426), 0);
      expect(amplitudRelativa(c6dsss, 2448), 0);
      expect(amplitudRelativa(c6dsss, 2460), 0);
      // sinc²(0,5) = (2/π)² ≈ 0,405 a 5,5 MHz del centro.
      expect(amplitudRelativa(c6dsss, 2442.5), closeTo(0.4053, 1e-3));
      expect(amplitudRelativa(c6dsss, 2431.5), amplitudRelativa(c6dsss, 2442.5));
    });

    test('OFDM 20 MHz: plano hasta ±8,906 MHz y cero en ±10 MHz', () {
      expect(amplitudRelativa(c6ofdm, 2437 + 8.9), 1);
      expect(amplitudRelativa(c6ofdm, 2437 - 8.9), 1);
      expect(amplitudRelativa(c6ofdm, 2447), 0);
      final medio = amplitudRelativa(c6ofdm, 2437 + 9.45);
      expect(medio, greaterThan(0));
      expect(medio, lessThan(1));
    });

    test('el perfil empieza y termina en los bordes del canal, en cero', () {
      for (final c in [
        c6dsss,
        c6ofdm,
        ...CatalogoCanales.canales5(80),
        ...CatalogoCanales.canales24de40(),
      ]) {
        final p = perfilCanal(c);
        expect(p.first, (c.inicioMHz, 0.0));
        expect(p.last.$1, closeTo(c.finMHz, 1e-9));
        expect(p.last.$2, closeTo(0, 1e-9));
      }
    });
  });

  group('Conjunto sin solapamiento', () {
    test('2.4 GHz 22 MHz: 1 / 6 / 11', () {
      final libres = canalesSinSolapamiento(CatalogoCanales.canales24(Modo24.dsss22));
      expect(numeros(libres), [1, 6, 11]);
    });

    test('2.4 GHz 20 MHz: 1 / 5 / 9 / 13, tocándose en el borde', () {
      final libres = canalesSinSolapamiento(CatalogoCanales.canales24(Modo24.ofdm20));
      expect(numeros(libres), [1, 5, 9, 13]);
      expect(libres[0].finMHz, libres[1].inicioMHz);
    });

    test('2.4 GHz 40 MHz: dos bloques, 3 (2402-2442) y 11 (2442-2482)', () {
      final libres = canalesSinSolapamiento(CatalogoCanales.canales24de40());
      expect(numeros(libres), [3, 11]);
      expect((libres[0].inicioMHz, libres[0].finMHz), (2402.0, 2442.0));
      expect((libres[1].inicioMHz, libres[1].finMHz), (2442.0, 2482.0));
      expect(libres[0].solapaCon(libres[1]), isFalse);
    });

    test('5 GHz: todos los canales de un mismo ancho quedan libres', () {
      for (final w in CatalogoCanales.anchos5) {
        final cs = CatalogoCanales.canales5(w);
        expect(canalesSinSolapamiento(cs).length, cs.length);
      }
    });

    test('canales de 5 GHz que no forman bloque', () {
      expect(CatalogoCanales.canales5SinBloque(20), isEmpty);
      expect(CatalogoCanales.canales5SinBloque(40), [165]);
      expect(CatalogoCanales.canales5SinBloque(80), [165]);
      expect(CatalogoCanales.canales5SinBloque(160),
          [132, 136, 140, 144, 149, 153, 157, 161, 165]);
    });
  });

  group('Notas de 2.4 GHz', () {
    test('OFDM 20 MHz menciona el borde, la fuga y 1/6/11', () {
      final libres = canalesSinSolapamiento(CatalogoCanales.canales24(Modo24.ofdm20));
      final s = nota24(Opcion24.ofdm20, libres);
      expect(s, contains('1 / 5 / 9 / 13'));
      expect(s, contains('2422, 2442, 2462'));
      expect(s, contains('fuga'));
      expect(s, contains('12 y 13'));
      expect(s, contains('1 / 6 / 11'));
    });

    test('40 MHz dice que caben dos bloques', () {
      final libres = canalesSinSolapamiento(CatalogoCanales.canales24de40());
      final s = nota24(Opcion24.ht40, libres);
      expect(s, contains('caben 2 bloques'));
      expect(s, contains('3 (2402–2442 MHz) y 11 (2442–2482 MHz)'));
    });
  });

  group('Escala', () {
    const e = EscalaEspectro(
        fMinMHz: 2390, fMaxMHz: 2495, xIzq: 0, xDer: 420, yBase: 200, yTope: 40);

    test('bordes, ida y vuelta y potencia', () {
      expect(e.pxPorMHz, 4);
      expect(e.x(2390), 0);
      expect(e.x(2495), 420);
      expect(e.f(e.x(2437)), closeTo(2437, 1e-9));
      expect(e.y(0), 200);
      expect(e.y(1), 40);
      expect(e.yDbm(-95), 200);
      expect(e.yDbm(-20), 40);
      expect(e.yDbm(-10), 40);
    });

    test('la vista cubre toda la banda de la norma', () {
      for (final b in [Banda.ghz24, Banda.ghz5]) {
        final v = rangoVista(b), n = NormaColombia.rangoBanda(b);
        expect(v.inicioMHz, lessThan(n.inicioMHz));
        expect(v.finMHz, greaterThan(n.finMHz));
      }
    });
  });

  group('Ventana de zoom', () {
    final limite = rangoVista(Banda.ghz5); // 5140-5860

    test('la vista completa es toda la banda', () {
      final v = VentanaFrecuencia.completa(Banda.ghz5);
      expect((v.inicioMHz, v.finMHz), (5140.0, 5860.0));
    });

    test('pellizco ×2 en el centro conserva el foco bajo los dedos', () {
      final v = VentanaFrecuencia.completa(Banda.ghz5).pellizcar(
          factor: 2, fFoco: 5500, fraccionFoco: 0.5, limite: limite, anchoMinMHz: 40);
      expect((v.inicioMHz, v.finMHz), (5320.0, 5680.0));
    });

    test('el zoom no pasa del ancho mínimo ni sale de la banda', () {
      final maximo = VentanaFrecuencia.completa(Banda.ghz5).pellizcar(
          factor: 1000, fFoco: 5500, fraccionFoco: 0.5, limite: limite, anchoMinMHz: 40);
      expect(maximo.anchoMHz, 40);
      final borde = VentanaFrecuencia.completa(Banda.ghz5).pellizcar(
          factor: 4, fFoco: 5150, fraccionFoco: 0.5, limite: limite, anchoMinMHz: 40);
      expect((borde.inicioMHz, borde.finMHz), (5140.0, 5320.0));
      final alejar = const VentanaFrecuencia(5400, 5600).pellizcar(
          factor: 0.1, fFoco: 5500, fraccionFoco: 0.5, limite: limite, anchoMinMHz: 40);
      expect(alejar, VentanaFrecuencia.completa(Banda.ghz5));
    });

    test('con un dedo (factor 1) solo se desplaza', () {
      final v = const VentanaFrecuencia(5400, 5600).pellizcar(
          factor: 1, fFoco: 5500, fraccionFoco: 0.25, limite: limite, anchoMinMHz: 40);
      expect((v.inicioMHz, v.finMHz), (5450.0, 5650.0));
    });

    test('centrar en un canal respeta los bordes', () {
      const v = VentanaFrecuencia(5400, 5600);
      expect(v.centrarEn(5745, limite), const VentanaFrecuencia(5645, 5845));
      expect(v.centrarEn(5825, limite), const VentanaFrecuencia(5660, 5860));
    });
  });

  test('las etiquetas no se enciman (tocarse sí se permite)', () {
    final fila = FilaEtiquetas();
    expect(fila.reservar(0, 10), isTrue);
    expect(fila.reservar(5, 15), isFalse);
    expect(fila.reservar(10, 20), isTrue);
    expect(fila.reservar(-3, 1), isFalse);
  });

  test('nota de 5 GHz: singular con un canal sin bloque, plural con varios', () {
    String nota(int w) => nota5(
        w, CatalogoCanales.canales5(w), CatalogoCanales.canales5SinBloque(w));
    expect(nota(40), contains('El canal 165 no forma un bloque de 40 MHz'));
    expect(nota(80), contains('El canal 165 no forma un bloque de 80 MHz'));
    expect(nota(160), contains('Los canales 132, 136'));
    expect(nota(160), contains('no forman un bloque de 160 MHz'));
    expect(nota(20), isNot(contains('bloque de 20')));
  });

  group('Pantalla', () {
    Finder lienzo() =>
        find.byWidgetPredicate((w) => w is CustomPaint && w.painter is PintorEspectro);
    PintorEspectro pintor(WidgetTester t) =>
        t.widget<CustomPaint>(lienzo()).painter! as PintorEspectro;

    /// Toque simple: espera a que venza el plazo del doble toque.
    Future<void> tocar(WidgetTester t, Offset p) async {
      await t.tapAt(p);
      await t.pump(const Duration(milliseconds: 400));
      await t.pumpAndSettle();
    }

    void celular(WidgetTester t, {bool horizontal = false}) {
      // 1080×2400 px a 2,625 → ~411×914 dp, como el Honor X8.
      t.view.physicalSize = horizontal ? const Size(2400, 1080) : const Size(1080, 2400);
      t.view.devicePixelRatio = 2.625;
      addTearDown(t.view.reset);
    }

    testWidgets('se dibuja en todas las opciones y responde al toque', (tester) async {
      celular(tester);
      await tester.pumpWidget(const AppEspectro());

      // Tocar el espectro en 2437 MHz (canal 6 en 22 MHz) lo selecciona.
      final caja = tester.getRect(lienzo());
      final e = PintorEspectro.escalaPara(caja.size, pintor(tester).ventana);
      await tocar(tester, caja.topLeft + Offset(e.x(2437), e.yBase - 20));
      expect(find.textContaining('Canal 6 · centro 2437 MHz'), findsOneWidget);
      // DSSS 22 MHz: el 6 (2426-2448) se pisa 2 MHz con el 2, 7 con el 3, 12 con el 4...
      expect(find.textContaining('Se solapa con: 2 (2 MHz), 3 (7 MHz), 4 (12 MHz)'),
          findsOneWidget);

      // En vertical los anchos son segmentos: "22 MHz" arriba y "b" abajo.
      for (final o in Opcion24.values) {
        await tester.tap(find.text(o.etiqueta.split(' (').first));
        await tester.pumpAndSettle();
      }
      // Tocar una fila selecciona el canal y muestra sus solapamientos. La
      // tabla va en el scroll de la página: primero se lleva a la vista.
      await tester.ensureVisible(find.text('Centro 2422 MHz · ancho 40 MHz'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Centro 2422 MHz · ancho 40 MHz'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Canal 3 · centro 2422 MHz'), findsOneWidget);

      await tester.tap(find.text('5 GHz'));
      await tester.pumpAndSettle();
      for (final w in CatalogoCanales.anchos5) {
        await tester.tap(find.text('$w MHz'));
        await tester.pumpAndSettle();
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('5 GHz arranca con toda la banda; pellizco acerca y doble toque vuelve',
        (tester) async {
      celular(tester);
      await tester.pumpWidget(const AppEspectro());
      await tester.tap(find.text('5 GHz'));
      await tester.pumpAndSettle();

      final completa = VentanaFrecuencia.completa(Banda.ghz5);
      expect(pintor(tester).ventana, completa);
      // A escala real: el lienzo mide lo que la pantalla.
      final caja = tester.getRect(lienzo());
      expect(caja.width, closeTo(1080 / 2.625, 0.01));

      // Pellizco: dos dedos que se separan en horizontal.
      final a = await tester.startGesture(caja.center - const Offset(20, 0), pointer: 1);
      final b = await tester.startGesture(caja.center + const Offset(20, 0), pointer: 2);
      for (var i = 0; i < 10; i++) {
        await a.moveBy(const Offset(-8, 0));
        await b.moveBy(const Offset(8, 0));
        await tester.pump();
      }
      await a.up();
      await b.up();
      await tester.pumpAndSettle();
      final acercada = pintor(tester).ventana;
      expect(acercada.anchoMHz, lessThan(completa.anchoMHz / 2));
      expect(find.textContaining('Doble toque para ver toda la banda'), findsOneWidget);

      // Con zoom, tocar un canal sigue funcionando.
      final e = PintorEspectro.escalaPara(caja.size, acercada);
      final canal = CatalogoCanales.canales5(20).firstWhere(
          (c) => acercada.contiene(c.inicioMHz, c.finMHz));
      await tocar(tester, caja.topLeft + Offset(e.x(canal.centroMHz.toDouble()), e.yBase - 20));
      expect(find.textContaining('Canal ${canal.numero} · centro ${canal.centroMHz} MHz'),
          findsOneWidget);

      // Doble toque: vuelve a la banda completa.
      await tester.tapAt(caja.center);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(caja.center);
      await tester.pumpAndSettle();
      expect(pintor(tester).ventana, completa);
    });

    testWidgets('en horizontal el espectro usa todo el ancho y no se desborda',
        (tester) async {
      celular(tester, horizontal: true);
      await tester.pumpWidget(const AppEspectro());
      expect(tester.getRect(lienzo()).width, greaterThan(800));
      // El espectro llena casi todo el alto; la tabla está más abajo, al deslizar.
      expect(tester.getRect(lienzo()).height, greaterThan(200));
      expect(find.byType(TablaCanales), findsOneWidget);
      expect(find.textContaining('tabla de canales está en vertical'), findsNothing);
      for (final o in Opcion24.values) {
        await tester.tap(find.text(o.etiqueta));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text('5 GHz'));
      await tester.pumpAndSettle();
      for (final w in CatalogoCanales.anchos5) {
        await tester.tap(find.text('$w MHz'));
        await tester.pumpAndSettle();
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'en horizontal: arrastre vertical desplaza, pellizco hace zoom y se llega a "+ AP"',
        (tester) async {
      celular(tester, horizontal: true);
      await tester.pumpWidget(const AppEspectro());
      final completa = VentanaFrecuencia.completa(Banda.ghz24);
      final antes = tester.getRect(lienzo());

      // Pellizco horizontal sobre el espectro: acerca, la pantalla no se mueve.
      final a = await tester.startGesture(antes.center - const Offset(20, 0), pointer: 1);
      final b = await tester.startGesture(antes.center + const Offset(20, 0), pointer: 2);
      for (var i = 0; i < 10; i++) {
        await a.moveBy(const Offset(-8, 0));
        await b.moveBy(const Offset(8, 0));
        await tester.pump();
      }
      await a.up();
      await b.up();
      await tester.pumpAndSettle();
      expect(pintor(tester).ventana.anchoMHz, lessThan(completa.anchoMHz));
      expect(tester.getRect(lienzo()).top, antes.top);

      // Arrastre vertical con un dedo sobre el espectro: desplaza la pantalla
      // y no cambia el zoom.
      final zoom = pintor(tester).ventana;
      await tester.dragFrom(antes.center, const Offset(0, -150));
      await tester.pumpAndSettle();
      expect(tester.getRect(lienzo()).top, lessThan(antes.top));
      expect(pintor(tester).ventana, zoom);

      // Con "APs", al deslizar aparece el botón para agregar y abre el editor.
      await tester.tap(find.text('APs'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.byIcon(Icons.add), 200,
          scrollable: find.ancestor(of: lienzo(), matching: find.byType(Scrollable)).first);
      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();
      expect(find.text('Nuevo punto de acceso'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
