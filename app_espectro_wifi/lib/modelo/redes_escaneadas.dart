// Incremento 5: de las redes que entrega Android (una por BSSID) a los
// PuntoAcceso de la app. Dart puro, sin Flutter.
//
// Pasos:
//  1. Agrupar los BSSID del mismo equipo físico. Un AP que anuncia varios SSID
//     (p. ej. "Lab" e "Invitados") usa un BSSID virtual por SSID, pero es UN
//     solo radio: un solo transmisor en el canal. Se agrupan si tienen la misma
//     frecuencia primaria, el mismo ancho y el mismo centro, y su MAC solo
//     difiere en el último byte (eso incluye el caso de los últimos 4 bits).
//     Además se exige que su RSSI difiera en ≤ 10 dB: el mismo radio llega con
//     casi el mismo nivel, y así no se juntan dos equipos de la misma marca con
//     MAC seguidas que estén en puntos distintos.
//  2. Filtrar por RSSI mínimo (por defecto −85 dBm) para esconder las débiles.
//  3. Clasificar cada grupo con clasificarRed(). Las que no se pueden dibujar
//     (6 GHz, 320 MHz, fuera de la rejilla o de las bandas) van a una lista
//     aparte: nunca se descarta una red en silencio.
//  4. Pasar el estándar de Android al del dibujo. ax/be no tienen forma propia
//     en la app: en 5 GHz se dibujan como ac y en 2.4 GHz como n ("aprox.");
//     la ocupación (canal, ancho y centro) sí es la real.
import 'dart:math' as math;

import 'analisis.dart';
import 'canales.dart';
import 'punto_acceso.dart';

/// RSSI mínimo por defecto para mostrar una red (dBm).
const double rssiMinimoPorDefecto = -85;

/// Una red vista hace más de esto (ms), al momento de escanear, se oculta.
const int antiguedadMaximaMs = 60000;

/// Una red (un BSSID) tal como la entrega el WifiManager de Android.
class RedEscaneada {
  const RedEscaneada({
    required this.ssid,
    required this.bssid,
    required this.frecuenciaMHz,
    required this.rssiDbm,
    this.codigoAncho,
    this.centro0MHz,
    this.centro1MHz,
    this.codigoEstandar,
    this.edadMs,
  });

  factory RedEscaneada.desdeMapa(Map<Object?, Object?> m) {
    int? entero(String k) => (m[k] as num?)?.toInt();
    return RedEscaneada(
      ssid: (m['ssid'] as String?) ?? '',
      bssid: ((m['bssid'] as String?) ?? '').toLowerCase(),
      frecuenciaMHz: entero('frecuencia') ?? 0,
      rssiDbm: entero('rssi') ?? -127,
      codigoAncho: entero('ancho'),
      centro0MHz: entero('centro0'),
      centro1MHz: entero('centro1'),
      codigoEstandar: entero('estandar'),
      edadMs: entero('edadMs'),
    );
  }

  final String ssid;
  final String bssid;

  /// `frequency`: centro del canal primario de 20 MHz.
  final int frecuenciaMHz;

  /// `level`, en dBm.
  final int rssiDbm;

  /// `channelWidth` (código de Android, ver [anchoDeCodigo]).
  final int? codigoAncho;

  /// `centerFreq0` / `centerFreq1` (0 si no aplica).
  final int? centro0MHz;
  final int? centro1MHz;

  /// `wifiStandard` (Android 11+), null si no existe.
  final int? codigoEstandar;

  /// Hace cuánto vio Android la red (ms).
  final int? edadMs;

  bool get oculta => ssid.trim().isEmpty;
  String get ssidVisible => oculta ? '(red oculta)' : ssid;
}

/// ScanResult.CHANNEL_WIDTH_*: 0 = 20, 1 = 40, 2 = 80, 3 = 160, 4 = 80+80,
/// 5 = 320 MHz. En 80+80 devuelve 80 (el segmento de centerFreq0).
int? anchoDeCodigo(int? codigo) => switch (codigo) {
      0 => 20,
      1 => 40,
      2 => 80,
      3 => 160,
      4 => 80,
      5 => 320,
      _ => null,
    };

String textoAnchoAndroid(int? codigo) => switch (codigo) {
      4 => '80+80 MHz',
      _ => anchoDeCodigo(codigo) == null ? 'no reportado' : '${anchoDeCodigo(codigo)} MHz',
    };

/// Nombre del estándar que reporta Android (ScanResult.WIFI_STANDARD_*).
String? nombreEstandarAndroid(int? codigo, Banda banda) => switch (codigo) {
      1 => banda == Banda.ghz24 ? '802.11b/g (legacy)' : '802.11a (legacy)',
      4 => '802.11n (Wi-Fi 4)',
      5 => '802.11ac (Wi-Fi 5)',
      6 => '802.11ax (Wi-Fi 6)',
      7 => '802.11ad (60 GHz)',
      8 => '802.11be (Wi-Fi 7)',
      _ => null,
    };

/// Estándar con el que se dibuja, si es aproximado y una nota opcional.
(Estandar, bool, String?) estandarParaDibujo(int? codigo, Banda banda) {
  final es24 = banda == Banda.ghz24;
  switch (codigo) {
    case 1:
      return es24
          ? (
              Estandar.g,
              true,
              'Android dice "legacy": puede ser 802.11b (DSSS, 22 MHz) o 802.11g '
                  '(OFDM, 20 MHz); no los distingue. Se dibuja como 802.11g.',
            )
          : (Estandar.n, true, '802.11a: OFDM de 20 MHz, la misma forma que 802.11n a 20 MHz.');
    case 4:
      return (Estandar.n, false, null);
    case 5:
      return es24 ? (Estandar.n, true, null) : (Estandar.ac, false, null);
    case 6:
    case 8:
      // ac es solo de 5 GHz: en 2.4 GHz el equivalente con forma OFDM es n.
      return es24 ? (Estandar.n, true, null) : (Estandar.ac, true, null);
    default:
      return (Estandar.desconocido, false, null);
  }
}

/// Red que no se dibuja en el espectro, con el motivo.
class RedNoDibujada {
  const RedNoDibujada({required this.titulo, required this.motivo, required this.rssiDbm});
  final String titulo;
  final String motivo;
  final int rssiDbm;
}

class ResultadoConversion {
  const ResultadoConversion({
    required this.aps,
    required this.noDibujadas,
    required this.ocultasPorRssi,
    this.ocultasPorAntiguedad = 0,
    required this.totalBssid,
    required this.totalEquipos,
  });

  static const vacio = ResultadoConversion(
    aps: [],
    noDibujadas: [],
    ocultasPorRssi: 0,
    totalBssid: 0,
    totalEquipos: 0,
  );

  /// Equipos escondidos por verse hace más de [antiguedadMaximaMs] al escanear.
  final int ocultasPorAntiguedad;

  /// Todos los equipos escondidos (antiguos o débiles).
  int get ocultas => ocultasPorRssi + ocultasPorAntiguedad;

  /// APs para la lista (2.4 y 5 GHz), ya filtrados por RSSI.
  final List<PuntoAcceso> aps;
  final List<RedNoDibujada> noDibujadas;

  /// Equipos (grupos) escondidos por estar bajo el RSSI mínimo.
  final int ocultasPorRssi;

  /// BSSID que devolvió Android y equipos físicos tras agrupar (sin filtrar).
  final int totalBssid;
  final int totalEquipos;
}

// --- Agrupación --------------------------------------------------------------

/// Diferencia máxima de RSSI (dB) para considerar dos BSSID del mismo radio.
const double _toleranciaRssiGrupo = 10;

/// Los primeros 5 bytes de la MAC, o null si no tiene el formato aa:bb:cc:dd:ee:ff.
String? _prefijoMac(String bssid) {
  final partes = bssid.split(':');
  if (partes.length != 6) return null;
  return partes.take(5).join(':');
}

class _Grupo {
  _Grupo(this.principal) : redes = [principal];
  final RedEscaneada principal;
  final List<RedEscaneada> redes;

  bool acepta(RedEscaneada r) {
    final p = principal;
    final prefijo = _prefijoMac(p.bssid);
    return prefijo != null &&
        prefijo == _prefijoMac(r.bssid) &&
        r.frecuenciaMHz == p.frecuenciaMHz &&
        r.codigoAncho == p.codigoAncho &&
        (r.centro0MHz ?? 0) == (p.centro0MHz ?? 0) &&
        (r.rssiDbm - p.rssiDbm).abs() <= _toleranciaRssiGrupo;
  }
}

List<_Grupo> _agrupar(List<RedEscaneada> redes) {
  final orden = [...redes]..sort((a, b) => b.rssiDbm.compareTo(a.rssiDbm));
  final grupos = <_Grupo>[];
  for (final r in orden) {
    final g = grupos.where((g) => g.acepta(r)).firstOrNull;
    if (g == null) {
      grupos.add(_Grupo(r));
    } else {
      g.redes.add(r);
    }
  }
  return grupos;
}

// --- Centro del bloque ------------------------------------------------------------

/// Centro real del bloque de un AP escaneado y, si se corrigió, la nota.
///
/// En 160 MHz muchos drivers siguen la codificación de 802.11ac/ax: CCFS0 =
/// centro del 80 MHz primario y CCFS1 = centro del 160. Android los pasa tal
/// cual como centerFreq0/centerFreq1. Si centerFreq1 ≠ 0 y está a 40 MHz de
/// centerFreq0, el centro es centerFreq1. Si aun así el centro no es el de un
/// bloque de 160 MHz de la rejilla (5250 o 5570 MHz en 5 GHz), se usa el
/// bloque que contiene al primario y se deja la nota. En los demás anchos (y
/// en 80+80, que se dibuja como el segmento de centerFreq0) no cambia nada.
(int, String?) centroDeBloque({
  required int frecuenciaMHz,
  required int anchoMHz,
  required int centro0MHz,
  int centro1MHz = 0,
  bool ochentaMasOchenta = false,
}) {
  if (anchoMHz != 160 || ochentaMasOchenta) return (centro0MHz, null);
  var centro = centro0MHz;
  if (centro1MHz != 0 && (centro1MHz - centro0MHz).abs() == 40) centro = centro1MHz;
  if (bandaDeFrecuencia(frecuenciaMHz) != Banda.ghz5) return (centro, null);
  final bloques = CatalogoCanales.canales5(160);
  if (bloques.any((c) => c.centroMHz == centro)) return (centro, null);
  final bloque = bloques
      .where((c) => c.inicioMHz <= frecuenciaMHz && frecuenciaMHz <= c.finMHz)
      .firstOrNull;
  if (bloque == null) return (centro, null);
  return (
    bloque.centroMHz,
    'Centro de 160 MHz corregido: Android reportó centerFreq0 $centro0MHz / '
        'centerFreq1 $centro1MHz.',
  );
}

// --- Conversión ----------------------------------------------------------------

/// Convierte el escaneo en APs. [coloresOcupados]: índices de color que ya
/// usan los APs simulados de cada banda, para no repetirlos al principio.
ResultadoConversion convertirRedes(
  List<RedEscaneada> redes, {
  double rssiMinimo = rssiMinimoPorDefecto,
  Map<Banda, Set<int>> coloresOcupados = const {},
  DateTime? horaEscaneo,
  bool mostrarAntiguas = false,
}) {
  final grupos = _agrupar(redes);
  final aps = <PuntoAcceso>[];
  final noDibujadas = <RedNoDibujada>[];
  var ocultas = 0;
  var ocultasAntiguas = 0;
  final siguienteColor = <Banda, int>{};

  int color(Banda b) {
    final usados = coloresOcupados[b] ?? const <int>{};
    var i = siguienteColor[b] ?? 0;
    // Los colores salen del ángulo áureo (no se acaban): se saltan los usados.
    while (usados.contains(i)) {
      i++;
    }
    siguienteColor[b] = i + 1;
    return i;
  }

  for (final g in grupos) {
    final r = g.principal;
    // Edad del equipo = la del BSSID visto más recientemente (null si ninguno la trae).
    final edades = [for (final red in g.redes) ?red.edadMs];
    final edad = edades.isEmpty ? null : edades.reduce(math.min);
    if (!mostrarAntiguas && edad != null && edad > antiguedadMaximaMs) {
      ocultasAntiguas++;
      continue;
    }
    if (r.rssiDbm < rssiMinimo) {
      ocultas++;
      continue;
    }
    final ssids = <String>[];
    for (final red in g.redes) {
      if (!ssids.contains(red.ssidVisible)) ssids.add(red.ssidVisible);
    }
    final nombre = ssids.length == 1 ? ssids.first : '${ssids.first} (+${ssids.length - 1})';
    final ancho = anchoDeCodigo(r.codigoAncho);
    final anchoDibujo = ancho ?? 20;
    final c0 = r.centro0MHz;
    final centroValido = anchoDibujo > 20 && c0 != null && c0 > 0;
    final (centro, notaCentro) = centroValido
        ? centroDeBloque(
            frecuenciaMHz: r.frecuenciaMHz,
            anchoMHz: anchoDibujo,
            centro0MHz: c0,
            centro1MHz: r.centro1MHz ?? 0,
            ochentaMasOchenta: r.codigoAncho == 4,
          )
        : (null, null);
    final cls = clasificarRed(
      frecuenciaMHz: r.frecuenciaMHz,
      anchoMHz: anchoDibujo,
      centroMHz: centro,
    );
    final banda = cls.banda;
    final titulo = '$nombre · ${r.frecuenciaMHz} MHz · ${textoAnchoAndroid(r.codigoAncho)} '
        '· ${r.rssiDbm} dBm';

    // Lo que no se puede dibujar va a la lista aparte, con el motivo.
    String? motivo;
    if (banda == null) {
      motivo = cls.observacion;
    } else if (banda == Banda.ghz6) {
      motivo = 'Banda de 6 GHz (Res. ANE 737/2022): va en lista aparte, no se dibuja.';
    } else if (ancho == 320) {
      motivo = '320 MHz solo existe en 6 GHz; Android lo reporta en ${banda.nombre}.';
    } else if (cls.canalPrimario == null) {
      motivo = cls.observacion;
    }
    if (motivo != null) {
      noDibujadas.add(RedNoDibujada(titulo: titulo, motivo: motivo, rssiDbm: r.rssiDbm));
      continue;
    }
    final b = banda!;

    final (estandar, aprox, notaEstandar) = estandarParaDibujo(r.codigoEstandar, b);
    final notas = <String>[
      if (cls.observacion.isNotEmpty) cls.observacion,
      if (ancho == null) 'Android no reportó el ancho: se toma 20 MHz.',
      if (anchoDibujo > 20 && !centroValido)
        'Android no dio centerFreq0: el bloque se ubica como en la simulación '
            '(puede no ser el real).',
      ?notaCentro,
      if (r.codigoAncho == 4)
        '80+80 MHz: se dibuja solo el segmento de centerFreq0 ($c0 MHz); el otro '
            '(centerFreq1 = ${r.centro1MHz} MHz) no se dibuja.',
      ?notaEstandar,
      if (g.redes.length > 1)
        '${g.redes.length} BSSID del mismo equipo (misma frecuencia, ancho y centro; '
            'MAC igual salvo el último byte): un solo radio, cuenta como un AP.',
    ];

    aps.add(PuntoAcceso(
      id: 'esc-${r.bssid.isEmpty ? '${r.frecuenciaMHz}-$nombre' : r.bssid}',
      nombre: nombre,
      banda: b,
      canalPrimario: cls.canalPrimario!,
      anchoMHz: anchoDibujo,
      estandar: estandar,
      origen: OrigenAp.escaneado,
      centroRealMHz: centroValido ? cls.centroMHz : null,
      centro0Android: c0,
      centro1Android: r.centro1MHz,
      rssiDbm: r.rssiDbm.toDouble(),
      bssid: r.bssid,
      ssids: ssids,
      bssids: [for (final red in g.redes) red.bssid],
      estandarReportado: nombreEstandarAndroid(r.codigoEstandar, b),
      estandarAprox: aprox,
      notasEscaneo: notas,
      vistaEn: horaEscaneo != null && edad != null
          ? horaEscaneo.subtract(Duration(milliseconds: edad))
          : null,
      colorIndice: color(b),
    ));
  }

  aps.sort((a, b) {
    final porBanda = a.banda.index.compareTo(b.banda.index);
    return porBanda != 0 ? porBanda : (b.rssiDbm ?? -127).compareTo(a.rssiDbm ?? -127);
  });
  noDibujadas.sort((a, b) => b.rssiDbm.compareTo(a.rssiDbm));
  return ResultadoConversion(
    aps: aps,
    noDibujadas: noDibujadas,
    ocultasPorRssi: ocultas,
    ocultasPorAntiguedad: ocultasAntiguas,
    totalBssid: redes.length,
    totalEquipos: grupos.length,
  );
}

// --- Duplicar como simulado ------------------------------------------------------

/// Copia editable (simulada) de un AP escaneado. Conserva banda, canal y ancho,
/// y elige PIRE y distancia para que el nivel simulado (PIRE − FSPL) quede
/// igual al RSSI medido: primero PIRE 20 dBm y se despeja la distancia; si da
/// fuera de 1–200 m, se fija la distancia en el límite y se ajusta la PIRE
/// (0–30 dBm). Si el estándar no sirve en el editor, se cambia por uno válido.
PuntoAcceso duplicarComoSimulado(PuntoAcceso ap, {required String id, required int colorIndice}) {
  var e = ap.estandar;
  if (e == Estandar.desconocido || !e.permite(ap.banda)) {
    e = ap.banda == Banda.ghz24 ? Estandar.n : Estandar.ac;
  }
  var pire = 20.0;
  var d = 10.0;
  final rssi = ap.rssiDbm;
  if (rssi != null) {
    final f = ap.canalOcupado.centroMHz.toDouble();
    // FSPL = 20·log10(f) + 20·log10(d) − 27,55  →  despejar d.
    d = math.pow(10, (pire - rssi - fsplDb(f, 1)) / 20).toDouble();
    if (d > 200 || d < 1) {
      d = d > 200 ? 200 : 1;
      pire = (rssi + fsplDb(f, d)).clamp(0, 30).roundToDouble();
    }
    d = (d * 10).round() / 10;
  }
  final base = PuntoAcceso(
    id: id,
    nombre: '${ap.nombre} (copia)',
    banda: ap.banda,
    canalPrimario: ap.canalPrimario,
    anchoMHz: ap.anchoMHz,
    estandar: e,
    potenciaDbm: pire,
    distanciaM: d,
    carga: ap.carga,
    colorIndice: colorIndice,
  );
  return base.conAncho(ap.anchoMHz);
}
