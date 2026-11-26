// Forma espectral de cada canal: cuánta potencia relativa (0..1, escala lineal)
// hay a cada frecuencia. La usa el pintor del espectro y, en el incremento 3,
// la animación.
//
// DSSS (802.11b): el chip rate es 11 Mchip/s, así que el espectro es una sinc²
// con nulos en f_c ± 11 MHz. Se dibuja solo el lóbulo principal (22 MHz): la
// máscara de 802.11b obliga a filtrar los lóbulos laterales (−30 dBr a ±11 MHz).
//
// OFDM (802.11a/g/n/ac): las subportadoras van separadas Δf = 312,5 kHz
// (20 MHz / FFT de 64 puntos). Se usan las subportadoras de índice −N_SR a +N_SR
// (sin la de DC y, según el modo, sin las de guarda del centro). La señal ocupa
// el tramo de la subportadora −N_SR a la +N_SR: (2·N_SR + 1)·Δf. Ese "+1" es la
// posición de DC, que va vacía pero está dentro del tramo ocupado.
//   N_ST = subportadoras usadas; N_SR = índice de la más alejada del centro.
//   Fuente: IEEE Std 802.11-2020, tablas de parámetros de modulación de la
//   cláusula 17 (OFDM, 802.11a/g), 19 (HT, 802.11n) y 21 (VHT, 802.11ac).
//
//   Modo              N_ST  N_SR  N_ST·Δf     (2·N_SR+1)·Δf  ancho nominal
//   802.11a/g  20 MHz   52    26   16,25 MHz   16,5625 MHz    20 MHz
//   HT/VHT     20 MHz   56    28   17,50 MHz   17,8125 MHz    20 MHz
//   HT/VHT     40 MHz  114    58   35,63 MHz   36,5625 MHz    40 MHz
//   VHT        80 MHz  242   122   75,63 MHz   76,5625 MHz    80 MHz
//   VHT       160 MHz  484   250  151,25 MHz  156,5625 MHz   160 MHz
//
// El trapecio tiene la parte plana igual al tramo ocupado y cae linealmente
// hasta el ancho nominal (±W/2), que es el mismo que usa Canal.solapaCon().
// La máscara espectral completa (faldas a −20/−28/−40 dBr) no se dibuja aquí.
import 'dart:math' as math;

import 'canales.dart';

/// Separación entre subportadoras OFDM en 802.11a/g/n/ac.
const double espaciadoSubportadoraMHz = 0.3125;

/// Ocupación de un modo OFDM según sus subportadoras.
class OcupacionOfdm {
  const OcupacionOfdm(
    this.estandar,
    this.anchoNominalMHz,
    this.subportadorasUsadas,
    this.indiceMaximo,
  );

  final String estandar;
  final int anchoNominalMHz;

  /// N_ST: subportadoras con datos o pilotos.
  final int subportadorasUsadas;

  /// N_SR: índice de la subportadora más alejada del centro.
  final int indiceMaximo;

  /// Ancho real ocupado (parte plana del trapecio): (2·N_SR + 1)·Δf.
  double get tramoOcupadoMHz => (2 * indiceMaximo + 1) * espaciadoSubportadoraMHz;

  /// Solo la suma de las subportadoras usadas: N_ST·Δf (sin DC ni huecos).
  double get soloUsadasMHz => subportadorasUsadas * espaciadoSubportadoraMHz;
}

abstract final class TablaOfdm {
  static const legacy20 = OcupacionOfdm('802.11a/g (20 MHz)', 20, 52, 26);
  static const ht20 = OcupacionOfdm('802.11n/ac HT20/VHT20', 20, 56, 28);
  static const ht40 = OcupacionOfdm('802.11n/ac HT40/VHT40', 40, 114, 58);
  static const vht80 = OcupacionOfdm('802.11ac VHT80', 80, 242, 122);
  static const vht160 = OcupacionOfdm('802.11ac VHT160', 160, 484, 250);

  /// Modo que se dibuja para cada ancho. En 20 MHz se toma HT20/VHT20 (56
  /// subportadoras), que es lo que usan los equipos 802.11n/ac actuales;
  /// [legacy20] queda disponible para comparar.
  static OcupacionOfdm paraAncho(int anchoMHz) => switch (anchoMHz) {
        20 => ht20,
        40 => ht40,
        80 => vht80,
        160 => vht160,
        _ => throw ArgumentError('Sin modo OFDM para $anchoMHz MHz'),
      };
}

/// true si el canal se dibuja como DSSS (802.11b, 22 MHz).
bool esDsss(Canal c) => c.anchoMHz == Modo24.dsss22.anchoMHz;

/// Potencia relativa (0..1, lineal) del canal [c] a la frecuencia [fMHz].
double amplitudRelativa(Canal c, double fMHz) {
  final d = (fMHz - c.centroMHz).abs();
  return esDsss(c) ? _dsss(d) : _ofdm(TablaOfdm.paraAncho(c.anchoMHz), d);
}

double _dsss(double d) {
  if (d >= 11) return 0;
  if (d == 0) return 1;
  final x = math.pi * d / 11;
  final s = math.sin(x) / x;
  return s * s;
}

double _ofdm(OcupacionOfdm o, double d) {
  final plano = o.tramoOcupadoMHz / 2;
  final borde = o.anchoNominalMHz / 2;
  if (d <= plano) return 1;
  if (d >= borde) return 0;
  return (borde - d) / (borde - plano);
}

/// Puntos (frecuencia MHz, potencia relativa) del contorno del canal, de
/// inicioMHz a finMHz. OFDM: las 4 esquinas exactas del trapecio. DSSS: la
/// sinc² muestreada cada [pasoMHz].
List<(double, double)> perfilCanal(Canal c, {double pasoMHz = 0.25}) {
  if (!esDsss(c)) {
    final plano = TablaOfdm.paraAncho(c.anchoMHz).tramoOcupadoMHz / 2;
    return [
      (c.inicioMHz, 0),
      (c.centroMHz - plano, 1),
      (c.centroMHz + plano, 1),
      (c.finMHz, 0),
    ];
  }
  final n = ((c.finMHz - c.inicioMHz) / pasoMHz).round();
  return [
    for (var i = 0; i <= n; i++)
      (c.inicioMHz + i * pasoMHz, amplitudRelativa(c, c.inicioMHz + i * pasoMHz)),
  ];
}
