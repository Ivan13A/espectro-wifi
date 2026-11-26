// Punto de acceso (incremento 4). Dart puro, sin Flutter.
//
// Un solo modelo para los APs SIMULADOS (los crea el usuario) y, desde el
// incremento 5, para los ESCANEADOS (salen de clasificarRed()). Todo lo demás
// (dibujo, análisis, animación) lee esta clase y no sabe de dónde vino el AP.
//
// Lo que ocupa un AP no se guarda: se calcula de su canal primario, su ancho
// y su estándar con ocupacionEmisor() (simulacion.dart). En un AP escaneado,
// si Android da el centro real del bloque (centerFreq0), se usa ese centro.
import 'canales.dart';
import 'simulacion.dart';

String _f(double v) => v == v.roundToDouble()
    ? v.toInt().toString()
    : v.toString().replaceAll('.', ',');

/// Estándar del AP. Define en qué banda opera, qué anchos admite y la
/// modulación (forma espectral).
enum Estandar {
  b('802.11b', 'DSSS'),
  g('802.11g', 'OFDM'),
  n('802.11n', 'OFDM'),
  ac('802.11ac', 'OFDM'),

  /// Solo para APs escaneados cuyo estándar no se conoce.
  desconocido('Desconocido', '');

  const Estandar(this.nombre, this.modulacion);
  final String nombre;
  final String modulacion;

  bool get dsss => this == Estandar.b;

  String get etiqueta => modulacion.isEmpty ? nombre : '$nombre ($modulacion)';

  /// Anchos (MHz) que admite en [banda]; vacío si no opera en ella.
  ///  - b: 22 MHz (lóbulo principal DSSS), solo 2.4 GHz.
  ///  - g: 20 MHz, solo 2.4 GHz.
  ///  - n: 20 y 40 MHz (HT20/HT40) en 2.4 y 5 GHz.
  ///  - ac: 20, 40, 80 y 160 MHz, solo 5 GHz.
  List<int> anchosEn(Banda banda) {
    final es24 = banda == Banda.ghz24, es5 = banda == Banda.ghz5;
    switch (this) {
      case Estandar.b:
        return es24 ? const [22] : const [];
      case Estandar.g:
        return es24 ? const [20] : const [];
      case Estandar.n:
        return (es24 || es5) ? const [20, 40] : const [];
      case Estandar.ac:
        return es5 ? const [20, 40, 80, 160] : const [];
      case Estandar.desconocido:
        if (es24) return const [20, 22, 40];
        return es5 ? const [20, 40, 80, 160] : const [];
    }
  }

  bool permite(Banda banda) => anchosEn(banda).isNotEmpty;

  /// Estándares que el usuario puede elegir en [banda] (sin "desconocido").
  static List<Estandar> elegiblesEn(Banda banda) => [
        for (final e in Estandar.values)
          if (e != Estandar.desconocido && e.permite(banda)) e,
      ];
}

enum OrigenAp {
  /// Creado por el usuario en la app.
  simulado('Simulado'),

  /// Detectado por el escaneo real (incremento 5). Solo lectura.
  escaneado('Escaneado');

  const OrigenAp(this.nombre);
  final String nombre;
}

/// Canales primarios posibles en [banda] con [anchoMHz].
///  - 2.4 GHz: 1 a 13 con cualquier ancho. En 40 MHz el secundario va 4
///    canales arriba (o abajo desde el 10), así que todos tienen bloque.
///  - 5 GHz: en 20 MHz los 25 canales; en 40/80/160 solo los que forman parte
///    de un bloque de ese ancho (p. ej. el 165 no tiene bloque de 40 MHz).
List<int> primariosValidos(Banda banda, int anchoMHz) {
  switch (banda) {
    case Banda.ghz24:
      return [for (var n = 1; n <= 13; n++) n];
    case Banda.ghz5:
      if (anchoMHz <= 20) return CatalogoCanales.canales5de20;
      if (!CatalogoCanales.anchos5.contains(anchoMHz)) return const [];
      return [for (final c in CatalogoCanales.canales5(anchoMHz)) ...c.subcanales]..sort();
    case Banda.ghz6:
      return const [];
  }
}

/// Canales de 20 MHz de [banda] que se pueden activar o desactivar.
List<int> canales20De(Banda banda) => switch (banda) {
      Banda.ghz24 => [for (var n = 1; n <= 13; n++) n],
      Banda.ghz5 => CatalogoCanales.canales5de20,
      Banda.ghz6 => const <int>[],
    };

/// El primario válido más cercano a [deseado] para [anchoMHz], saltando los
/// canales de [evitar]. Si todos están en [evitar], ignora [evitar].
int ajustarPrimario(Banda banda, int anchoMHz, int deseado, {Set<int> evitar = const {}}) {
  final validos = primariosValidos(banda, anchoMHz);
  if (validos.isEmpty) return deseado;
  final libres = [for (final n in validos) if (!evitar.contains(n)) n];
  final lista = libres.isEmpty ? validos : libres;
  if (lista.contains(deseado)) return deseado;
  var mejor = lista.first;
  for (final n in lista) {
    if ((n - deseado).abs() < (mejor - deseado).abs()) mejor = n;
  }
  return mejor;
}

class PuntoAcceso {
  const PuntoAcceso({
    required this.id,
    required this.nombre,
    required this.banda,
    required this.canalPrimario,
    required this.anchoMHz,
    required this.estandar,
    this.potenciaDbm = 20,
    this.activo = true,
    this.carga = 0.3,
    this.colorIndice = 0,
    this.distanciaM = 10,
    this.origen = OrigenAp.simulado,
    this.centroRealMHz,
    this.centro0Android,
    this.centro1Android,
    this.rssiDbm,
    this.bssid,
    this.ssids = const [],
    this.bssids = const [],
    this.estandarReportado,
    this.estandarAprox = false,
    this.notasEscaneo = const [],
    this.vistaEn,
  });

  final String id;
  final String nombre;
  final Banda banda;
  final int canalPrimario;

  /// 22 (DSSS) o 20/40/80/160 (OFDM).
  final int anchoMHz;
  final Estandar estandar;

  /// PIRE en dBm. Se usa en el análisis de interferencia (incremento 4b):
  /// nivel en el punto de observación = PIRE − pérdida en espacio libre.
  final double potenciaDbm;

  /// Encendido por el usuario. Un AP también deja de transmitir si usa un
  /// canal desactivado (eso lo decide ModeloAps).
  final bool activo;

  /// Fracción del tiempo que transmite datos en la animación (0,02 a 0,95).
  final double carga;
  final int colorIndice;

  /// Distancia al punto de observación, en metros (análisis, incremento 4b).
  final double distanciaM;

  final OrigenAp origen;

  // --- Solo APs escaneados (incremento 5) ---

  /// Centro real del bloque (`centerFreq0` de Android) si el ancho es > 20 MHz.
  final int? centroRealMHz;

  /// centerFreq0 / centerFreq1 tal como los dio Android (0 = no aplica). Solo
  /// para mostrarlos: el dibujo usa [centroRealMHz], que puede venir corregido.
  final int? centro0Android;
  final int? centro1Android;

  /// Nivel medido (RSSI) en dBm.
  final double? rssiDbm;

  /// BSSID principal (el de mayor RSSI del grupo).
  final String? bssid;

  /// SSID que anuncia el equipo. Más de uno = varios BSSID virtuales del mismo
  /// radio, agrupados en un solo AP ("varios SSID").
  final List<String> ssids;
  final List<String> bssids;

  /// Estándar tal como lo reporta Android (wifiStandard), p. ej. "802.11ax".
  final String? estandarReportado;

  /// true si [estandar] es una aproximación para dibujar (ax/be → n o ac).
  final bool estandarAprox;

  /// Observaciones de la conversión (norma, ancho no reportado, 80+80...).
  final List<String> notasEscaneo;

  /// Hora en que Android vio la red (hora del escaneo − edadMs); null si no se sabe.
  final DateTime? vistaEn;

  bool get variosSsid => ssids.length > 1;

  bool get escaneado => origen == OrigenAp.escaneado;

  /// Frecuencia central del canal primario de 20 MHz.
  int get frecuenciaPrimariaMHz => frecuenciaDeCanal(banda, canalPrimario);

  /// Ancho y estándar en el formato del motor de animación.
  PasoAncho get paso {
    if (estandar.dsss || anchoMHz == 22) return PasosAncho.dsss22;
    if (banda == Banda.ghz24) {
      return anchoMHz == 40 ? PasosAncho.ht40 : PasosAncho.ofdm20;
    }
    return switch (anchoMHz) {
      40 => PasosAncho.a40,
      80 => PasosAncho.a80,
      160 => PasosAncho.a160,
      _ => PasosAncho.a20,
    };
  }

  /// Porción del espectro que ocupa (canal primario + secundarios).
  Canal get canalOcupado {
    final centro = centroRealMHz;
    if (centro == null || anchoMHz <= 22) {
      return ocupacionEmisor(banda, canalPrimario, paso);
    }
    // AP escaneado con el centro real: los subcanales de 20 MHz salen del rango.
    final subcanales = <int>[];
    for (var f = centro - anchoMHz / 2 + 10; f < centro + anchoMHz / 2; f += 20) {
      final n = canalDeFrecuencia(banda, f.round());
      if (n != null) subcanales.add(n);
    }
    return Canal(
      banda: banda,
      numero: canalDeFrecuencia(banda, centro) ?? canalPrimario,
      centroMHz: centro,
      anchoMHz: anchoMHz,
      subcanales: subcanales.isEmpty ? [canalPrimario] : subcanales,
    );
  }

  PuntoAcceso copyWith({
    String? nombre,
    Banda? banda,
    int? canalPrimario,
    int? anchoMHz,
    Estandar? estandar,
    double? potenciaDbm,
    bool? activo,
    double? carga,
    int? colorIndice,
    double? distanciaM,
    bool sinCentroReal = false,
  }) =>
      PuntoAcceso(
        id: id,
        nombre: nombre ?? this.nombre,
        banda: banda ?? this.banda,
        canalPrimario: canalPrimario ?? this.canalPrimario,
        anchoMHz: anchoMHz ?? this.anchoMHz,
        estandar: estandar ?? this.estandar,
        potenciaDbm: potenciaDbm ?? this.potenciaDbm,
        activo: activo ?? this.activo,
        carga: carga ?? this.carga,
        colorIndice: colorIndice ?? this.colorIndice,
        distanciaM: distanciaM ?? this.distanciaM,
        origen: origen,
        centroRealMHz: sinCentroReal ? null : centroRealMHz,
        centro0Android: sinCentroReal ? null : centro0Android,
        centro1Android: sinCentroReal ? null : centro1Android,
        rssiDbm: rssiDbm,
        bssid: bssid,
        ssids: ssids,
        bssids: bssids,
        estandarReportado: estandarReportado,
        estandarAprox: estandarAprox,
        notasEscaneo: notasEscaneo,
        vistaEn: vistaEn,
      );

  /// El mismo AP con otro ancho. Si el estándar no lo admite, pasa al que sí
  /// (22 → 802.11b; 40 en 2.4 → 802.11n; 80/160 → 802.11ac). Si el canal
  /// primario no tiene bloque de ese ancho, se mueve al válido más cercano;
  /// con [moverPrimario] en false se deja igual (y validarAp lo rechaza).
  PuntoAcceso conAncho(
    int ancho, {
    Set<int> evitar = const {},
    bool moverPrimario = true,
  }) {
    var e = estandar;
    if (!e.anchosEn(banda).contains(ancho)) {
      e = switch ((banda, ancho)) {
        (Banda.ghz24, 22) => Estandar.b,
        (Banda.ghz24, 20) => Estandar.g,
        (Banda.ghz24, _) => Estandar.n,
        (_, 20 || 40) => Estandar.n.permite(banda) && estandar != Estandar.ac
            ? Estandar.n
            : Estandar.ac,
        _ => Estandar.ac,
      };
    }
    return copyWith(
      anchoMHz: ancho,
      estandar: e,
      canalPrimario: moverPrimario
          ? ajustarPrimario(banda, ancho, canalPrimario, evitar: evitar)
          : canalPrimario,
    );
  }

  /// El mismo AP (mismo id y mismo nivel) en otro canal primario y ancho.
  /// En un AP escaneado se suelta el centro real de Android, que era del
  /// bloque viejo: el bloque nuevo sale del primario y el ancho. El RSSI se
  /// conserva, así que el nivel no cambia (en uno simulado se conservan PIRE
  /// y distancia). Si el estándar no admite el ancho, conAncho lo cambia.
  PuntoAcceso conCanal(int primario, int ancho) =>
      copyWith(canalPrimario: primario, sinCentroReal: true)
          .conAncho(ancho, moverPrimario: false);

  @override
  String toString() => '$nombre (${banda.nombre}, canal $canalPrimario, $anchoMHz MHz)';
}

/// Error que impide guardar el AP, o null si está bien. Los APs escaneados
/// no se validan: muestran lo que reporta Android, aunque no cuadre.
String? validarAp(PuntoAcceso ap) {
  if (ap.escaneado) return null;
  if (ap.nombre.trim().isEmpty) return 'Ponle un nombre al AP.';
  if (ap.banda == Banda.ghz6) return 'La banda de 6 GHz no se simula.';
  if (ap.estandar == Estandar.desconocido) return 'Elige un estándar.';
  if (!ap.estandar.permite(ap.banda)) {
    return '${ap.estandar.nombre} no opera en ${ap.banda.nombre}.';
  }
  if (!ap.estandar.anchosEn(ap.banda).contains(ap.anchoMHz)) {
    return '${ap.estandar.nombre} no admite ${ap.anchoMHz} MHz en ${ap.banda.nombre}.';
  }
  if (!primariosValidos(ap.banda, ap.anchoMHz).contains(ap.canalPrimario)) {
    return 'El canal ${ap.canalPrimario} no forma un bloque de ${ap.anchoMHz} MHz.';
  }
  if (ap.potenciaDbm < 0 || ap.potenciaDbm > 30) {
    return 'La potencia debe estar entre 0 y 30 dBm.';
  }
  return null;
}

/// Una línea: "Canal 6 · 2437 MHz · 20 MHz · 2427–2447 MHz".
String resumenAp(PuntoAcceso ap) {
  final c = ap.canalOcupado;
  return 'Canal ${ap.canalPrimario} · ${ap.frecuenciaPrimariaMHz} MHz · '
      '${c.anchoMHz} MHz · ${_f(c.inicioMHz)}–${_f(c.finMHz)} MHz';
}

/// En qué canales y frecuencias opera el AP, en líneas para la UI.
List<String> describirOperacion(PuntoAcceso ap) {
  final c = ap.canalOcupado;
  final p = ap.canalPrimario;
  final reportado = ap.estandarReportado;
  final estandar = !ap.escaneado || reportado == null
      ? ap.estandar.etiqueta
      : ap.estandarAprox
          ? '$reportado (dibujado como ${ap.estandar.etiqueta}, aprox.)'
          : reportado;
  final lineas = <String>[
    '$estandar · canal primario $p (${ap.frecuenciaPrimariaMHz} MHz)',
  ];
  if (c.subcanales.length > 1) {
    lineas.add('Bloque de ${c.anchoMHz} MHz centrado en ${c.centroMHz} MHz '
        '(canal ${c.numero}), ocupa ${_f(c.inicioMHz)}–${_f(c.finMHz)} MHz');
    final partes = [
      for (final s in c.subcanales)
        '$s (${frecuenciaDeCanal(ap.banda, s)} MHz)${s == p ? ', primario' : ''}',
    ];
    lineas.add('Canales de 20 MHz que usa: ${partes.join(' · ')}');
  } else {
    final que = ap.paso.dsss ? 'lóbulo principal DSSS' : 'canal OFDM';
    lineas.add('Ocupa ${_f(c.inicioMHz)}–${_f(c.finMHz)} MHz '
        '(${c.anchoMHz} MHz, $que), centro ${c.centroMHz} MHz');
  }
  lineas.add('Sub-banda: ${c.subbanda} · beacons en el canal $p');
  return lineas;
}

/// Emisor de la animación a partir del AP. La semilla sale del id, así que el
/// mismo AP genera siempre el mismo tráfico.
EmisorDemo emisorDeAp(PuntoAcceso ap, {bool animado = false}) {
  var h = 7;
  for (final u in ap.id.codeUnits) {
    h = (h * 31 + u) & 0x3fffffff;
  }
  return EmisorDemo(
    id: ap.id,
    nombre: ap.nombre,
    primario: ap.canalPrimario,
    paso: ap.paso,
    carga: ap.carga,
    desfaseBeaconMs: (2 + h % 90).toDouble(),
    semilla: h,
    colorIndice: ap.colorIndice,
    animado: animado,
  );
}
