// Pruebas del modelo de canales. Se corren con: flutter test
import 'package:app_espectro_wifi/modelo/canales.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Frecuencias IEEE', () {
    test('2.4 GHz: canal 1 = 2412, 6 = 2437, 13 = 2472, 14 = 2484', () {
      expect(frecuenciaDeCanal(Banda.ghz24, 1), 2412);
      expect(frecuenciaDeCanal(Banda.ghz24, 6), 2437);
      expect(frecuenciaDeCanal(Banda.ghz24, 13), 2472);
      expect(frecuenciaDeCanal(Banda.ghz24, 14), 2484);
    });

    test('5 GHz: 36 = 5180, 144 = 5720, 165 = 5825', () {
      expect(frecuenciaDeCanal(Banda.ghz5, 36), 5180);
      expect(frecuenciaDeCanal(Banda.ghz5, 144), 5720);
      expect(frecuenciaDeCanal(Banda.ghz5, 165), 5825);
    });

    test('6 GHz: canal 1 = 5955, canal 2 = 5935', () {
      expect(frecuenciaDeCanal(Banda.ghz6, 1), 5955);
      expect(frecuenciaDeCanal(Banda.ghz6, 2), 5935);
    });

    test('ida y vuelta canal <-> frecuencia', () {
      for (final n in CatalogoCanales.canales5de20) {
        expect(canalDeFrecuencia(Banda.ghz5, frecuenciaDeCanal(Banda.ghz5, n)), n);
      }
      for (var n = 1; n <= 14; n++) {
        expect(canalDeFrecuencia(Banda.ghz24, frecuenciaDeCanal(Banda.ghz24, n)), n);
      }
    });
  });

  group('Catálogo de simulación', () {
    test('25 canales de 20 MHz en 5 GHz', () {
      expect(CatalogoCanales.canales5(20).length, 25);
    });

    test('bloques agrupados de 5 GHz con sus centros', () {
      List<int> nums(int w) => CatalogoCanales.canales5(w).map((c) => c.numero).toList();
      expect(nums(40), [38, 46, 54, 62, 102, 110, 118, 126, 134, 142, 151, 159]);
      expect(nums(80), [42, 58, 106, 122, 138, 155]);
      expect(nums(160), [50, 114]);
      expect(CatalogoCanales.canales5(160).first.centroMHz, 5250);
      expect(CatalogoCanales.canales5(160).last.centroMHz, 5570);
    });

    test('todo el catálogo cumple la norma colombiana', () {
      final todos = [
        ...CatalogoCanales.canales24(Modo24.dsss22),
        ...CatalogoCanales.canales24(Modo24.ofdm20),
        ...CatalogoCanales.canales24de40(),
        for (final w in CatalogoCanales.anchos5) ...CatalogoCanales.canales5(w),
      ];
      for (final c in todos) {
        final ok = NormaColombia.tramosDe(c.banda)
            .any((r) => r.contiene(c.inicioMHz, c.finMHz));
        expect(ok, isTrue, reason: '$c ocupa ${c.inicioMHz}–${c.finMHz}');
      }
    });

    test('el canal 144 cruza U-NII-2C y U-NII-3', () {
      final c144 = CatalogoCanales.canales5(20).firstWhere((c) => c.numero == 144);
      expect(c144.inicioMHz, 5710);
      expect(c144.finMHz, 5730);
    });

    test('sub-bandas de los bloques', () {
      expect(CatalogoCanales.canales5(20).first.subbanda, 'U-NII-1');
      expect(CatalogoCanales.canales5(160).first.subbanda, 'U-NII-1 + U-NII-2A');
    });
  });

  group('Solapamiento en 2.4 GHz', () {
    List<int> solapadosCon1(Modo24 modo) {
      final cs = CatalogoCanales.canales24(modo);
      return cs.skip(1).where((c) => c.solapaCon(cs.first)).map((c) => c.numero).toList();
    }

    test('DSSS 22 MHz: el 1 se pisa con 2, 3, 4 y 5', () {
      expect(solapadosCon1(Modo24.dsss22), [2, 3, 4, 5]);
    });

    test('OFDM 20 MHz: el 1 se pisa solo con 2, 3 y 4 (el 5 apenas lo toca)', () {
      expect(solapadosCon1(Modo24.ofdm20), [2, 3, 4]);
    });

    test('1, 6 y 11 no se solapan en ningún modo', () {
      for (final modo in Modo24.values) {
        final cs = CatalogoCanales.canales24(modo);
        final c1 = cs[0], c6 = cs[5], c11 = cs[10];
        expect(c1.solapaCon(c6) || c6.solapaCon(c11) || c1.solapaCon(c11), isFalse);
      }
    });

    test('MHz compartidos entre 1 y 3 con DSSS = 12', () {
      final cs = CatalogoCanales.canales24(Modo24.dsss22);
      expect(cs[0].solapamientoMHz(cs[2]), 12);
    });
  });

  group('Clasificación del escaneo real', () {
    test('canal 6 normal', () {
      final r = clasificarRed(frecuenciaMHz: 2437);
      expect(r.banda, Banda.ghz24);
      expect(r.canalPrimario, 6);
      expect(r.dentroNorma, isTrue);
    });

    test('canal 14 (Japón): se acepta pero fuera de norma', () {
      final r = clasificarRed(frecuenciaMHz: 2484);
      expect(r.canalPrimario, 14);
      expect(r.dentroNorma, isFalse);
      expect(r.observacion, contains('Fuera de la norma'));
    });

    test('80 MHz usa centerFreq0', () {
      final r = clasificarRed(frecuenciaMHz: 5180, anchoMHz: 80, centroMHz: 5210);
      expect(r.canalPrimario, 36);
      expect(r.centroMHz, 5210);
      expect(r.dentroNorma, isTrue);
    });

    test('U-NII-4 (canal 169) fuera de norma', () {
      final r = clasificarRed(frecuenciaMHz: 5845);
      expect(r.banda, Banda.ghz5);
      expect(r.canalPrimario, 169);
      expect(r.dentroNorma, isFalse);
    });

    test('canal 165 a 80 MHz (bloque ilegal) se marca', () {
      final r = clasificarRed(frecuenciaMHz: 5825, anchoMHz: 80, centroMHz: 5815);
      expect(r.dentroNorma, isFalse);
    });

    test('red de 6 GHz va en lista aparte y está dentro de norma', () {
      final r = clasificarRed(frecuenciaMHz: 5955);
      expect(r.banda, Banda.ghz6);
      expect(r.vaEnListaAparte, isTrue);
      expect(r.dentroNorma, isTrue);
    });

    test('frecuencia rara no revienta', () {
      final r = clasificarRed(frecuenciaMHz: 900);
      expect(r.banda, isNull);
      expect(r.dentroNorma, isFalse);
    });

    test('ancho 20 ignora centerFreq0 = 0', () {
      final r = clasificarRed(frecuenciaMHz: 5500, anchoMHz: 20, centroMHz: 0);
      expect(r.centroMHz, 5500);
    });
  });
}
