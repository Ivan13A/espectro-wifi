// Incremento 4b: análisis de solapamiento e interferencia entre pares de APs.
// Dart puro, sin Flutter.
//
// Para cada par (A, B) de la misma banda que transmite:
//  1. Geometría: sin solape, mismo primario, angosto dentro del ancho
//     (alineado a la rejilla de 20 MHz) o solape parcial desalineado.
//  2. Quién oye a quién, por separado en cada sentido (la relación puede ser
//     ASIMÉTRICA):
//     - A decodifica el preámbulo de B si B lo pone en el primario de A. Un AP
//       ancho duplica su preámbulo en cada 20 MHz, así que un AP angosto que
//       está en un secundario del ancho lo decodifica (−82 dBm).
//     - Si no lo decodifica, A solo lo detecta por energía (−62 dBm en OFDM),
//       ventana por ventana de 20 MHz. Así un AP ancho ve a un angosto que
//       está en su secundario solo si llega con ≥ −62 dBm; entre −82 y −62 el
//       angosto le cede el turno al ancho y el ancho transmite encima.
//  3. Potencia de B que cae en una ventana de A: el nivel de B repartido según
//     su forma espectral (trapecio OFDM o sinc² DSSS, las mismas del dibujo),
//     integrada sobre la ventana.
//  4. SIR de A: nivel de A contra la suma (en mW) de lo que cae en su canal de
//     los APs que transmiten a la vez que A, es decir, los que no se oyen
//     mutuamente con A. Los que se oyen mutuamente se turnan (CSMA/CA): eso es
//     contención (tiempo de aire repartido), no interferencia.
//
// SUPUESTOS (también se muestran en la app):
//  - Los niveles se calculan en el punto de observación (el celular):
//    nivel = PIRE − FSPL(f, d). Lo que oye cada AP se aproxima con lo que
//    llega al celular, porque no se conoce la distancia entre APs.
//  - En un AP escaneado el nivel es el RSSI y se toma como potencia total.
//  - Ventana del receptor rectangular, del ancho nominal. Fuera del ancho
//    nominal no se modela la máscara espectral (faldas a −20/−28/−40 dBr).
//  - Un receptor no decodifica un preámbulo corrido respecto a su primario
//    (p. ej. canal 1 contra canal 3).
//  - Un AP ancho que ve ocupado un secundario aquí se modela como si no se
//    enterara del angosto y transmitiera encima; uno real puede estrecharse
//    (ancho de banda dinámico).
import 'dart:math' as math;

import 'canales.dart';
import 'forma_espectral.dart';
import 'punto_acceso.dart';

// --- Umbrales y su fuente ---------------------------------------------------

enum EstadoFuente {
  secundaria('estándar IEEE 802.11 citado por fuentes secundarias; texto normativo no consultado'),
  documentoIeee('documento de trabajo del grupo IEEE 802.11; texto final no consultado'),
  memoria('de memoria, por verificar'),
  supuesto('supuesto del modelo'),
  heuristica('heurística');

  const EstadoFuente(this.descripcion);
  final String descripcion;
}

class Umbral {
  const Umbral({
    required this.nombre,
    required this.valorDbm,
    required this.uso,
    required this.fuente,
    required this.estado,
  });

  final String nombre;
  final double valorDbm;
  final String uso;
  final String fuente;
  final EstadoFuente estado;
}

abstract final class Umbrales {
  static const decodOfdm = Umbral(
    nombre: 'Preámbulo OFDM en el primario de 20 MHz',
    valorDbm: -82,
    uso: 'Decodifica el preámbulo de un AP OFDM que lo pone en su primario '
        '(mismo primario, o el AP es ancho y duplica el preámbulo en cada 20 MHz).',
    fuente: 'IEEE 802.11-2020 §17.3.10.6, CCA OFDM (sensibilidad mínima de 6 Mb/s)',
    estado: EstadoFuente.secundaria,
  );

  static const energiaOfdm = Umbral(
    nombre: 'Detección de energía en 20 MHz (OFDM)',
    valorDbm: -62,
    uso: 'Señal que no decodifica, en el primario o en un secundario de 20 MHz. '
        'Es el umbral con el que un AP ancho ve a uno angosto en su secundario.',
    fuente: 'IEEE 802.11-2020 §17.3.10.6 (−82 + 20 dB). Secundario: cláusulas HT y '
        'VHT de CCA (§19.3.19.5 y §21.3.18.5; números de cláusula no verificados)',
    estado: EstadoFuente.secundaria,
  );

  /// Solo se menciona en el texto; el análisis usa [energiaOfdm].
  static const secundarioAlternativo = Umbral(
    nombre: 'Secundario, alternativa (802.11ac)',
    valorDbm: -72,
    uso: 'No se usa en el cálculo. Algunas fuentes dan −72 dBm para detectar una '
        'trama de 20 MHz en el secundario; con él el AP ancho vería antes al angosto.',
    fuente: 'Artículos y blogs sobre 802.11ac; las fuentes no coinciden',
    estado: EstadoFuente.supuesto,
  );

  static const decodDsss = Umbral(
    nombre: 'Señal DSSS en el mismo canal',
    valorDbm: -80,
    uso: 'Decodifica una señal 802.11b centrada en su primario. Un AP g/n en '
        '2.4 GHz (ERP) también entiende DSSS.',
    fuente: 'Sensibilidad mínima DSSS: IEEE 802.11-2016 §15.4.6.2, según WARP Project, '
        'Rice University (warpproject.org/trac/wiki/802.11/Benchmarks/Rx_Char). '
        'Un AP ERP (802.11g) decodifica DSSS: ERP-DSSS es obligatorio a 1, 2, 5,5 y '
        '11 Mb/s (cláusula 18), según Gast, "802.11 Wireless Networks", O\'Reilly, cap. 14 '
        '(oreilly.com/library/view/80211-wireless-networks/0596100523/ch14.html) y '
        'radio-electronics.com (www.radio-electronics.com/info/wireless/wi-fi/ieee-802-11g.php). '
        'Un AP 802.11n en 2.4 GHz también: Intel, "Different Wi-Fi Protocols and Data Rates", '
        'lista para 802.11n las tasas 1, 2, 5,5 y 11 Mb/s (DSSS/CCK) junto con las OFDM '
        '(www.intel.com/content/www/us/en/support/articles/000005725.html)',
    estado: EstadoFuente.secundaria,
  );

  static const _fuenteEdDsss = 'Documento IEEE 802.11 de 1999 (90107B) y minutas de 1994. '
      'Una patente da −76/−73/−70 dBm para HR/DSSS. Se usa la PIRE como potencia de '
      'transmisión (supuesto)';

  static const energiaDsssAlta = Umbral(
    nombre: 'Detección de energía DSSS, PIRE > 20 dBm (100 mW)',
    valorDbm: -80,
    uso: 'Un AP 802.11b detecta lo que no decodifica (OFDM o DSSS corrido).',
    fuente: _fuenteEdDsss,
    estado: EstadoFuente.documentoIeee,
  );

  static const energiaDsssMedia = Umbral(
    nombre: 'Detección de energía DSSS, PIRE de 17 a 20 dBm (50–100 mW)',
    valorDbm: -76,
    uso: 'Igual que el anterior, con potencia media.',
    fuente: _fuenteEdDsss,
    estado: EstadoFuente.documentoIeee,
  );

  static const energiaDsssBaja = Umbral(
    nombre: 'Detección de energía DSSS, PIRE ≤ 17 dBm (50 mW)',
    valorDbm: -70,
    uso: 'Igual que el anterior, con potencia baja.',
    fuente: _fuenteEdDsss,
    estado: EstadoFuente.documentoIeee,
  );

  /// 50 mW en dBm (16,99).
  static final double _dbm50mW = 10 * math.log(50) / math.ln10;

  static Umbral energiaDsss(double pireDbm) => pireDbm > 20
      ? energiaDsssAlta
      : pireDbm > _dbm50mW
          ? energiaDsssMedia
          : energiaDsssBaja;

  static const todos = [
    decodOfdm,
    energiaOfdm,
    secundarioAlternativo,
    decodDsss,
    energiaDsssAlta,
    energiaDsssMedia,
    energiaDsssBaja,
  ];
}

// --- Gravedad (heurística) ---------------------------------------------------

enum Gravedad {
  leve('Leve'),
  moderada('Moderada'),
  grave('Grave');

  const Gravedad(this.nombre);
  final String nombre;
}

/// Cortes de SIR para la gravedad. HEURÍSTICA: el único dato del estándar es
/// la diferencia de 17 dB entre la sensibilidad de 6 Mb/s (−82 dBm) y la de
/// 54 Mb/s (−65 dBm) en OFDM 802.11a/g (802.11-2016 §17.3.10.2, verificado en
/// la tabla que reproduce WARP Project, Rice University); es lo que la señal tiene que subir
/// sobre el ruido o la interferencia para pasar de la tasa más baja a la más
/// alta. "Grave" por debajo de 10 dB (supuesto: solo pasan las tasas
/// robustas) y "leve" desde 10 + 17 = 27 dB (cabe la tasa más alta).
abstract final class CortesSir {
  static const graveDb = 10.0;
  static const rangoTasasDb = 17.0;
  static const leveDb = graveDb + rangoTasasDb;

  static const explicacion =
      'Heurística: 17 dB es la diferencia de sensibilidad entre 6 Mb/s (−82 dBm) y '
      '54 Mb/s (−65 dBm) en OFDM 802.11a/g (IEEE 802.11-2016 §17.3.10.2, NON_HT, según '
      'WARP Project, Rice University: warpproject.org/trac/wiki/802.11/Benchmarks/Rx_Char; '
      'fuente secundaria que reproduce la tabla del estándar). '
      'SIR < 10 dB: grave (supuesto: solo pasan las tasas robustas). '
      '10 a 27 dB: moderada. ≥ 27 dB (10 + 17): leve, cabe la tasa más alta.';
}

/// Supuestos del análisis: los muestra "Umbrales y fuentes" en la app y el
/// reporte PDF (incremento 6).
const supuestoPuntoObservacion =
    'Supuesto: los niveles se calculan en el punto de observación (el '
    'celular), nivel = PIRE − FSPL(f, d), y lo que oye cada AP se aproxima '
    'con lo que llega al celular. Solo cuentan los APs que transmiten.';

const otrosSupuestos =
    'FSPL según ITU-R P.525. Ventana del receptor rectangular del ancho nominal; '
    'la máscara espectral fuera del ancho nominal no se modela. Un receptor no '
    'decodifica un preámbulo corrido respecto a su primario. Un AP ancho que no '
    've al angosto se modela transmitiendo encima (uno real podría estrecharse). '
    'En APs escaneados el RSSI se toma como potencia total.';

Gravedad gravedadDe(double sirDb) => sirDb < CortesSir.graveDb
    ? Gravedad.grave
    : sirDb < CortesSir.leveDb
        ? Gravedad.moderada
        : Gravedad.leve;

// --- Niveles y potencia por ventana ------------------------------------------

/// Pérdida en espacio libre en dB, con f en MHz y d en metros (mínimo 1 m).
/// ITU-R P.525: 32,45 + 20·log10(f_MHz) + 20·log10(d_km), que en metros
/// queda 20·log10(f_MHz) + 20·log10(d_m) − 27,55.
double fsplDb(double fMHz, double dM) =>
    20 * _log10(fMHz) + 20 * _log10(math.max(dM, 1)) - 27.55;

double _log10(double x) => math.log(x) / math.ln10;

/// Nivel total del AP en el punto de observación (dBm). Escaneado: RSSI.
/// Simulado: PIRE − FSPL al centro de su bloque.
double nivelDbm(PuntoAcceso ap) {
  final rssi = ap.rssiDbm;
  if (ap.escaneado && rssi != null) return rssi;
  return ap.potenciaDbm - fsplDb(ap.canalOcupado.centroMHz.toDouble(), ap.distanciaM);
}

/// Tramo de frecuencias por el que escucha un receptor (filtro rectangular).
class Ventana {
  const Ventana(this.desdeMHz, this.hastaMHz, this.etiqueta);
  final double desdeMHz;
  final double hastaMHz;
  final String etiqueta;
}

/// Primario del AP: 22 MHz en DSSS, 20 MHz en OFDM.
Ventana ventanaPrimaria(PuntoAcceso ap) {
  final f = ap.frecuenciaPrimariaMHz.toDouble();
  final m = ap.paso.dsss ? 11.0 : 10.0;
  return Ventana(f - m, f + m, 'primario ${ap.canalPrimario}');
}

/// Cada canal de 20 MHz del bloque (el primario y los secundarios).
List<Ventana> ventanas20(PuntoAcceso ap) {
  if (ap.paso.dsss) return [ventanaPrimaria(ap)];
  return [
    for (final s in ap.canalOcupado.subcanales)
      () {
        final f = frecuenciaDeCanal(ap.banda, s).toDouble();
        return Ventana(f - 10, f + 10,
            s == ap.canalPrimario ? 'primario $s' : 'secundario $s');
      }(),
  ];
}

Ventana ventanaCanal(PuntoAcceso ap) {
  final c = ap.canalOcupado;
  return Ventana(c.inicioMHz, c.finMHz, 'canal completo');
}

const _pasoMHz = 0.1;

/// ∫ forma(f) df de [c] entre [desde] y [hasta], por trapecios.
double _integral(Canal c, double desde, double hasta) {
  final a = math.max(desde, c.inicioMHz), b = math.min(hasta, c.finMHz);
  if (b <= a) return 0;
  final n = math.max(1, ((b - a) / _pasoMHz).ceil());
  final h = (b - a) / n;
  var s = (amplitudRelativa(c, a) + amplitudRelativa(c, b)) / 2;
  for (var i = 1; i < n; i++) {
    s += amplitudRelativa(c, a + i * h);
  }
  return s * h;
}

/// Fracción (0..1) de la potencia del canal [c] que cae en [v].
double fraccionEnVentana(Canal c, Ventana v) {
  final total = _integral(c, c.inicioMHz, c.finMHz);
  return total <= 0 ? 0 : _integral(c, v.desdeMHz, v.hastaMHz) / total;
}

/// Potencia (dBm) del AP [emisor] que cae en [v]; −∞ si no cae nada.
double potenciaEnVentanaDbm(PuntoAcceso emisor, Ventana v) {
  final frac = fraccionEnVentana(emisor.canalOcupado, v);
  return frac <= 0 ? double.negativeInfinity : nivelDbm(emisor) + 10 * _log10(frac);
}

// --- Quién oye a quién ----------------------------------------------------------

enum ModoEscucha {
  decodifica('decodifica el preámbulo'),
  energia('detecta por energía'),
  no('no oye');

  const ModoEscucha(this.nombre);
  final String nombre;
}

/// true si [emisor] pone su preámbulo donde [oyente] lo puede decodificar:
///  - DSSS: centrado en el primario del oyente (en 2.4 GHz todos entienden
///    DSSS: 802.11b, y g/n por ser ERP).
///  - OFDM: uno de sus canales de 20 MHz coincide con el primario del oyente
///    (el preámbulo va duplicado en cada 20 MHz del bloque). Un oyente DSSS
///    no entiende OFDM.
bool puedeDecodificar(PuntoAcceso oyente, PuntoAcceso emisor) {
  final fp = oyente.frecuenciaPrimariaMHz;
  if (emisor.paso.dsss) {
    return oyente.banda == Banda.ghz24 && emisor.frecuenciaPrimariaMHz == fp;
  }
  if (oyente.paso.dsss) return false;
  return emisor.canalOcupado.subcanales
      .any((s) => frecuenciaDeCanal(emisor.banda, s) == fp);
}

class Escucha {
  const Escucha({
    required this.oyente,
    required this.emisor,
    required this.modo,
    required this.ventana,
    required this.nivelDbm,
    required this.umbral,
  });

  final PuntoAcceso oyente;
  final PuntoAcceso emisor;
  final ModoEscucha modo;

  /// Ventana del oyente que decidió y el nivel del emisor en ella.
  final Ventana ventana;
  final double nivelDbm;
  final Umbral umbral;

  bool get oye => modo != ModoEscucha.no;

  String get texto {
    final o = oyente.nombre, e = emisor.nombre;
    final n = '${textoDbm(nivelDbm)} en su ${ventana.etiqueta}';
    final u = textoDbm(umbral.valorDbm);
    return switch (modo) {
      ModoEscucha.decodifica => '$o decodifica el preámbulo de $e: $n ≥ $u.',
      ModoEscucha.energia => '$o detecta a $e por energía: $n ≥ $u.',
      ModoEscucha.no => '$o no oye a $e: $n, por debajo de $u '
          '(${umbral == Umbrales.decodOfdm || umbral == Umbrales.decodDsss ? 'preámbulo' : 'energía'}).',
    };
  }
}

Escucha escuchar(PuntoAcceso oyente, PuntoAcceso emisor) {
  Escucha r(ModoEscucha m, Ventana v, double p, Umbral u) => Escucha(
      oyente: oyente, emisor: emisor, modo: m, ventana: v, nivelDbm: p, umbral: u);

  final prim = ventanaPrimaria(oyente);
  final decodificable = puedeDecodificar(oyente, emisor);
  final uDec = emisor.paso.dsss ? Umbrales.decodDsss : Umbrales.decodOfdm;
  final pPrim = potenciaEnVentanaDbm(emisor, prim);
  if (decodificable && pPrim >= uDec.valorDbm) {
    return r(ModoEscucha.decodifica, prim, pPrim, uDec);
  }

  final uEd = oyente.paso.dsss
      ? Umbrales.energiaDsss(oyente.potenciaDbm)
      : Umbrales.energiaOfdm;
  var mejor = prim;
  var pMax = double.negativeInfinity;
  for (final v in ventanas20(oyente)) {
    final p = potenciaEnVentanaDbm(emisor, v);
    if (p > pMax) {
      pMax = p;
      mejor = v;
    }
  }
  if (pMax >= uEd.valorDbm) return r(ModoEscucha.energia, mejor, pMax, uEd);
  // No oye. Si el preámbulo estaba a su alcance, lo que manda es −82 dBm.
  return decodificable
      ? r(ModoEscucha.no, prim, pPrim, uDec)
      : r(ModoEscucha.no, mejor, pMax, uEd);
}

// --- Relación por par ---------------------------------------------------------------

enum Geometria {
  sinSolape('Sin solape'),
  mismoPrimario('Mismo canal primario'),
  anidado('Angosto dentro del ancho'),
  parcial('Solape parcial');

  const Geometria(this.nombre);
  final String nombre;
}

enum TipoRelacion {
  independientes('Independientes', 'No comparten espectro.'),
  seTurnan('Se turnan', 'Se oyen mutuamente: CSMA/CA los turna. Comparten el tiempo de '
      'aire (contención), pero no se pisan.'),
  asimetrica('Asimétrica', 'Solo uno oye al otro: el que oye le cede el turno, el otro '
      'transmite encima.'),
  simultanea('Transmiten a la vez', 'Ninguno oye al otro: transmiten a la vez y cada uno '
      'interfiere al otro.');

  const TipoRelacion(this.nombre, this.descripcion);
  final String nombre;
  final String descripcion;
}

Set<int> _frecs20(PuntoAcceso ap) => {
      for (final s in ap.canalOcupado.subcanales) frecuenciaDeCanal(ap.banda, s),
    };

Geometria geometriaDe(PuntoAcceso a, PuntoAcceso b) {
  final ca = a.canalOcupado, cb = b.canalOcupado;
  if (a.banda != b.banda || !ca.solapaCon(cb)) return Geometria.sinSolape;
  if (a.frecuenciaPrimariaMHz == b.frecuenciaPrimariaMHz) return Geometria.mismoPrimario;
  if (!a.paso.dsss && !b.paso.dsss) {
    final fa = _frecs20(a), fb = _frecs20(b);
    if (fa.containsAll(fb) || fb.containsAll(fa)) return Geometria.anidado;
  }
  return Geometria.parcial;
}

class RelacionPar {
  RelacionPar._({
    required this.a,
    required this.b,
    required this.geometria,
    required this.solapeMHz,
    required this.aOyeB,
    required this.bOyeA,
    required this.pBenADbm,
    required this.pAenBDbm,
  });

  factory RelacionPar.de(PuntoAcceso a, PuntoAcceso b) {
    final g = geometriaDe(a, b);
    if (g == Geometria.sinSolape) {
      return RelacionPar._(
          a: a, b: b, geometria: g, solapeMHz: 0,
          aOyeB: null, bOyeA: null, pBenADbm: null, pAenBDbm: null);
    }
    return RelacionPar._(
      a: a,
      b: b,
      geometria: g,
      solapeMHz: a.canalOcupado.solapamientoMHz(b.canalOcupado),
      aOyeB: escuchar(a, b),
      bOyeA: escuchar(b, a),
      pBenADbm: potenciaEnVentanaDbm(b, ventanaCanal(a)),
      pAenBDbm: potenciaEnVentanaDbm(a, ventanaCanal(b)),
    );
  }

  final PuntoAcceso a;
  final PuntoAcceso b;
  final Geometria geometria;
  final double solapeMHz;

  /// null si no se solapan.
  final Escucha? aOyeB;
  final Escucha? bOyeA;

  /// Potencia de B que cae en el canal completo de A, y al revés (dBm).
  final double? pBenADbm;
  final double? pAenBDbm;

  bool get mezclaDsssOfdm => a.paso.dsss != b.paso.dsss;

  TipoRelacion get tipo {
    final ab = aOyeB?.oye, ba = bOyeA?.oye;
    if (ab == null || ba == null) return TipoRelacion.independientes;
    if (ab && ba) return TipoRelacion.seTurnan;
    if (ab || ba) return TipoRelacion.asimetrica;
    return TipoRelacion.simultanea;
  }

  /// Hay momentos en que los dos transmiten a la vez (al menos uno no oye al otro).
  bool get transmitenALaVez =>
      tipo == TipoRelacion.asimetrica || tipo == TipoRelacion.simultanea;

  /// SIR de A con solo B como interferente (null si no se pisan).
  double? get sirADb => transmitenALaVez ? nivelDbm(a) - pBenADbm! : null;
  double? get sirBDb => transmitenALaVez ? nivelDbm(b) - pAenBDbm! : null;

  /// La peor gravedad de las dos direcciones; null si no se pisan (se turnan
  /// o son independientes).
  Gravedad? get peorGravedad {
    Gravedad? peor;
    for (final s in [sirADb, sirBDb]) {
      if (s == null) continue;
      final g = gravedadDe(s);
      if (peor == null || g.index > peor.index) peor = g;
    }
    return peor;
  }

  PuntoAcceso otro(PuntoAcceso x) => x.id == a.id ? b : a;
  bool incluye(String id) => a.id == id || b.id == id;

  /// Explicación en líneas para la UI y el reporte.
  List<String> explicacion() {
    if (tipo == TipoRelacion.independientes) {
      return ['Sus canales no se pisan: no hay solape ni interferencia.'];
    }
    final l = <String>[
      '${geometria.nombre}: comparten ${textoMhz(solapeMHz)} MHz'
          '${mezclaDsssOfdm ? ' (uno es DSSS y el otro OFDM)' : ''}.',
      aOyeB!.texto,
      bOyeA!.texto,
    ];
    if (tipo == TipoRelacion.asimetrica) {
      final oye = aOyeB!.oye ? aOyeB! : bOyeA!;
      final sordo = aOyeB!.oye ? bOyeA! : aOyeB!;
      l.add('${oye.oyente.nombre} le cede el turno a ${oye.emisor.nombre}, pero '
          '${sordo.oyente.nombre} no se entera y transmite encima.');
      if (sordo.umbral == Umbrales.energiaOfdm &&
          sordo.ventana.etiqueta.startsWith('secundario')) {
        final alt = Umbrales.secundarioAlternativo.valorDbm;
        l.add('${sordo.oyente.nombre} solo vería a ${sordo.emisor.nombre} por energía en '
            'su ${sordo.ventana.etiqueta} (≥ ${textoDbm(Umbrales.energiaOfdm.valorDbm)}). '
            'Con el umbral alternativo de ${textoDbm(alt)} '
            '${sordo.nivelDbm >= alt ? 'sí lo detectaría' : 'tampoco lo detectaría'}. '
            'Un equipo real podría estrecharse en vez de pisarlo.');
      }
      if (mezclaDsssOfdm && geometria == Geometria.mismoPrimario) {
        l.add('Es el caso que motiva la protección ERP (RTS/CTS o CTS-to-self) de 802.11g.');
      }
    }
    if (transmitenALaVez) {
      l.add('Potencia de ${b.nombre} en el canal de ${a.nombre}: ${textoDbm(pBenADbm!)} '
          '→ SIR ${textoDb(sirADb!)} (${gravedadDe(sirADb!).nombre.toLowerCase()}).');
      l.add('Potencia de ${a.nombre} en el canal de ${b.nombre}: ${textoDbm(pAenBDbm!)} '
          '→ SIR ${textoDb(sirBDb!)} (${gravedadDe(sirBDb!).nombre.toLowerCase()}).');
    }
    return l;
  }
}

// --- Resumen por AP y por banda -------------------------------------------------------

class AnalisisAp {
  const AnalisisAp({
    required this.ap,
    required this.nivelDbm,
    required this.interferentes,
    required this.contencion,
    required this.sirDb,
  });

  final PuntoAcceso ap;
  final double nivelDbm;

  /// APs que transmiten a la vez que este y le meten potencia en su canal.
  final List<PuntoAcceso> interferentes;

  /// APs con los que se turna (comparten tiempo de aire).
  final List<PuntoAcceso> contencion;

  /// null si no hay interferentes.
  final double? sirDb;

  Gravedad? get gravedad => sirDb == null ? null : gravedadDe(sirDb!);
}

class AnalisisBanda {
  const AnalisisBanda(this.pares, this.porAp);

  /// Todos los pares, también los independientes.
  final List<RelacionPar> pares;
  final Map<String, AnalisisAp> porAp;

  List<RelacionPar> get conSolape =>
      [for (final p in pares) if (p.tipo != TipoRelacion.independientes) p];
}

/// Analiza los APs que transmiten (la lista que da ModeloAps.transmitiendoEn).
/// Los pares de bandas distintas se ignoran.
AnalisisBanda analizar(List<PuntoAcceso> transmitiendo) {
  final pares = <RelacionPar>[];
  for (var i = 0; i < transmitiendo.length; i++) {
    for (var j = i + 1; j < transmitiendo.length; j++) {
      if (transmitiendo[i].banda != transmitiendo[j].banda) continue;
      pares.add(RelacionPar.de(transmitiendo[i], transmitiendo[j]));
    }
  }
  final porAp = <String, AnalisisAp>{};
  for (final ap in transmitiendo) {
    final interf = <PuntoAcceso>[], cont = <PuntoAcceso>[];
    var iMw = 0.0;
    for (final p in pares) {
      if (!p.incluye(ap.id)) continue;
      if (p.tipo == TipoRelacion.seTurnan) cont.add(p.otro(ap));
      if (p.transmitenALaVez) {
        final pDbm = p.a.id == ap.id ? p.pBenADbm! : p.pAenBDbm!;
        if (pDbm.isFinite) {
          interf.add(p.otro(ap));
          iMw += math.pow(10, pDbm / 10).toDouble();
        }
      }
    }
    final s = nivelDbm(ap);
    porAp[ap.id] = AnalisisAp(
      ap: ap,
      nivelDbm: s,
      interferentes: interf,
      contencion: cont,
      sirDb: iMw > 0 ? s - 10 * _log10(iMw) : null,
    );
  }
  return AnalisisBanda(pares, porAp);
}

// --- Formato -------------------------------------------------------------------

String _num(double v) {
  final s = v.abs().toStringAsFixed(1).replaceAll('.', ',');
  final t = s.endsWith(',0') ? s.substring(0, s.length - 2) : s;
  return v < -0.05 ? '−$t' : t;
}

String textoDbm(double v) => v.isFinite ? '${_num(v)} dBm' : '—';
String textoDb(double v) => '${_num(v)} dB';
String textoMhz(double v) => _num(v);
