// Incremento 4a: modelo de puntos de acceso, lista y sincronización con la
// animación. (Escritas sin correr; ver PROGRESO.md.)
import 'package:app_espectro_wifi/modelo/canales.dart';
import 'package:app_espectro_wifi/modelo/lista_aps.dart';
import 'package:app_espectro_wifi/modelo/punto_acceso.dart';
import 'package:app_espectro_wifi/modelo/simulacion.dart';
import 'package:flutter_test/flutter_test.dart';

PuntoAcceso ap(
  String id, {
  Banda banda = Banda.ghz5,
  int primario = 36,
  int ancho = 20,
  Estandar estandar = Estandar.ac,
  bool activo = true,
}) =>
    PuntoAcceso(
      id: id,
      nombre: id.toUpperCase(),
      banda: banda,
      canalPrimario: primario,
      anchoMHz: ancho,
      estandar: estandar,
      activo: activo,
    );

void main() {
  group('Estándares', () {
    test('banda y anchos que admite cada uno', () {
      expect(Estandar.b.anchosEn(Banda.ghz24), [22]);
      expect(Estandar.b.permite(Banda.ghz5), isFalse);
      expect(Estandar.g.anchosEn(Banda.ghz24), [20]);
      expect(Estandar.n.anchosEn(Banda.ghz24), [20, 40]);
      expect(Estandar.n.anchosEn(Banda.ghz5), [20, 40]);
      expect(Estandar.ac.anchosEn(Banda.ghz5), [20, 40, 80, 160]);
      expect(Estandar.ac.permite(Banda.ghz24), isFalse);
    });

    test('elegibles por banda (sin "desconocido")', () {
      expect(Estandar.elegiblesEn(Banda.ghz24), [Estandar.b, Estandar.g, Estandar.n]);
      expect(Estandar.elegiblesEn(Banda.ghz5), [Estandar.n, Estandar.ac]);
    });
  });

  group('Canales primarios válidos', () {
    test('2.4 GHz: 1 a 13 con cualquier ancho', () {
      expect(primariosValidos(Banda.ghz24, 40), List.generate(13, (i) => i + 1));
    });

    test('5 GHz: el 165 no tiene bloque de 40 MHz; en 160 solo 36-64 y 100-128', () {
      expect(primariosValidos(Banda.ghz5, 20), contains(165));
      expect(primariosValidos(Banda.ghz5, 40), isNot(contains(165)));
      final de160 = primariosValidos(Banda.ghz5, 160);
      expect(de160.length, 16);
      expect(de160, isNot(contains(149)));
      expect(de160, contains(128));
    });

    test('ajustarPrimario busca el válido más cercano y evita los desactivados', () {
      expect(ajustarPrimario(Banda.ghz5, 160, 149), 128);
      expect(ajustarPrimario(Banda.ghz5, 20, 36, evitar: {36}), 40);
      expect(ajustarPrimario(Banda.ghz5, 20, 44), 44);
    });
  });

  group('Ocupación del AP', () {
    test('5 GHz, primario 36 a 80 MHz: bloque 36-48 centrado en 5210', () {
      final c = ap('a', ancho: 80).canalOcupado;
      expect(c.centroMHz, 5210);
      expect(c.inicioMHz, 5170);
      expect(c.finMHz, 5250);
      expect(c.subcanales, [36, 40, 44, 48]);
    });

    test('2.4 GHz HT40: secundario arriba (1 → 1+5) o abajo desde el 10 (11 → 7+11)', () {
      final bajo = ap('a', banda: Banda.ghz24, primario: 1, ancho: 40, estandar: Estandar.n)
          .canalOcupado;
      expect(bajo.subcanales, [1, 5]);
      expect(bajo.centroMHz, 2422);
      final alto = ap('b', banda: Banda.ghz24, primario: 11, ancho: 40, estandar: Estandar.n)
          .canalOcupado;
      expect(alto.subcanales, [7, 11]);
      expect(alto.centroMHz, 2452);
    });

    test('802.11b ocupa 22 MHz (lóbulo DSSS)', () {
      final a = ap('a', banda: Banda.ghz24, primario: 6, ancho: 22, estandar: Estandar.b);
      expect(a.paso.dsss, isTrue);
      expect(a.canalOcupado.inicioMHz, 2426);
      expect(a.canalOcupado.finMHz, 2448);
    });

    test('AP escaneado con centro real (centerFreq0): subcanales del rango', () {
      const real = PuntoAcceso(
        id: 'r',
        nombre: 'Red',
        banda: Banda.ghz5,
        canalPrimario: 44,
        anchoMHz: 80,
        estandar: Estandar.desconocido,
        origen: OrigenAp.escaneado,
        centroRealMHz: 5210,
      );
      expect(real.canalOcupado.subcanales, [36, 40, 44, 48]);
      expect(real.canalOcupado.numero, 42);
      expect(validarAp(real), isNull);
    });
  });

  group('Validación y cambio de ancho', () {
    test('rechaza combinaciones imposibles', () {
      expect(validarAp(ap('a')), isNull);
      expect(validarAp(ap('a', primario: 165, ancho: 40)), isNotNull);
      expect(validarAp(ap('a', banda: Banda.ghz24, primario: 6, estandar: Estandar.ac)),
          isNotNull);
      expect(validarAp(ap('a', ancho: 80, estandar: Estandar.n)), isNotNull);
      expect(validarAp(ap('a').copyWith(nombre: '  ')), isNotNull);
      expect(validarAp(ap('a').copyWith(potenciaDbm: 31)), isNotNull);
    });

    test('conAncho cambia el estándar si hace falta y mueve el primario', () {
      final b = ap('a', banda: Banda.ghz24, primario: 6, ancho: 22, estandar: Estandar.b);
      expect(b.conAncho(40).estandar, Estandar.n);
      expect(b.conAncho(20).estandar, Estandar.g);
      final n5 = ap('c', primario: 149, estandar: Estandar.n);
      final ancho = n5.conAncho(160);
      expect(ancho.estandar, Estandar.ac);
      expect(ancho.canalPrimario, 128);
      expect(validarAp(ancho), isNull);
    });
  });

  group('Descripción de lo que opera', () {
    test('bloque de 80 MHz: centro, rango y canales de 20 MHz con su frecuencia', () {
      final s = describirOperacion(ap('a', primario: 40, ancho: 80)).join('\n');
      expect(s, contains('canal primario 40 (5200 MHz)'));
      expect(s, contains('centrado en 5210 MHz'));
      expect(s, contains('5170–5250 MHz'));
      expect(s, contains('40 (5200 MHz), primario'));
      expect(s, contains('U-NII-1'));
    });

    test('resumen de una línea', () {
      expect(resumenAp(ap('a', banda: Banda.ghz24, primario: 6, estandar: Estandar.g)),
          'Canal 6 · 2437 MHz · 20 MHz · 2427–2447 MHz');
    });
  });

  group('Lista de APs', () {
    test('el ejemplo trae 3 APs por banda y selecciona el que se animaba', () {
      final m = ModeloAps.conEjemplo();
      expect(m.de(Banda.ghz24).length, 3);
      expect(m.de(Banda.ghz5).length, 3);
      expect(m.seleccionado(Banda.ghz24)?.canalPrimario, 6);
      expect(m.seleccionado(Banda.ghz5)?.canalPrimario, 36);
      for (final a in m.aps) {
        expect(validarAp(a), isNull, reason: a.toString());
      }
    });

    test('agregar, editar, apagar y quitar', () {
      final m = ModeloAps();
      final nuevo = m.borrador(Banda.ghz5);
      expect(validarAp(nuevo), isNull);
      m.agregar(nuevo);
      expect(m.de(Banda.ghz5).single.id, nuevo.id);
      m.editar(nuevo.copyWith(canalPrimario: 149));
      expect(m.porId(nuevo.id)?.canalPrimario, 149);
      m.alternarActivo(nuevo.id);
      expect(m.transmite(m.porId(nuevo.id)!), isFalse);
      m.quitar(nuevo.id);
      expect(m.aps, isEmpty);
    });

    test('el borrador elige un canal libre y un nombre libre', () {
      final m = ModeloAps.conEjemplo();
      final b = m.borrador(Banda.ghz24);
      expect([1, 6, 11], isNot(contains(b.canalPrimario)));
      expect(m.aps.map((a) => a.nombre), isNot(contains(b.nombre)));
    });

    test('un canal desactivado silencia al AP que lo usa, también como secundario', () {
      final m = ModeloAps([ap('a', primario: 36, ancho: 80), ap('b', primario: 149)]);
      m.alternarCanal(Banda.ghz5, 44); // secundario del bloque 36-48
      expect(m.canalesBloqueados(m.porId('a')!), [44]);
      expect(m.transmite(m.porId('a')!), isFalse);
      expect(m.transmite(m.porId('b')!), isTrue);
      expect(m.transmitiendoEn(Banda.ghz5).map((a) => a.id), ['b']);
      m.activarTodos(Banda.ghz5);
      expect(m.transmite(m.porId('a')!), isTrue);
    });

    test('reemplazarEscaneados no toca los simulados', () {
      final m = ModeloAps([ap('sim')]);
      const r = PuntoAcceso(
        id: 'r1',
        nombre: 'Red',
        banda: Banda.ghz5,
        canalPrimario: 36,
        anchoMHz: 20,
        estandar: Estandar.desconocido,
        origen: OrigenAp.escaneado,
      );
      m.reemplazarEscaneados([r]);
      m.reemplazarEscaneados([r]);
      expect(m.aps.map((a) => a.id), ['sim', 'r1']);
    });
  });

  group('Sincronización con la animación', () {
    test('agregar, editar y quitar conserva los emisores que siguen', () {
      final a = ap('a', primario: 36);
      final b = ap('b', primario: 149);
      final sim = SimulacionEspectro(
        banda: Banda.ghz5,
        demos: [emisorDeAp(a), emisorDeAp(b)],
        paso: PasosAncho.a20,
      );
      sim.avanzar(10);
      final emisorA = sim.emisores.first;

      // Ancho nuevo: mismo objeto, con transición en curso.
      sim.sincronizar([emisorDeAp(a.copyWith(anchoMHz: 80)), emisorDeAp(b)]);
      expect(identical(sim.emisores.first, emisorA), isTrue);
      expect(emisorA.progreso, 0);
      expect(emisorA.canalDestino.anchoMHz, 80);

      // Quitar b y agregar c: c arranca en el tiempo actual.
      final c = ap('c', primario: 100);
      sim.sincronizar([emisorDeAp(a.copyWith(anchoMHz: 80)), emisorDeAp(c)]);
      expect(sim.emisores.map((e) => e.demo.id), ['a', 'c']);
      final t = sim.tiempoMs;
      sim.avanzar(1);
      for (final r in sim.emisores.last.registro) {
        expect(r.rafaga.inicioMs, greaterThanOrEqualTo(t));
      }
    });

    test('la misma id da siempre el mismo tráfico', () {
      final x = emisorDeAp(ap('mismo'));
      final y = emisorDeAp(ap('mismo'));
      expect(x.semilla, y.semilla);
      expect(x.desfaseBeaconMs, y.desfaseBeaconMs);
    });
  });
}
