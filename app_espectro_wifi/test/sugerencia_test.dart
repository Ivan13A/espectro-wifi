// "Sugerir canal": orden con analizar() y redes reales apagadas por el usuario.
import 'package:app_espectro_wifi/modelo/analisis.dart';
import 'package:app_espectro_wifi/modelo/canales.dart';
import 'package:app_espectro_wifi/modelo/lista_aps.dart';
import 'package:app_espectro_wifi/modelo/punto_acceso.dart';
import 'package:app_espectro_wifi/modelo/sugerencia.dart';
import 'package:app_espectro_wifi/reporte/datos_reporte.dart';
import 'package:flutter_test/flutter_test.dart';

PuntoAcceso ap(
  String id, {
  Banda banda = Banda.ghz5,
  int primario = 36,
  int ancho = 20,
  Estandar? estandar,
}) =>
    PuntoAcceso(
      id: id,
      nombre: id,
      banda: banda,
      canalPrimario: primario,
      anchoMHz: ancho,
      estandar: estandar ?? (banda == Banda.ghz24 ? Estandar.g : Estandar.ac),
    );

PuntoAcceso g24(String id, int canal) => ap(id, banda: Banda.ghz24, primario: canal);

PuntoAcceso real(String id, {int primario = 6, double rssi = -55}) => PuntoAcceso(
      id: id,
      nombre: id,
      banda: Banda.ghz24,
      canalPrimario: primario,
      anchoMHz: 20,
      estandar: Estandar.n,
      origen: OrigenAp.escaneado,
      rssiDbm: rssi,
    );

void main() {
  group('sugerirCanal', () {
    test('(a) 2.4 GHz con vecinos en 6 y 11 y el objetivo en el 3 sugiere el 1', () {
      final s = sugerirCanal(g24('obj', 3), [g24('v6', 6), g24('v11', 11)]);
      final mejor = s.mejores.first;
      expect(mejor.primario, 1);
      expect(mejor.anchoMHz, 20);
      expect(mejor.gravedad, isNull);
      expect(mejor.contencion, isEmpty);
      expect(s.actualEsMejor, isFalse);
      // Solo 1, 6 y 11 a 20 MHz.
      for (final o in s.mejores) {
        expect(canales24Sugeridos, contains(o.primario));
        expect(o.anchoMHz, 20);
      }
      expect(mejor.razon, startsWith('Canal 1 · 20 MHz: sin interferencia simultánea'));
    });

    test('(b) 5 GHz con vecinos de 80 MHz en 36–48 y 149–161 sugiere un bloque libre', () {
      final vecinos = [ap('v1', primario: 36, ancho: 80), ap('v2', primario: 149, ancho: 80)];
      final s = sugerirCanal(ap('obj', primario: 44, ancho: 80), vecinos);
      final mejor = s.mejores.first;
      for (final v in vecinos) {
        expect(mejor.ap.canalOcupado.solapaCon(v.canalOcupado), isFalse,
            reason: '${mejor.etiqueta} pisa a ${v.nombre}');
      }
      expect(mejor.gravedad, isNull);
      expect(mejor.contencion, isEmpty);
      // A igualdad, gana el ancho mayor: 160 MHz en 100–128.
      expect(mejor.anchoMHz, 160);
    });

    test('(c) la configuración actual siempre aparece en la salida', () {
      // Peor caso: actual en un canal desactivado.
      final s1 = sugerirCanal(g24('obj', 3), [g24('v6', 6)], desactivados: {3});
      expect(s1.opciones.first.esActual, isTrue);
      expect(s1.actual.bloqueados, [3]);
      expect(s1.actualEsMejor, isFalse);
      // Mejor caso: ya está bien, y aun así hay alternativas.
      final s2 = sugerirCanal(g24('obj', 1), [g24('v6', 6), g24('v11', 11)]);
      expect(s2.opciones.first.esActual, isTrue);
      expect(s2.actualEsMejor, isTrue);
      expect(s2.mejores.map((o) => o.primario), unorderedEquals([6, 11]));
      expect(s2.mejores.every((o) => !o.esActual), isTrue);
    });

    test('comparación sin cambios dice "igual que la actual"', () {
      final s = sugerirCanal(g24('obj', 1), const []);
      // 6 y 11 sin vecinos: sin interferencia y sin contención, como la actual.
      expect(s.mejores.first.comparacion, startsWith('Igual que la actual'));
      expect(s.mejores.first.comparacion, isNot(contains('→')));
    });

    test('en empate total prefiere OFDM sobre 802.11b y lo explica', () {
      final b = ap('obj', banda: Banda.ghz24, primario: 1, ancho: 22, estandar: Estandar.b);
      final s = sugerirCanal(b, const []);
      expect(s.actualEsMejor, isFalse);
      final mejor = s.mejores.first;
      expect(mejor.ap.paso.dsss, isFalse);
      expect(mejor.primario, 1);
      expect(mejor.razon, contains(notaDsss));
      // Con un AP OFDM como actual no aparece la nota.
      final s2 = sugerirCanal(g24('obj', 1), const []);
      expect(s2.mejores.every((o) => !o.razon.contains(notaDsss)), isTrue);
    });

    test('con dos candidatos leves gana el que se turna con menos APs aunque tenga menos SIR', () {
      // Objetivo real en el 1 (−40 dBm). v8 (−80 dBm, canal 8) pisa poco al 6 y
      // menos al 11: los dos quedan leves. v11 (−50 dBm) se turna con el 11.
      final s = sugerirCanal(real('obj', primario: 1, rssi: -40), [
        real('v8', primario: 8, rssi: -80),
        real('v11', primario: 11, rssi: -50),
      ]);
      final c6 = s.mejores.singleWhere((o) => o.primario == 6);
      final c11 = s.mejores.singleWhere((o) => o.primario == 11);
      expect(c6.gravedad, Gravedad.leve);
      expect(c11.gravedad, Gravedad.leve);
      expect(c11.sirDb!, greaterThan(c6.sirDb!));
      expect(c6.empeorados.length, c11.empeorados.length);
      expect(c6.contencion, isEmpty);
      expect(c11.contencion.map((a) => a.id), ['v11']);
      expect(s.mejores.indexOf(c6), lessThan(s.mejores.indexOf(c11)));
    });

    test('un leve que se turna con 1 AP gana a uno sin interferencia que se turna con 3', () {
      // Objetivo real en el 3 (−40 dBm). En el 1: n1 (se turna) y n4, débil en
      // el 4, que pisa un poco al 1 (leve). En el 11: tres APs que se turnan.
      final s = sugerirCanal(real('obj', primario: 3, rssi: -40), [
        real('n1', primario: 1, rssi: -50),
        real('n4', primario: 4, rssi: -80),
        for (final id in ['a11', 'b11', 'c11']) real(id, primario: 11, rssi: -50),
      ]);
      final c1 = s.mejores.singleWhere((o) => o.primario == 1);
      final c11 = s.mejores.singleWhere((o) => o.primario == 11);
      expect(c1.gravedad, Gravedad.leve);
      expect(c1.contencion.map((a) => a.id), ['n1']);
      expect(c11.gravedad, isNull);
      expect(c11.contencion, hasLength(3));
      expect(c1.empeorados.length, c11.empeorados.length);
      expect(s.mejores.indexOf(c1), lessThan(s.mejores.indexOf(c11)));
      // La frase sigue diciendo la gravedad real.
      expect(c1.razon, contains('interferencia leve'));
    });

    test('si solo cambia el ancho, la comparación lo dice', () {
      final s = sugerirCanal(ap('obj', primario: 100, ancho: 80), const []);
      final mejor = s.mejores.first;
      expect(mejor.anchoMHz, 160);
      expect(mejor.comparacion,
          'Mismo resultado, con 160 MHz en vez de 80 MHz (más capacidad).');
    });

    test('no sugiere canales desactivados', () {
      final s = sugerirCanal(g24('obj', 3), [g24('v6', 6)], desactivados: {1});
      expect(s.mejores.map((o) => o.primario), isNot(contains(1)));
    });

    test('un AP real conserva su RSSI y suelta el centro de Android', () {
      final r = PuntoAcceso(
        id: 'r',
        nombre: 'r',
        banda: Banda.ghz5,
        canalPrimario: 36,
        anchoMHz: 80,
        estandar: Estandar.ac,
        origen: OrigenAp.escaneado,
        rssiDbm: -60,
        centroRealMHz: 5210,
      );
      final c = r.conCanal(149, 80);
      expect(c.centroRealMHz, isNull);
      expect(c.canalOcupado.subcanales, [149, 153, 157, 161]);
      expect(nivelDbm(c), -60);
    });
  });

  group('Redes reales apagadas por el usuario', () {
    test('siguen apagadas tras reemplazarEscaneados hasta encenderlas o Limpiar', () {
      final m = ModeloAps();
      m.reemplazarEscaneados([real('r1')]);
      m.alternarActivo('r1');
      m.reemplazarEscaneados([real('r1')]);
      expect(m.porId('r1')!.activo, isFalse);

      m.alternarActivo('r1'); // el usuario la enciende
      m.reemplazarEscaneados([real('r1')]);
      expect(m.porId('r1')!.activo, isTrue);

      m.alternarActivo('r1');
      m.limpiarEscaneados();
      m.reemplazarEscaneados([real('r1')]);
      expect(m.porId('r1')!.activo, isTrue);
    });

    test('"Probar en simulación" crea la copia, la selecciona y apaga la real', () {
      final m = ModeloAps();
      m.reemplazarEscaneados([real('r1', primario: 3, rssi: -55)]);
      final copia = m.probarEnSimulacion(m.porId('r1')!, 1, 20);
      expect(copia.escaneado, isFalse);
      expect(copia.canalPrimario, 1);
      expect(nivelDbm(copia), closeTo(-55, 0.5));
      expect(m.seleccionado(Banda.ghz24)!.id, copia.id);
      expect(m.porId('r1')!.activo, isFalse);
      m.reemplazarEscaneados([real('r1', primario: 3)]);
      expect(m.porId('r1')!.activo, isFalse);
      expect(m.transmitiendoEn(Banda.ghz24).map((a) => a.id), [copia.id]);
    });
  });

  test('DFS: la nota va solo en candidatos con canales 52–144 y no cambia el orden', () {
    final s = sugerirCanal(ap('obj', primario: 36), [ap('v', primario: 36)]);
    for (final o in s.opciones) {
      final enDfs = {o.primario, ...o.ap.canalOcupado.subcanales}.any((n) => n >= 52 && n <= 144);
      expect(o.razon.contains(notaDfs), enDfs, reason: o.etiqueta);
    }
    // El orden es el mismo con la nota: 160 MHz en 100–128 sigue ganando.
    expect(s.mejores.first.primario, 100);
    expect(s.mejores.first.anchoMHz, 160);
  });

  test('reporte: si el seleccionado no transmite, usa la real con más RSSI', () {
    final m = ModeloAps([g24('sim', 1)]);
    m.reemplazarEscaneados([real('debil', rssi: -80), real('Familia_Amaya_B', primario: 11, rssi: -50)]);
    m.seleccionar(m.porId('sim')!);
    m.fijarSoloReales(Banda.ghz24, true);
    final r = recomendacionesDe(m);
    expect(r.first, startsWith('2.4 GHz, para Familia_Amaya_B (la red real con señal más fuerte)'));
    // 5 GHz no tiene APs: se omite.
    expect(r.any((l) => l.startsWith('5 GHz')), isFalse);

    // Sin reales que transmitan, la banda se omite (y no hay sección).
    final m2 = ModeloAps([g24('sim', 1)]);
    m2.alternarActivo('sim');
    expect(recomendacionesDe(m2), isEmpty);
  });

  test('el reporte trae la sugerencia por banda y la regla de 2.4 GHz', () {
    final m = ModeloAps.conEjemplo();
    final r = recomendacionesDe(m);
    final sel = m.seleccionado(Banda.ghz24)!.nombre;
    expect(r.first, startsWith('2.4 GHz, para $sel'));
    expect(r.any((l) => l.startsWith('5 GHz, para')), isTrue);
    expect(r.last, regla24);
  });
}
