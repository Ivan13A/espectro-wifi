// Incremento 4b: análisis de solapamiento e interferencia. (Escritas sin
// correr; ver PROGRESO.md.) Los valores esperados están calculados a mano en
// los comentarios.
import 'package:app_espectro_wifi/modelo/analisis.dart';
import 'package:app_espectro_wifi/modelo/canales.dart';
import 'package:app_espectro_wifi/modelo/punto_acceso.dart';
import 'package:flutter_test/flutter_test.dart';

PuntoAcceso ap(
  String id, {
  Banda banda = Banda.ghz5,
  int primario = 36,
  int ancho = 20,
  Estandar? estandar,
  double pire = 20,
  double d = 10,
}) =>
    PuntoAcceso(
      id: id,
      nombre: id,
      banda: banda,
      canalPrimario: primario,
      anchoMHz: ancho,
      estandar: estandar ?? (banda == Banda.ghz24 ? Estandar.g : Estandar.ac),
      potenciaDbm: pire,
      distanciaM: d,
    );

PuntoAcceso g24(String id, int canal, {double pire = 20, double d = 10}) =>
    ap(id, banda: Banda.ghz24, primario: canal, pire: pire, d: d);

void main() {
  group('Propagación y reparto espectral', () {
    test('FSPL a 2437 MHz y 10 m ≈ 60,19 dB', () {
      // 20·log10(2437) = 67,737; + 20 − 27,55 = 60,187.
      expect(fsplDb(2437, 10), closeTo(60.19, 0.01));
    });

    test('nivel = PIRE − FSPL', () {
      final a = g24('a', 6, pire: 15, d: 10);
      expect(nivelDbm(a), closeTo(15 - fsplDb(2437, 10), 1e-9));
    });

    test('un canal de 20 MHz cae entero en su propia ventana', () {
      final a = ap('a');
      expect(fraccionEnVentana(a.canalOcupado, ventanaCanal(a)), closeTo(1, 1e-9));
    });

    test('un bloque de 80 MHz reparte ~1/4 en cada canal de 20 MHz', () {
      // Trapecio VHT80: plano ±38,28 MHz, borde ±40. Bordes ≈ 0,245, centro ≈ 0,256.
      final a = ap('a', ancho: 80);
      final fr = [for (final v in ventanas20(a)) fraccionEnVentana(a.canalOcupado, v)];
      expect(fr, hasLength(4));
      expect(fr.reduce((x, y) => x + y), closeTo(1, 1e-6));
      for (final f in fr) {
        expect(f, inInclusiveRange(0.2, 0.3));
      }
      expect(fr[1], greaterThan(fr[0]));
    });
  });

  group('Umbrales', () {
    test('detección de energía DSSS por PIRE', () {
      expect(Umbrales.energiaDsss(21).valorDbm, -80);
      expect(Umbrales.energiaDsss(20).valorDbm, -76);
      expect(Umbrales.energiaDsss(17).valorDbm, -76);
      expect(Umbrales.energiaDsss(16).valorDbm, -70);
    });

    test('cortes de gravedad: 10 y 10 + 17 = 27 dB', () {
      expect(CortesSir.leveDb, 27);
      expect(gravedadDe(9.9), Gravedad.grave);
      expect(gravedadDe(10), Gravedad.moderada);
      expect(gravedadDe(26.9), Gravedad.moderada);
      expect(gravedadDe(27), Gravedad.leve);
    });
  });

  group('Clasificación de pares', () {
    test('canales 1 y 6: sin solape, independientes', () {
      final r = RelacionPar.de(g24('a', 1), g24('b', 6));
      expect(r.geometria, Geometria.sinSolape);
      expect(r.tipo, TipoRelacion.independientes);
      expect(r.sirADb, isNull);
    });

    test('co-canal 36/36: se decodifican y se turnan', () {
      final r = RelacionPar.de(ap('a'), ap('b'));
      expect(r.geometria, Geometria.mismoPrimario);
      expect(r.aOyeB!.modo, ModoEscucha.decodifica);
      expect(r.bOyeA!.modo, ModoEscucha.decodifica);
      expect(r.tipo, TipoRelacion.seTurnan);
      expect(r.transmitenALaVez, isFalse);
    });

    test('36 a 20 MHz dentro de 36 a 80 MHz (mismo primario): se turnan', () {
      final r = RelacionPar.de(ap('ancho', ancho: 80), ap('angosto'));
      expect(r.geometria, Geometria.mismoPrimario);
      expect(r.tipo, TipoRelacion.seTurnan);
    });

    test('44 a 20 MHz en el secundario de 36 a 80 MHz: asimétrica', () {
      // Ancho: 20 − FSPL(5210, 10) = −46,79 dBm; en el canal 44 ≈ 0,256 → −52,7 dBm,
      // ≥ −82: el angosto decodifica su preámbulo duplicado.
      // Angosto: 0 − FSPL(5220, 10) = −66,80 dBm en el secundario 44 del ancho,
      // < −62: el ancho no lo ve y transmite encima.
      final ancho = ap('ancho', ancho: 80);
      final angosto = ap('angosto', primario: 44, pire: 0);
      final r = RelacionPar.de(ancho, angosto);
      expect(r.geometria, Geometria.anidado);
      expect(r.aOyeB!.modo, ModoEscucha.no);
      expect(r.aOyeB!.umbral, Umbrales.energiaOfdm);
      expect(r.aOyeB!.ventana.etiqueta, 'secundario 44');
      expect(r.aOyeB!.nivelDbm, closeTo(-66.80, 0.05));
      expect(r.bOyeA!.modo, ModoEscucha.decodifica);
      expect(r.bOyeA!.nivelDbm, closeTo(-52.7, 0.2));
      expect(r.tipo, TipoRelacion.asimetrica);
      // SIR del angosto: −66,80 − (−52,7) ≈ −14,1 dB → grave.
      expect(r.sirBDb, closeTo(-14.1, 0.3));
      expect(gravedadDe(r.sirBDb!), Gravedad.grave);
      // SIR del ancho: −46,79 − (−66,80) ≈ 20 dB → moderada.
      expect(r.sirADb, closeTo(20.0, 0.1));
      // −66,8 dBm ≥ −72: con el umbral alternativo sí lo detectaría.
      expect(r.explicacion().any((l) => l.contains('sí lo detectaría')), isTrue);
    });

    test('el mismo caso con el angosto fuerte: el ancho lo detecta por energía', () {
      final r = RelacionPar.de(ap('ancho', ancho: 80), ap('angosto', primario: 44));
      expect(r.aOyeB!.modo, ModoEscucha.energia);
      expect(r.tipo, TipoRelacion.seTurnan);
    });

    test('b y g en el canal 6: el g oye al b, el b no oye al g', () {
      // b: 20 − FSPL(2437, 10) = −40,2 dBm, ≥ −80: el g (ERP) decodifica DSSS.
      // g: 0 − FSPL(2437, 100) = −80,2 dBm; el b (PIRE 20 dBm → −76) no lo detecta.
      final b = ap('b', banda: Banda.ghz24, primario: 6, ancho: 22, estandar: Estandar.b);
      final g = g24('g', 6, pire: 0, d: 100);
      final r = RelacionPar.de(b, g);
      expect(r.geometria, Geometria.mismoPrimario);
      expect(r.mezclaDsssOfdm, isTrue);
      expect(r.aOyeB!.modo, ModoEscucha.no);
      expect(r.aOyeB!.umbral, Umbrales.energiaDsssMedia);
      expect(r.bOyeA!.modo, ModoEscucha.decodifica);
      expect(r.bOyeA!.umbral, Umbrales.decodDsss);
      expect(r.tipo, TipoRelacion.asimetrica);
      expect(r.explicacion().any((l) => l.contains('ERP')), isTrue);
    });

    test('canales 1 y 3 lejanos: transmiten a la vez, SIR ≈ 3 dB', () {
      // A 300 m: ≈ −69,6 dBm cada uno. Medio canal 3 cae en el canal 1 → −72,7 dBm,
      // < −62, y el preámbulo está corrido: ninguno oye al otro.
      final r = RelacionPar.de(g24('a', 1, d: 300), g24('b', 3, d: 300));
      expect(r.geometria, Geometria.parcial);
      expect(r.tipo, TipoRelacion.simultanea);
      expect(r.sirADb, closeTo(3.0, 0.2));
      expect(gravedadDe(r.sirADb!), Gravedad.grave);
    });
  });

  group('Análisis de la banda', () {
    test('dos interferentes suman en mW: la SIR baja ~3 dB', () {
      final a = g24('a', 6, d: 300);
      final b = g24('b', 4, d: 300);
      final c = g24('c', 8, d: 300);
      final todo = analizar([a, b, c]);
      final solo = analizar([a, b]);
      final ra = todo.porAp['a']!;
      expect(ra.interferentes.map((x) => x.id), unorderedEquals(['b', 'c']));
      expect(ra.sirDb!, closeTo(solo.porAp['a']!.sirDb! - 3, 0.3));
      // 4 y 8 solo se tocan en el borde: no se solapan.
      expect(todo.porAp['b']!.interferentes.map((x) => x.id), ['a']);
    });

    test('co-canal: contención, sin interferencia simultánea', () {
      final res = analizar([ap('a'), ap('b')]);
      expect(res.porAp['a']!.contencion.map((x) => x.id), ['b']);
      expect(res.porAp['a']!.sirDb, isNull);
    });

    test('bandas distintas no forman pares', () {
      final res = analizar([g24('a', 6), ap('b')]);
      expect(res.pares, isEmpty);
    });
  });
}
