import 'package:app_espectro_wifi/modelo/canales.dart';
import 'package:app_espectro_wifi/modelo/forma_animada.dart';
import 'package:app_espectro_wifi/modelo/simulacion.dart';
import 'package:app_espectro_wifi/modelo/trafico.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Duración del beacon (preámbulo + bytes·8 / tasa)', () {
    test('DSSS a 1 Mbps, 250 bytes: ~2,2 ms', () {
      final d = duracionBeaconMs(modulacion: Modulacion.dsss);
      expect(d, closeTo((192 + 250 * 8 / 1) / 1000, 1e-9));
      expect(d, inInclusiveRange(2.0, 2.4));
    });

    test('OFDM a 6 Mbps, 250 bytes: ~0,35 ms', () {
      final d = duracionBeaconMs(modulacion: Modulacion.ofdm);
      expect(d, closeTo((20 + 250 * 8 / 6) / 1000, 1e-9));
      expect(d, inInclusiveRange(0.2, 0.4));
    });

    test('depende de los bytes y de la tasa', () {
      final corto = duracionBeaconMs(bytes: 100, modulacion: Modulacion.ofdm);
      final largo = duracionBeaconMs(bytes: 400, modulacion: Modulacion.ofdm);
      final rapido =
          duracionBeaconMs(bytes: 400, modulacion: Modulacion.ofdm, tasaMbps: 24);
      expect(largo, greaterThan(corto));
      expect(rapido, lessThan(largo));
    });
  });

  group('Tráfico de un emisor', () {
    List<Rafaga> generar(double carga, int semilla, double hasta,
        {Modulacion mod = Modulacion.ofdm}) {
      final t = TraficoEmisor(carga: carga, semilla: semilla, desfaseBeaconMs: 5);
      return t.avanzar(hasta, modulacionBeacon: mod);
    }

    test('las ráfagas están en orden y no se pisan', () {
      final r = generar(0.4, 1, 2000);
      expect(r.length, greaterThan(50));
      for (var i = 0; i + 1 < r.length; i++) {
        expect(r[i + 1].inicioMs, greaterThanOrEqualTo(r[i].finMs));
      }
    });

    test('el beacon sale cada 102,4 ms', () {
      final b = generar(0.4, 2, 1000).where((r) => r.tipo == TipoRafaga.beacon).toList();
      expect(b.length, 10); // 5, 107,4 ... 926,6
      for (var i = 0; i < b.length; i++) {
        expect(b[i].inicioMs, closeTo(5 + i * intervaloBeaconMs, 1e-9));
      }
    });

    test('la duración del beacon sigue la modulación', () {
      final dsss = generar(0.3, 3, 300, mod: Modulacion.dsss)
          .firstWhere((r) => r.tipo == TipoRafaga.beacon);
      final ofdm = generar(0.3, 3, 300).firstWhere((r) => r.tipo == TipoRafaga.beacon);
      expect(dsss.duracionMs, greaterThan(5 * ofdm.duracionMs));
    });

    test('los datos duran entre 0,1 y 4,5 ms', () {
      for (final r in generar(0.5, 4, 3000).where((r) => r.tipo == TipoRafaga.datos)) {
        expect(r.duracionMs, inInclusiveRange(0.1, TraficoEmisor.datoMaxMs));
      }
    });

    test('el tiempo en el aire se parece a la carga pedida', () {
      for (final carga in [0.1, 0.3, 0.6]) {
        final datos = generar(carga, 5, 20000)
            .where((r) => r.tipo == TipoRafaga.datos)
            .fold<double>(0, (s, r) => s + r.duracionMs);
        expect(datos / 20000, closeTo(carga, 0.06), reason: 'carga $carga');
      }
    });

    test('con la misma semilla sale lo mismo', () {
      final a = generar(0.3, 9, 500), b = generar(0.3, 9, 500);
      expect(a.length, b.length);
      for (var i = 0; i < a.length; i++) {
        expect(a[i].inicioMs, b[i].inicioMs);
        expect(a[i].duracionMs, b[i].duracionMs);
      }
    });

    test('llamar por partes da lo mismo que de una vez', () {
      final t = TraficoEmisor(carga: 0.3, semilla: 7);
      final partes = <Rafaga>[];
      for (var ms = 10.0; ms <= 400; ms += 10) {
        partes.addAll(t.avanzar(ms, modulacionBeacon: Modulacion.ofdm));
      }
      final junto = TraficoEmisor(carga: 0.3, semilla: 7)
          .avanzar(400, modulacionBeacon: Modulacion.ofdm);
      expect(partes.length, junto.length);
    });
  });

  group('Ocupación del emisor', () {
    test('5 GHz, primario 36: centro 5180 → 5190 → 5210 → 5250', () {
      final centros = [
        for (final p in PasosAncho.ghz5) ocupacionEmisor(Banda.ghz5, 36, p).centroMHz,
      ];
      expect(centros, [5180, 5190, 5210, 5250]);
    });

    test('5 GHz: el rango contiene siempre al primario', () {
      for (final p in PasosAncho.ghz5) {
        final c = ocupacionEmisor(Banda.ghz5, 36, p);
        expect(c.inicioMHz, lessThanOrEqualTo(5170));
        expect(c.finMHz, greaterThanOrEqualTo(5190));
      }
    });

    test('2.4 GHz, primario 6: 22 y 20 MHz centrados; HT40 sube a 2447', () {
      expect(ocupacionEmisor(Banda.ghz24, 6, PasosAncho.dsss22).anchoMHz, 22);
      expect(ocupacionEmisor(Banda.ghz24, 6, PasosAncho.ofdm20).centroMHz, 2437);
      final c40 = ocupacionEmisor(Banda.ghz24, 6, PasosAncho.ht40);
      expect(c40.centroMHz, 2447);
      expect([c40.inicioMHz, c40.finMHz], [2427, 2467]);
    });

    test('2.4 GHz, primario 11: HT40 baja para no salirse de la banda', () {
      final c = ocupacionEmisor(Banda.ghz24, 11, PasosAncho.ht40);
      expect(c.finMHz, lessThanOrEqualTo(2483.5));
      expect(c.centroMHz, 2452);
    });

    test('el beacon ocupa solo el primario', () {
      expect(canalBeacon(Banda.ghz5, 36, dsss: false).anchoMHz, 20);
      expect(canalBeacon(Banda.ghz24, 1, dsss: true).anchoMHz, 22);
    });
  });

  group('Potencia total constante', () {
    test('el área es la misma en 20/40/80/160 MHz (5 GHz)', () {
      final areas = [
        for (final p in PasosAncho.ghz5)
          () {
            final c = ocupacionEmisor(Banda.ghz5, 36, p);
            return areaPerfil(c) * alturaPotenciaConstante(c);
          }(),
      ];
      for (final a in areas) {
        expect(a, closeTo(areas.first, 1e-6));
      }
    });

    test('la altura cae ~3 dB cada vez que el ancho se duplica', () {
      final h = [
        for (final p in PasosAncho.ghz5)
          alturaPotenciaConstante(ocupacionEmisor(Banda.ghz5, 36, p)),
      ];
      expect(h.first, closeTo(1, 1e-9));
      for (var i = 0; i + 1 < h.length; i++) {
        expect(densidadDb(h[i + 1]) - densidadDb(h[i]), closeTo(-3, 0.2));
      }
    });

    test('2.4 GHz: el área de DSSS 22, OFDM 20 y HT40 coincide', () {
      final areas = [
        for (final p in PasosAncho.ghz24)
          () {
            final c = ocupacionEmisor(Banda.ghz24, 6, p);
            return areaPerfil(c) * alturaPotenciaConstante(c);
          }(),
      ];
      for (final a in areas) {
        expect(a, closeTo(areas.first, 1e-6));
      }
    });
  });

  group('Interpolación de formas', () {
    CapaForma capa(int ancho) => CapaForma.deCanal(
        ocupacionEmisor(Banda.ghz5, 36, PasosAncho.ghz5.firstWhere((p) => p.anchoMHz == ancho)));

    test('OFDM → OFDM: una sola capa que crece y desliza el centro', () {
      final ini = capa(20), fin = capa(40);
      expect(mezclarCapas(ini, fin, 0).single.centroMHz, 5180);
      final medio = mezclarCapas(ini, fin, 0.5).single;
      expect(medio.centroMHz, closeTo(5185, 1e-9));
      expect(medio.mitadBordeMHz, closeTo(15, 1e-9));
      final fin2 = mezclarCapas(ini, fin, 1).single;
      expect(fin2.centroMHz, 5190);
      expect(fin2.mitadBordeMHz, 20);
    });

    test('DSSS ↔ OFDM: dos capas que se cruzan, no una forma estirada', () {
      final dsss = CapaForma.deCanal(ocupacionEmisor(Banda.ghz24, 6, PasosAncho.dsss22));
      final ofdm = CapaForma.deCanal(ocupacionEmisor(Banda.ghz24, 6, PasosAncho.ofdm20));
      expect(mezclarCapas(dsss, ofdm, 0.5).length, 2);
      expect(mezclarCapas(dsss, ofdm, 0).length, 1);
      expect(mezclarCapas(dsss, ofdm, 1).length, 1);
      expect(mezclarCapas(dsss, ofdm, 1).single.dsss, isFalse);
    });

    test('el perfil DSSS llega a 0 en ±11 MHz y vale 1 en el centro', () {
      final p = CapaForma.deCanal(ocupacionEmisor(Banda.ghz24, 6, PasosAncho.dsss22)).perfil();
      expect(p.first.$2, closeTo(0, 1e-9));
      expect(p.last.$2, closeTo(0, 1e-9));
      expect(p.map((e) => e.$2).reduce((a, b) => a > b ? a : b), closeTo(1, 1e-9));
    });
  });

  group('Simulación', () {
    EmisorDemo demo(String n, int semilla, double carga) => EmisorDemo(
          nombre: n,
          primario: 6,
          paso: PasosAncho.ofdm20,
          carga: carga,
          desfaseBeaconMs: 1,
          semilla: semilla,
          colorIndice: 0,
        );

    test('dos emisores en el mismo canal generan zonas de interferencia', () {
      final sim = SimulacionEspectro(
        banda: Banda.ghz24,
        demos: [demo('X', 1, 0.6), demo('Y', 2, 0.6)],
        paso: PasosAncho.ofdm20,
        msPorSegundo: 1000,
      );
      for (var i = 0; i < 20; i++) {
        sim.avanzar(0.1);
      }
      final zonas = sim.interferenciasEnVentana(900);
      expect(zonas, isNotEmpty);
      for (final z in zonas) {
        expect(z.fIniMHz, lessThan(z.fFinMHz));
        expect(z.tIniMs, lessThan(z.tFinMs));
      }
    });

    test('los emisores demo de 2.4 GHz (1/6/11, 20 MHz) no se solapan', () {
      final sim = SimulacionEspectro(
        banda: Banda.ghz24,
        demos: EmisoresDemo.ghz24,
        paso: PasosAncho.ofdm20,
        msPorSegundo: 1000,
      );
      for (var i = 0; i < 20; i++) {
        sim.avanzar(0.1);
      }
      expect(sim.interferenciasEnVentana(900), isEmpty);
    });

    test('con HT40 en el canal 6 el AP-B pisa al AP-C (canal 11)', () {
      final sim = SimulacionEspectro(
        banda: Banda.ghz24,
        demos: EmisoresDemo.ghz24,
        paso: PasosAncho.ht40,
        msPorSegundo: 1000,
      );
      for (var i = 0; i < 40; i++) {
        sim.avanzar(0.1);
      }
      expect(sim.interferenciasEnVentana(900), isNotEmpty);
    });

    test('irA arranca la transición y termina en el ancho pedido', () {
      final sim = SimulacionEspectro(
        banda: Banda.ghz5,
        demos: EmisoresDemo.ghz5,
        paso: PasosAncho.a20,
      );
      sim.irA(PasosAncho.a80);
      final animado = sim.emisores.firstWhere((e) => e.demo.animado);
      expect(animado.progreso, 0);
      for (var i = 0; i < 20; i++) {
        sim.avanzar(0.1);
      }
      expect(animado.progreso, 1);
      expect(animado.capas(true).single.centroMHz, 5210);
    });

    test('en pausa el tiempo no corre pero el ancho sí cambia', () {
      final sim = SimulacionEspectro(
        banda: Banda.ghz5,
        demos: EmisoresDemo.ghz5,
        paso: PasosAncho.a20,
      );
      sim.irA(PasosAncho.a40);
      sim.avanzar(0.5, correr: false);
      expect(sim.tiempoMs, 0);
      expect(sim.emisores.firstWhere((e) => e.demo.animado).progreso, greaterThan(0));
    });

    test('la lentitud sale de ms simulados por segundo de pantalla', () {
      final sim = SimulacionEspectro(
        banda: Banda.ghz5,
        demos: EmisoresDemo.ghz5,
        paso: PasosAncho.a20,
        msPorSegundo: 20 / 6,
      );
      expect(sim.lentitud, closeTo(300, 1e-6));
    });
  });

  group('Textos', () {
    final demoB = EmisoresDemo.ghz24.firstWhere((d) => d.animado);

    test('DSSS → OFDM se describe como cambio de estándar, no como ensanchamiento', () {
      final t = describirTransicion(
        banda: Banda.ghz24,
        emisor: demoB,
        de: PasosAncho.dsss22,
        a: PasosAncho.ofdm20,
        potenciaConstante: true,
      );
      expect(t, contains('Cambio de estándar'));
      expect(t, contains('no ensanchamiento'));
      expect(t, isNot(contains('se ensancha')));
    });

    test('20 → 40 MHz en 2.4 GHz menciona el corrimiento del centro', () {
      final t = describirTransicion(
        banda: Banda.ghz24,
        emisor: demoB,
        de: PasosAncho.ofdm20,
        a: PasosAncho.ht40,
        potenciaConstante: true,
      );
      expect(t, contains('se ensancha'));
      expect(t, contains('2437 a 2447'));
      expect(t, contains('baja'));
    });

    test('sin potencia constante avisa que no se ve la densidad', () {
      final t = describirTransicion(
        banda: Banda.ghz5,
        emisor: EmisoresDemo.ghz5.first,
        de: PasosAncho.a20,
        a: PasosAncho.a40,
        potenciaConstante: false,
      );
      expect(t, contains('apagado'));
    });
  });
}
