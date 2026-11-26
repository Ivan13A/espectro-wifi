// Simulación animada del espectro (incremento 3): emisores de demostración, su
// tráfico en el tiempo y el cambio de ancho de canal. Dart puro, sin Flutter.
//
// Es un MODELO, no una medición: Android no entrega la ocupación en el tiempo
// de las redes reales. Desde el incremento 4 los emisores salen de la lista de
// APs (punto_acceso.dart → emisorDeAp) y [SimulacionEspectro.sincronizar] los
// actualiza sin reiniciar la simulación. EmisoresDemo queda como la lista de
// ejemplo inicial.
import 'dart:math' as math;

import 'canales.dart';
import 'forma_animada.dart';
import 'trafico.dart';

String _mhz(double v) => v == v.roundToDouble()
    ? v.toInt().toString()
    : v.toString().replaceAll('.', ',');

String _db(double v) => v.toStringAsFixed(1).replaceAll('.', ',');

// --- Pasos de ancho ---------------------------------------------------------

/// Un ancho (y estándar) que puede tomar el emisor animado.
class PasoAncho {
  const PasoAncho(this.anchoMHz, this.estandar, {this.dsss = false});

  /// Ancho nominal: 22 en DSSS, 20/40/80/160 en OFDM.
  final int anchoMHz;
  final String estandar;
  final bool dsss;
}

abstract final class PasosAncho {
  static const dsss22 = PasoAncho(22, '802.11b (DSSS)', dsss: true);
  static const ofdm20 = PasoAncho(20, '802.11g/n (OFDM)');
  static const ht40 = PasoAncho(40, '802.11n HT40 (OFDM)');
  static const a20 = PasoAncho(20, '802.11n/ac (OFDM)');
  static const a40 = PasoAncho(40, '802.11n/ac (OFDM)');
  static const a80 = PasoAncho(80, '802.11ac (OFDM)');
  static const a160 = PasoAncho(160, '802.11ac (OFDM)');

  /// Mismo orden que las opciones de ancho de 2.4 GHz de la pantalla.
  static const ghz24 = [dsss22, ofdm20, ht40];
  static const ghz5 = [a20, a40, a80, a160];

  static List<PasoAncho> de(Banda b) => b == Banda.ghz24 ? ghz24 : ghz5;
}

/// Canal que ocupa un emisor con canal primario [primario] y el ancho [paso].
Canal ocupacionEmisor(Banda banda, int primario, PasoAncho paso) {
  if (banda == Banda.ghz24) {
    if (paso.anchoMHz == 40) {
      // HT40 con el secundario 4 canales arriba (o abajo si no cabe).
      final sec = primario <= 9 ? primario + 4 : primario - 4;
      final centro = (primario + sec) ~/ 2;
      return Canal(
        banda: banda,
        numero: centro,
        centroMHz: frecuenciaDeCanal(banda, centro),
        anchoMHz: 40,
        subcanales: [math.min(primario, sec), math.max(primario, sec)],
      );
    }
    return Canal(
      banda: banda,
      numero: primario,
      centroMHz: frecuenciaDeCanal(banda, primario),
      anchoMHz: paso.anchoMHz,
      subcanales: [primario],
    );
  }
  if (paso.anchoMHz != 20) {
    for (final c in CatalogoCanales.canales5(paso.anchoMHz)) {
      if (c.subcanales.contains(primario)) return c;
    }
  }
  return Canal(
    banda: banda,
    numero: primario,
    centroMHz: frecuenciaDeCanal(banda, primario),
    anchoMHz: 20,
    subcanales: [primario],
  );
}

/// Canal por el que se envía el beacon: solo el primario (22 MHz en DSSS, 20 en OFDM).
Canal canalBeacon(Banda banda, int primario, {required bool dsss}) => Canal(
      banda: banda,
      numero: primario,
      centroMHz: frecuenciaDeCanal(banda, primario),
      anchoMHz: dsss ? 22 : 20,
      subcanales: [primario],
    );

// --- Emisores de demostración -------------------------------------------------

class EmisorDemo {
  const EmisorDemo({
    required this.nombre,
    required this.primario,
    required this.paso,
    required this.carga,
    required this.desfaseBeaconMs,
    required this.semilla,
    required this.colorIndice,
    this.animado = false,
    this.id = '',
  });

  /// Id del AP del que sale (vacío en los emisores sueltos de las pruebas).
  final String id;
  final String nombre;
  final int primario;

  /// Ancho fijo; en el emisor [animado] es solo el inicial.
  final PasoAncho paso;
  final double carga;

  /// Cuándo sale el primer beacon (para que no coincidan).
  final double desfaseBeaconMs;
  final int semilla;
  final int colorIndice;

  /// Si es true, sigue el ancho elegido en la pantalla.
  final bool animado;
}

abstract final class EmisoresDemo {
  static const ghz24 = [
    EmisorDemo(
        nombre: 'AP-A', primario: 1, paso: PasosAncho.dsss22, carga: 0.25,
        desfaseBeaconMs: 3, semilla: 11, colorIndice: 0),
    EmisorDemo(
        nombre: 'AP-B', primario: 6, paso: PasosAncho.ofdm20, carga: 0.35,
        desfaseBeaconMs: 8, semilla: 22, colorIndice: 2, animado: true),
    EmisorDemo(
        nombre: 'AP-C', primario: 11, paso: PasosAncho.ofdm20, carga: 0.30,
        desfaseBeaconMs: 14, semilla: 33, colorIndice: 4),
  ];

  static const ghz5 = [
    EmisorDemo(
        nombre: 'AP-A', primario: 36, paso: PasosAncho.a20, carga: 0.35,
        desfaseBeaconMs: 3, semilla: 44, colorIndice: 0, animado: true),
    EmisorDemo(
        nombre: 'AP-B', primario: 100, paso: PasosAncho.a80, carga: 0.40,
        desfaseBeaconMs: 8, semilla: 55, colorIndice: 2),
    EmisorDemo(
        nombre: 'AP-C', primario: 149, paso: PasosAncho.a40, carga: 0.30,
        desfaseBeaconMs: 14, semilla: 66, colorIndice: 4),
  ];

  static List<EmisorDemo> de(Banda b) => b == Banda.ghz24 ? ghz24 : ghz5;
}

// --- Simulación ----------------------------------------------------------------

/// Una ráfaga ya emitida y la porción de espectro que ocupó.
class RegistroRafaga {
  const RegistroRafaga(this.rafaga, this.inicioMHz, this.finMHz, this.altura);

  final Rafaga rafaga;
  final double inicioMHz;
  final double finMHz;

  /// Densidad relativa con la que se dibuja (1 si la potencia constante está apagada).
  final double altura;
}

/// Zona de espectro y tiempo donde dos emisores transmiten a la vez.
class ZonaInterferencia {
  const ZonaInterferencia(this.tIniMs, this.tFinMs, this.fIniMHz, this.fFinMHz);

  final double tIniMs;
  final double tFinMs;
  final double fIniMHz;
  final double fFinMHz;
}

class EmisorSim {
  EmisorSim(this.demo, this.banda, PasoAncho inicial, {double inicioMs = 0})
      : pasoDesde = inicial,
        pasoHasta = inicial,
        trafico = TraficoEmisor(
          carga: demo.carga,
          semilla: demo.semilla,
          desfaseBeaconMs: demo.desfaseBeaconMs,
          inicioMs: inicioMs,
        );

  /// Cuánto dura el cambio de ancho en pantalla.
  static const double transicionS = 1.2;

  /// Cuánto se tarda en apagar el brillo después de una ráfaga (en pantalla).
  static const double persistenciaS = 0.25;

  /// Historial que se conserva: más que la ventana mayor (400 ms).
  static const double historialMs = 900;

  /// Datos del emisor; cambian cuando el usuario edita el AP.
  EmisorDemo demo;
  final Banda banda;
  TraficoEmisor trafico;

  PasoAncho pasoDesde;
  PasoAncho pasoHasta;

  /// Avance lineal 0..1 entre [pasoDesde] y [pasoHasta].
  double progreso = 1;

  final registro = <RegistroRafaga>[];
  final _canales = <PasoAncho, Canal>{};

  /// Brillo 0..1 de las ráfagas de datos y de beacon (1 mientras transmite,
  /// luego decae). Solo es efecto visual; [activoDatos] y [activoBeacon] dicen
  /// si se transmite en este instante.
  double nivelDatos = 0, nivelBeacon = 0;
  bool activoDatos = false, activoBeacon = false;

  Canal canal(PasoAncho p) =>
      _canales.putIfAbsent(p, () => ocupacionEmisor(banda, demo.primario, p));

  /// Ancho vigente: el de partida en la primera mitad del cambio, luego el nuevo.
  PasoAncho get pasoActual => progreso < 0.5 ? pasoDesde : pasoHasta;

  Canal get canalDestino => canal(pasoHasta);

  Canal get canalBeaconActual =>
      canalBeacon(banda, demo.primario, dsss: pasoActual.dsss);

  void irA(PasoAncho nuevo) {
    if (identical(nuevo, pasoHasta)) return;
    if (progreso >= 0.5) pasoDesde = pasoHasta;
    pasoHasta = nuevo;
    progreso = 0;
  }

  /// Aplica los datos editados del AP sin perder su historial de ráfagas.
  ///  - Mismo canal primario, otro ancho: transición animada (como los chips).
  ///  - Otro canal primario: salta al canal nuevo (las ráfagas viejas se
  ///    quedan donde ocurrieron).
  ///  - Otra carga: el tráfico se rehace desde [ahoraMs].
  void actualizarDemo(EmisorDemo nuevo, double ahoraMs) {
    final anterior = demo;
    demo = nuevo;
    if (nuevo.primario != anterior.primario) {
      _canales.clear();
      pasoDesde = pasoHasta = nuevo.paso;
      progreso = 1;
    } else {
      irA(nuevo.paso);
    }
    if (nuevo.carga != anterior.carga || nuevo.semilla != anterior.semilla) {
      trafico = TraficoEmisor(
        carga: nuevo.carga,
        semilla: nuevo.semilla,
        desfaseBeaconMs: nuevo.desfaseBeaconMs,
        inicioMs: ahoraMs,
      );
    }
  }

  double _altura(Canal c, bool constante) =>
      constante ? alturaPotenciaConstante(c) : 1;

  /// Formas a dibujar ahora (una, o dos si hay cambio de estándar).
  List<CapaForma> capas(bool constante) {
    CapaForma de(PasoAncho p) {
      final c = canal(p);
      return CapaForma.deCanal(c, altura: _altura(c, constante));
    }

    return mezclarCapas(de(pasoDesde), de(pasoHasta), easeInOut(progreso));
  }

  CapaForma capaBeacon(bool constante) {
    final c = canalBeaconActual;
    return CapaForma.deCanal(c, altura: _altura(c, constante));
  }

  void actualizar(double dtS, double ahoraMs, bool constante, double tauMs) {
    if (progreso < 1) progreso = math.min(1.0, progreso + dtS / transicionS);

    final dsss = pasoActual.dsss;
    final cb = canalBeaconActual;
    final cd = canal(pasoActual);
    for (final r in trafico.avanzar(
      ahoraMs,
      modulacionBeacon: dsss ? Modulacion.dsss : Modulacion.ofdm,
    )) {
      if (r.tipo == TipoRafaga.beacon) {
        registro.add(RegistroRafaga(r, cb.inicioMHz, cb.finMHz, _altura(cb, constante)));
      } else {
        registro.add(RegistroRafaga(r, cd.inicioMHz, cd.finMHz, _altura(cd, constante)));
      }
    }
    registro.removeWhere((r) => r.rafaga.finMs < ahoraMs - historialMs);

    nivelDatos = nivelBeacon = 0;
    activoDatos = activoBeacon = false;
    for (final r in registro) {
      final activa = r.rafaga.inicioMs <= ahoraMs && ahoraMs < r.rafaga.finMs;
      final n = activa ? 1.0 : math.exp(-(ahoraMs - r.rafaga.finMs) / tauMs);
      if (r.rafaga.tipo == TipoRafaga.beacon) {
        nivelBeacon = math.max(nivelBeacon, n);
        activoBeacon = activoBeacon || activa;
      } else {
        nivelDatos = math.max(nivelDatos, n);
        activoDatos = activoDatos || activa;
      }
    }
  }
}

class SimulacionEspectro {
  SimulacionEspectro({
    required this.banda,
    required List<EmisorDemo> demos,
    required PasoAncho paso,
    this.potenciaConstante = true,
    this.msPorSegundo = 20 / 6,
  }) : emisores = [
          for (final d in demos) EmisorSim(d, banda, d.animado ? paso : d.paso),
        ];

  final Banda banda;
  final List<EmisorSim> emisores;

  /// Con la potencia total constante, más ancho = menos densidad (−3 dB por duplicación).
  bool potenciaConstante;

  /// Tiempo simulado: ms que pasan por cada segundo de pantalla.
  double msPorSegundo;

  /// Tiempo simulado transcurrido.
  double tiempoMs = 0;

  /// Cuántas veces más lenta que el tiempo real va la reproducción.
  double get lentitud => 1000 / msPorSegundo;

  /// Lleva al emisor animado al ancho [paso].
  void irA(PasoAncho paso) {
    for (final e in emisores) {
      if (e.demo.animado) e.irA(paso);
    }
  }

  /// Deja los emisores igual a [demos] (los APs que transmiten), emparejados
  /// por id: los nuevos arrancan en el tiempo actual, los que ya estaban
  /// conservan su historial y los que faltan se quitan.
  void sincronizar(List<EmisorDemo> demos) {
    final previos = {for (final e in emisores) e.demo.id: e};
    final nuevos = <EmisorSim>[];
    for (final d in demos) {
      final e = previos[d.id];
      if (e == null) {
        nuevos.add(EmisorSim(d, banda, d.paso, inicioMs: tiempoMs));
      } else {
        e.actualizarDemo(d, tiempoMs);
        nuevos.add(e);
      }
    }
    emisores
      ..clear()
      ..addAll(nuevos);
  }

  /// Avanza [dtS] segundos de pantalla. Si [correr] es false el tiempo de las
  /// ráfagas se detiene, pero el cambio de ancho sigue su curso.
  void avanzar(double dtS, {bool correr = true}) {
    if (correr) tiempoMs += dtS * msPorSegundo;
    final tau = EmisorSim.persistenciaS * msPorSegundo;
    for (final e in emisores) {
      e.actualizar(dtS, tiempoMs, potenciaConstante, tau);
    }
  }

  /// Zonas donde dos emisores distintos transmiten a la vez dentro de [desdeMs, hastaMs].
  List<ZonaInterferencia> cruces(double desdeMs, double hastaMs) {
    final zonas = <ZonaInterferencia>[];
    for (var i = 0; i < emisores.length; i++) {
      for (var j = i + 1; j < emisores.length; j++) {
        for (final a in emisores[i].registro) {
          if (a.rafaga.finMs <= desdeMs || a.rafaga.inicioMs >= hastaMs) continue;
          for (final b in emisores[j].registro) {
            if (b.rafaga.finMs <= desdeMs || b.rafaga.inicioMs >= hastaMs) continue;
            final t0 = math.max(desdeMs, math.max(a.rafaga.inicioMs, b.rafaga.inicioMs));
            final t1 = math.min(hastaMs, math.min(a.rafaga.finMs, b.rafaga.finMs));
            final f0 = math.max(a.inicioMHz, b.inicioMHz);
            final f1 = math.min(a.finMHz, b.finMHz);
            if (t0 < t1 && f0 < f1) zonas.add(ZonaInterferencia(t0, t1, f0, f1));
          }
        }
      }
    }
    return zonas;
  }

  List<ZonaInterferencia> interferenciasAhora() =>
      cruces(tiempoMs, tiempoMs + 1e-6);

  List<ZonaInterferencia> interferenciasEnVentana(double ventanaMs) =>
      cruces(tiempoMs - ventanaMs, tiempoMs);
}

// --- Textos ----------------------------------------------------------------------

String _canales20(int ancho) {
  final n = (ancho / 20).round();
  return '$n canal${n == 1 ? '' : 'es'} de 20 MHz';
}

String _rango(Canal c) => '${_mhz(c.inicioMHz)}–${_mhz(c.finMHz)}';

/// Descripción del estado del emisor animado sin cambio en curso.
String describirOcupacion({
  required Banda banda,
  required EmisorDemo emisor,
  required PasoAncho paso,
}) {
  final c = ocupacionEmisor(banda, emisor.primario, paso);
  final aprox = paso.dsss ? ' (lóbulo principal)' : ' = ${_canales20(c.anchoMHz)}';
  return '${emisor.nombre} (canal ${emisor.primario}) en ${paso.estandar}: ocupa '
      '${_rango(c)} MHz, ${c.anchoMHz} MHz$aprox, centrado en ${c.centroMHz} MHz. '
      'Elige otro ancho o pulsa "Reproducir anchos" para ver la transición.';
}

/// Descripción del paso de [de] a [a] del emisor animado.
String describirTransicion({
  required Banda banda,
  required EmisorDemo emisor,
  required PasoAncho de,
  required PasoAncho a,
  required bool potenciaConstante,
}) {
  final c0 = ocupacionEmisor(banda, emisor.primario, de);
  final c1 = ocupacionEmisor(banda, emisor.primario, a);
  final nombre = '${emisor.nombre} (canal ${emisor.primario})';

  if (de.dsss != a.dsss) {
    return 'Cambio de estándar, no ensanchamiento: $nombre pasa de ${de.estandar} '
        'a ${a.estandar}. Cambia la modulación (${de.dsss ? 'DSSS → OFDM' : 'OFDM → DSSS'}) '
        'y por eso la forma se sustituye (${de.dsss ? 'lóbulo sinc² → trapecio' : 'trapecio → lóbulo sinc²'}) '
        'en vez de estirarse. Ahora ocupa ${_rango(c1)} MHz (${c1.anchoMHz} MHz).';
  }

  final mas = a.anchoMHz > de.anchoMHz;
  final centro = c0.centroMHz != c1.centroMHz
      ? 'El centro pasa de ${c0.centroMHz} a ${c1.centroMHz} MHz; el canal primario '
          '(${emisor.primario}, ${frecuenciaDeCanal(banda, emisor.primario)} MHz) no cambia.'
      : 'El centro se mantiene en ${c1.centroMHz} MHz.';
  final h0 = alturaPotenciaConstante(c0), h1 = alturaPotenciaConstante(c1);
  final dens = potenciaConstante
      ? 'Misma potencia total: la densidad espectral ${h1 < h0 ? 'baja' : 'sube'} '
          '${_db((densidadDb(h1) - densidadDb(h0)).abs())} dB '
          '(más ancho = menos potencia por MHz).'
      : 'Con "Potencia total constante" apagado la altura no cambia y no se ve la '
          'variación de densidad.';
  return '$nombre ${mas ? 'se ensancha' : 'se estrecha'}: ${de.anchoMHz} → ${a.anchoMHz} MHz '
      '(${_canales20(a.anchoMHz)}), ocupa ${_rango(c1)} MHz. $centro $dens';
}
