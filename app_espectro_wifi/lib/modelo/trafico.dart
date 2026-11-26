// Tráfico SIMULADO de un emisor Wi-Fi: ráfagas de beacon y de datos en el tiempo.
//
// Es un modelo, no una medición: Android no entrega la ocupación en el tiempo
// de las redes reales, solo su frecuencia, ancho y RSSI.
//
// Beacon:
//  - Se envía cada 100 TU = 102,4 ms (1 TU = 1024 µs), en el canal primario.
//  - Duración = preámbulo + bytes·8 / tasa (los bits entre Mbps dan µs).
//      DSSS (802.11b, preámbulo largo): 144 µs de sincronía + 48 µs de cabecera
//        PLCP = 192 µs, y la tasa de gestión es 1 Mbps.
//      OFDM (802.11a/g/n): 16 µs de preámbulo + 4 µs de SIGNAL = 20 µs, a 6 Mbps.
//    Con 250 bytes: DSSS ≈ 2,19 ms; OFDM ≈ 0,35 ms. Se omite el redondeo a
//    símbolos OFDM de 4 µs (error < 4 µs).
//
// Datos:
//  - Duración entre 0,3 y 4,5 ms (el tope de un PPDU 802.11n/ac es ~5,5 ms),
//    con más ráfagas cortas que largas.
//  - Entre ráfagas hay un hueco mínimo (DIFS + backoff) más un tiempo aleatorio
//    que da la "carga" pedida (fracción del tiempo en el aire).
//  - Cada emisor decide por su cuenta: NO se simula CSMA/CA entre emisores, así
//    que si dos comparten frecuencia pueden transmitir a la vez. Eso es lo que
//    la app pinta como interferencia.
import 'dart:math' as math;

enum TipoRafaga { beacon, datos }

enum Modulacion { dsss, ofdm }

/// 100 TU de 1024 µs.
const double intervaloBeaconMs = 102.4;

/// Tamaño típico de un beacon (cabecera + SSID + elementos de información).
const int bytesBeaconTipico = 250;

/// Duración del preámbulo + cabecera física, en µs.
double preambuloUs(Modulacion m) => switch (m) {
      Modulacion.dsss => 192.0,
      Modulacion.ofdm => 20.0,
    };

/// Tasa a la que se envían los beacons: 1 Mbps en DSSS, 6 Mbps en OFDM.
double tasaBeaconMbps(Modulacion m) => switch (m) {
      Modulacion.dsss => 1.0,
      Modulacion.ofdm => 6.0,
    };

/// Duración de un beacon en ms: preámbulo + bytes·8 / tasa.
double duracionBeaconMs({
  int bytes = bytesBeaconTipico,
  required Modulacion modulacion,
  double? tasaMbps,
}) {
  final tasa = tasaMbps ?? tasaBeaconMbps(modulacion);
  return (preambuloUs(modulacion) + bytes * 8 / tasa) / 1000;
}

/// Una transmisión: de [inicioMs] a [finMs] (tiempo simulado).
class Rafaga {
  const Rafaga(this.inicioMs, this.duracionMs, this.tipo);

  final double inicioMs;
  final double duracionMs;
  final TipoRafaga tipo;

  double get finMs => inicioMs + duracionMs;
}

/// Genera, en orden, las ráfagas de un emisor. Con la misma semilla y las
/// mismas llamadas sale siempre lo mismo.
class TraficoEmisor {
  /// [inicioMs]: instante en que el emisor empieza a existir. Un AP que se
  /// agrega con la simulación en marcha arranca en el tiempo actual, sin
  /// generar ráfagas en el pasado.
  TraficoEmisor({
    required double carga,
    required int semilla,
    double desfaseBeaconMs = 0,
    double inicioMs = 0,
  })  : carga = carga.clamp(0.02, 0.95).toDouble(),
        _azar = math.Random(semilla),
        _proxBeacon = inicioMs + desfaseBeaconMs,
        _libre = inicioMs;

  /// Fracción del tiempo que el emisor transmite datos (0,02 a 0,95).
  final double carga;

  static const double datoMinMs = 0.3;
  static const double datoMaxMs = 4.5;

  /// DIFS (34 µs) más un backoff corto.
  static const double huecoMinMs = 0.05;

  /// SIFS de OFDM (16 µs): separa el beacon de lo que sigue.
  static const double sifsMs = 0.016;

  /// Los datos terminan este tiempo antes del siguiente beacon.
  static const double guardaBeaconMs = 0.05;

  /// Con la distribución usada (min + (max−min)·u²) la media es min + (max−min)/3.
  static const double datoMedioMs = datoMinMs + (datoMaxMs - datoMinMs) / 3;

  final math.Random _azar;
  double _proxBeacon;

  /// Instante desde el que el emisor tiene el aire libre.
  double _libre;
  double? _proxDato;

  double _hueco() {
    final media = math.max(0.0, datoMedioMs * (1 - carga) / carga - huecoMinMs);
    return huecoMinMs + (-math.log(1 - _azar.nextDouble()) * media);
  }

  double _duracionDato() {
    final u = _azar.nextDouble();
    return datoMinMs + (datoMaxMs - datoMinMs) * u * u;
  }

  /// Ráfagas nuevas que empiezan hasta [ahoraMs] (inclusive). La duración del
  /// beacon se calcula con la modulación vigente en ese momento.
  List<Rafaga> avanzar(
    double ahoraMs, {
    required Modulacion modulacionBeacon,
    int bytesBeacon = bytesBeaconTipico,
  }) {
    final nuevas = <Rafaga>[];
    while (true) {
      _proxDato ??= _libre + _hueco();
      final esBeacon = _proxBeacon <= _proxDato!;
      final inicio = esBeacon ? math.max(_proxBeacon, _libre) : _proxDato!;
      if (inicio > ahoraMs) break;

      if (esBeacon) {
        final d = duracionBeaconMs(bytes: bytesBeacon, modulacion: modulacionBeacon);
        nuevas.add(Rafaga(inicio, d, TipoRafaga.beacon));
        _libre = inicio + d + sifsMs;
        _proxBeacon += intervaloBeaconMs; // el TBTT nominal no se corre
        if (_proxDato! < _libre) _proxDato = _libre + _hueco();
      } else {
        var d = _duracionDato();
        final limite = _proxBeacon - guardaBeaconMs;
        if (inicio + d > limite) d = limite - inicio;
        if (d < 0.1) {
          // No cabe una ráfaga útil antes del beacon: se espera a que pase.
          _libre = math.max(_libre, _proxBeacon);
          _proxDato = null;
          continue;
        }
        nuevas.add(Rafaga(inicio, d, TipoRafaga.datos));
        _libre = inicio + d;
        _proxDato = null;
      }
    }
    return nuevas;
  }
}
