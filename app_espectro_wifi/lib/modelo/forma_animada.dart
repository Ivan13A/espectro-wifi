// Formas espectrales que cambian con el tiempo (incremento 3).
//
// Una [CapaForma] es una forma de la clase de forma_espectral.dart descrita por
// sus parámetros (centro, mitad de la parte plana, mitad del ancho nominal y
// altura), de modo que se pueda interpolar:
//  - OFDM → OFDM (20 → 40 → 80 → 160 MHz): se interpolan los parámetros. El
//    trapecio crece y el centro se desliza hasta el centro del bloque nuevo.
//  - DSSS ↔ OFDM: es un cambio de estándar, no un ensanchamiento. La forma
//    vieja se desvanece y la nueva aparece (dos capas), sin estirar una en otra.
//
// Altura con potencia total constante: la normativa limita la potencia total
// (PIRE) y el equipo la reparte entre sus subportadoras. Al ensanchar el canal
// la misma potencia queda en más MHz: la densidad baja (−3 dB cada vez que el
// ancho se duplica). La altura es el área de referencia dividida entre el área
// de la forma, así que el área (potencia total) es la misma para todos los
// anchos. Referencia (altura 1): el modo más estrecho de la banda, que es el
// DSSS de 22 MHz en 2.4 GHz y HT20 en 5 GHz.
import 'dart:math' as math;

import 'canales.dart';
import 'forma_espectral.dart';

/// Suaviza un avance 0..1 (arranque y llegada lentos).
double easeInOut(double t) {
  final x = t.clamp(0.0, 1.0).toDouble();
  return x * x * (3 - 2 * x);
}

double _lerp(double a, double b, double t) => a + (b - a) * t;

class CapaForma {
  const CapaForma({
    required this.centroMHz,
    required this.mitadPlanoMHz,
    required this.mitadBordeMHz,
    required this.altura,
    required this.dsss,
  });

  /// La forma de [c], con la altura dada (1 = pico de la referencia).
  factory CapaForma.deCanal(Canal c, {double altura = 1}) {
    final dsss = esDsss(c);
    return CapaForma(
      centroMHz: c.centroMHz.toDouble(),
      mitadPlanoMHz: dsss ? 0 : TablaOfdm.paraAncho(c.anchoMHz).tramoOcupadoMHz / 2,
      mitadBordeMHz: c.anchoMHz / 2,
      altura: altura,
      dsss: dsss,
    );
  }

  final double centroMHz;

  /// Mitad de la parte plana del trapecio (0 en DSSS).
  final double mitadPlanoMHz;

  /// Mitad del ancho nominal: donde la forma llega a 0.
  final double mitadBordeMHz;
  final double altura;
  final bool dsss;

  double get inicioMHz => centroMHz - mitadBordeMHz;
  double get finMHz => centroMHz + mitadBordeMHz;

  CapaForma conAltura(double h) => CapaForma(
        centroMHz: centroMHz,
        mitadPlanoMHz: mitadPlanoMHz,
        mitadBordeMHz: mitadBordeMHz,
        altura: h,
        dsss: dsss,
      );

  /// Interpolación entre dos formas del mismo tipo (las dos DSSS o las dos OFDM).
  static CapaForma interpolar(CapaForma a, CapaForma b, double t) => CapaForma(
        centroMHz: _lerp(a.centroMHz, b.centroMHz, t),
        mitadPlanoMHz: _lerp(a.mitadPlanoMHz, b.mitadPlanoMHz, t),
        mitadBordeMHz: _lerp(a.mitadBordeMHz, b.mitadBordeMHz, t),
        altura: _lerp(a.altura, b.altura, t),
        dsss: a.dsss,
      );

  /// Puntos (MHz, potencia relativa) del contorno, ya multiplicados por [altura].
  List<(double, double)> perfil({double pasoMHz = 0.25}) {
    if (!dsss) {
      return [
        (centroMHz - mitadBordeMHz, 0),
        (centroMHz - mitadPlanoMHz, altura),
        (centroMHz + mitadPlanoMHz, altura),
        (centroMHz + mitadBordeMHz, 0),
      ];
    }
    // Lóbulo principal de una sinc² con nulos en ±mitadBorde.
    final n = (2 * mitadBordeMHz / pasoMHz).round();
    return [
      for (var i = 0; i <= n; i++)
        () {
          final d = -mitadBordeMHz + i * (2 * mitadBordeMHz / n);
          double a = 1;
          if (d != 0) {
            final x = math.pi * d / mitadBordeMHz;
            a = (math.sin(x) / x) * (math.sin(x) / x);
          }
          return (centroMHz + d, a * altura);
        }(),
    ];
  }
}

/// Capas a dibujar entre [a] y [b] con el avance [t] (0..1, ya suavizado).
List<CapaForma> mezclarCapas(CapaForma a, CapaForma b, double t) {
  if (a.dsss == b.dsss) return [CapaForma.interpolar(a, b, t)];
  return [
    if (t < 1) a.conAltura(a.altura * (1 - t)),
    if (t > 0) b.conAltura(b.altura * t),
  ];
}

/// Área bajo el contorno del canal (MHz · potencia relativa), por trapecios.
double areaPerfil(Canal c) {
  final p = perfilCanal(c);
  var area = 0.0;
  for (var i = 0; i + 1 < p.length; i++) {
    area += (p[i + 1].$1 - p[i].$1) * (p[i].$2 + p[i + 1].$2) / 2;
  }
  return area;
}

const _referencia24 = Canal(
  banda: Banda.ghz24,
  numero: 6,
  centroMHz: 2437,
  anchoMHz: 22,
  subcanales: [6],
);
const _referencia5 = Canal(
  banda: Banda.ghz5,
  numero: 36,
  centroMHz: 5180,
  anchoMHz: 20,
  subcanales: [36],
);

final _alturas = <String, double>{};

/// Altura relativa (la de la referencia de la banda = 1) que deja a [c] con la
/// misma potencia total que la referencia.
double alturaPotenciaConstante(Canal c) =>
    _alturas.putIfAbsent('${c.banda.index}/${c.anchoMHz}', () {
      final ref = c.banda == Banda.ghz24 ? _referencia24 : _referencia5;
      return areaPerfil(ref) / areaPerfil(c);
    });

/// Densidad espectral relativa en dB (10·log10 de la altura).
double densidadDb(double altura) => 10 * math.log(altura) / math.ln10;
