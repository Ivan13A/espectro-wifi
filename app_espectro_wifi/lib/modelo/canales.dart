// Modelo de canales Wi-Fi para Colombia.
//
// Fuentes:
// - Res. ANE 105 de 2020, Título 4 y Anexo 1 "Frecuencias de uso libre".
//   Bandas de 5 GHz en el numeral 3.8.1 (corregido por Res. ANE 469 de 2020, art. 8):
//   5150-5250, 5250-5350, 5470-5725 y 5725-5850 MHz.
// - Res. ANE 737 de 2022: 5925-7125 MHz (6 GHz) para sistemas de acceso
//   inalámbrico de uso libre. No se dibuja, pero el escaneo la reconoce.
// - Numeración de canales: IEEE 802.11.
//     2.4 GHz: f = 2407 + 5·n MHz (n = 1..13; el 14 = 2484 MHz es solo Japón)
//     5 GHz:   f = 5000 + 5·n MHz
//     6 GHz:   f = 5950 + 5·n MHz (excepción: canal 2 = 5935 MHz)
//
// La tabla de canales es para la SIMULACIÓN (lo que el usuario puede elegir).
// El escaneo real usa clasificarRed(), que acepta cualquier frecuencia y marca
// lo que esté fuera de la norma colombiana en vez de descartarlo.

enum Banda {
  ghz24('2.4 GHz'),
  ghz5('5 GHz'),
  ghz6('6 GHz');

  const Banda(this.nombre);
  final String nombre;
}

/// Tipo de señal en 2.4 GHz. Cambia el ancho y por tanto el solapamiento.
enum Modo24 {
  /// 802.11b, DSSS: lóbulo principal de 22 MHz.
  dsss22('802.11b (DSSS)', 22),

  /// 802.11g/n, OFDM: canal nominal de 20 MHz.
  ofdm20('802.11g/n (OFDM)', 20);

  const Modo24(this.nombre, this.anchoMHz);
  final String nombre;
  final int anchoMHz;
}

/// Rango de frecuencias en MHz, cerrado: [inicio, fin].
class Rango {
  const Rango(this.inicioMHz, this.finMHz, [this.nombre = '']);
  final double inicioMHz;
  final double finMHz;
  final String nombre;

  bool contiene(double desde, double hasta) =>
      desde >= inicioMHz && hasta <= finMHz;

  bool contienePunto(double f) => f >= inicioMHz && f <= finMHz;

  @override
  String toString() => '$nombre [$inicioMHz–$finMHz MHz]';
}

/// Rangos de uso libre en Colombia por banda.
abstract final class NormaColombia {
  // Banda ISM de 2.4 GHz, uso libre. Fuente: presentación MinTIC sobre normatividad
  // de uso libre (mintic.gov.co/portal/715/articles-273358_memorias_05.pdf).
  static const banda24 = Rango(2400, 2483.5, 'ISM 2.4 GHz');

  static const unii1 = Rango(5150, 5250, 'U-NII-1');
  static const unii2a = Rango(5250, 5350, 'U-NII-2A');
  static const unii2c = Rango(5470, 5725, 'U-NII-2C');
  static const unii3 = Rango(5725, 5850, 'U-NII-3');
  static const subbandas5 = [unii1, unii2a, unii2c, unii3];

  /// Tramos contiguos de 5 GHz. Un canal puede cruzar el límite entre
  /// sub-bandas vecinas (p. ej. el 144 cruza 5725 MHz) y seguir siendo legal.
  static const tramos5 = [Rango(5150, 5350), Rango(5470, 5850)];

  static const banda6 = Rango(5925, 7125, '6 GHz (Res. ANE 737/2022)');

  static List<Rango> tramosDe(Banda b) => switch (b) {
        Banda.ghz24 => const [banda24],
        Banda.ghz5 => tramos5,
        Banda.ghz6 => const [banda6],
      };

  /// Rango total que se dibuja para cada banda.
  static Rango rangoBanda(Banda b) => switch (b) {
        Banda.ghz24 => banda24,
        Banda.ghz5 => const Rango(5150, 5850, '5 GHz'),
        Banda.ghz6 => banda6,
      };
}

/// Frecuencia central (MHz) del canal [n] según IEEE 802.11.
int frecuenciaDeCanal(Banda banda, int n) => switch (banda) {
      Banda.ghz24 => n == 14 ? 2484 : 2407 + 5 * n,
      Banda.ghz5 => 5000 + 5 * n,
      Banda.ghz6 => n == 2 ? 5935 : 5950 + 5 * n,
    };

/// Número de canal IEEE para una frecuencia central, o null si no cuadra
/// con la rejilla de 5 MHz de esa banda.
int? canalDeFrecuencia(Banda banda, int fMHz) {
  switch (banda) {
    case Banda.ghz24:
      if (fMHz == 2484) return 14;
      final d = fMHz - 2407;
      return d % 5 == 0 ? d ~/ 5 : null;
    case Banda.ghz5:
      final d = fMHz - 5000;
      return d % 5 == 0 ? d ~/ 5 : null;
    case Banda.ghz6:
      if (fMHz == 5935) return 2;
      final d = fMHz - 5950;
      return d % 5 == 0 ? d ~/ 5 : null;
  }
}

/// Banda a la que pertenece una frecuencia, o null si no es Wi-Fi conocido.
/// Los márgenes son amplios a propósito: así un AP fuera de norma (p. ej. canal 14
/// o U-NII-4) se reconoce como de su banda y se marca, en vez de perderse.
Banda? bandaDeFrecuencia(int fMHz) {
  if (fMHz >= 2400 && fMHz <= 2500) return Banda.ghz24;
  if (fMHz >= 4900 && fMHz < 5925) return Banda.ghz5;
  if (fMHz >= 5925 && fMHz <= 7125) return Banda.ghz6;
  return null;
}

/// Un canal (de 20/22 MHz o un bloque agrupado de 40/80/160 MHz).
class Canal {
  const Canal({
    required this.banda,
    required this.numero,
    required this.centroMHz,
    required this.anchoMHz,
    required this.subcanales,
  });

  final Banda banda;

  /// Número IEEE. En bloques agrupados es el número del centro (p. ej. 42 en 80 MHz).
  final int numero;
  final int centroMHz;
  final int anchoMHz;

  /// Canales de 20 MHz que cubre el bloque. En 20/22 MHz es solo [numero].
  final List<int> subcanales;

  double get inicioMHz => centroMHz - anchoMHz / 2;
  double get finMHz => centroMHz + anchoMHz / 2;

  /// Sub-banda(s) donde cae el canal: 'U-NII-1', 'U-NII-1 + U-NII-2A', etc.
  String get subbanda {
    if (banda == Banda.ghz24) return NormaColombia.banda24.nombre;
    if (banda == Banda.ghz6) return NormaColombia.banda6.nombre;
    final nombres = <String>{};
    for (final s in subcanales) {
      final f = frecuenciaDeCanal(Banda.ghz5, s).toDouble();
      for (final r in NormaColombia.subbandas5) {
        if (r.contienePunto(f)) {
          nombres.add(r.nombre);
          break;
        }
      }
    }
    return nombres.join(' + ');
  }

  /// true si los rangos ocupados se pisan (tocarse en el borde no cuenta).
  bool solapaCon(Canal otro) =>
      banda == otro.banda &&
      inicioMHz < otro.finMHz &&
      otro.inicioMHz < finMHz;

  /// MHz compartidos con otro canal (0 si no se solapan).
  double solapamientoMHz(Canal otro) {
    if (!solapaCon(otro)) return 0;
    final a = inicioMHz > otro.inicioMHz ? inicioMHz : otro.inicioMHz;
    final b = finMHz < otro.finMHz ? finMHz : otro.finMHz;
    return b - a;
  }

  @override
  String toString() =>
      'Canal $numero ($centroMHz MHz, $anchoMHz MHz, ${banda.nombre})';
}

/// Catálogo de canales que el usuario puede elegir en la simulación.
abstract final class CatalogoCanales {
  /// Canales de 20 MHz de 5 GHz permitidos en Colombia (25 en total).
  static const canales5de20 = [
    36, 40, 44, 48, // U-NII-1
    52, 56, 60, 64, // U-NII-2A
    100, 104, 108, 112, 116, 120, 124, 128, 132, 136, 140, 144, // U-NII-2C
    149, 153, 157, 161, 165, // U-NII-3
  ];

  /// Primer canal de 20 MHz de cada bloque agrupado en 5 GHz.
  static const _inicios5 = {
    40: [36, 44, 52, 60, 100, 108, 116, 124, 132, 140, 149, 157],
    80: [36, 52, 100, 116, 132, 149],
    160: [36, 100],
  };

  /// Canales de 2.4 GHz (1-13) con el ancho del modo elegido.
  static List<Canal> canales24(Modo24 modo) => [
        for (var n = 1; n <= 13; n++)
          Canal(
            banda: Banda.ghz24,
            numero: n,
            centroMHz: frecuenciaDeCanal(Banda.ghz24, n),
            anchoMHz: modo.anchoMHz,
            subcanales: [n],
          ),
      ];

  /// Bloques de 40 MHz en 2.4 GHz (802.11n HT40): primario + secundario a 4
  /// canales. Se identifican por el canal central, de 3 a 11.
  static List<Canal> canales24de40() => [
        for (var c = 3; c <= 11; c++)
          Canal(
            banda: Banda.ghz24,
            numero: c,
            centroMHz: frecuenciaDeCanal(Banda.ghz24, c),
            anchoMHz: 40,
            subcanales: [c - 2, c + 2],
          ),
      ];

  /// Canales de 5 GHz para un ancho de 20, 40, 80 o 160 MHz.
  static List<Canal> canales5(int anchoMHz) {
    if (anchoMHz == 20) {
      return [
        for (final n in canales5de20)
          Canal(
            banda: Banda.ghz5,
            numero: n,
            centroMHz: frecuenciaDeCanal(Banda.ghz5, n),
            anchoMHz: 20,
            subcanales: [n],
          ),
      ];
    }
    final inicios = _inicios5[anchoMHz];
    if (inicios == null) {
      throw ArgumentError('Ancho no válido en 5 GHz: $anchoMHz MHz');
    }
    final k = anchoMHz ~/ 20;
    return [
      for (final p in inicios)
        Canal(
          banda: Banda.ghz5,
          numero: p + 2 * (k - 1),
          centroMHz: frecuenciaDeCanal(Banda.ghz5, p + 2 * (k - 1)),
          anchoMHz: anchoMHz,
          subcanales: [for (var i = 0; i < k; i++) p + 4 * i],
        ),
    ];
  }

  static const anchos5 = [20, 40, 80, 160];

  /// Canales de 20 MHz de 5 GHz que no caben en ningún bloque del ancho dado
  /// (p. ej. el 165 en 40 y 80 MHz). En 20 MHz la lista sale vacía.
  static List<int> canales5SinBloque(int anchoMHz) {
    final cubiertos = {for (final c in canales5(anchoMHz)) ...c.subcanales};
    return [for (final n in canales5de20) if (!cubiertos.contains(n)) n];
  }
}

/// Conjunto más grande de canales que no se pisan entre sí. Tocarse en el
/// borde se permite, igual que en [Canal.solapaCon]. Usa el algoritmo voraz
/// por frecuencia de fin, que da el óptimo para intervalos; ante varios
/// conjuntos igual de grandes, elige el que empieza más abajo (p. ej. 1/6/11).
List<Canal> canalesSinSolapamiento(List<Canal> canales) {
  final orden = [...canales]..sort((a, b) => a.finMHz.compareTo(b.finMHz));
  final elegidos = <Canal>[];
  for (final c in orden) {
    if (elegidos.isEmpty || c.inicioMHz >= elegidos.last.finMHz) elegidos.add(c);
  }
  return elegidos;
}

/// Resultado de clasificar una red detectada por el escaneo real.
class ClasificacionRed {
  const ClasificacionRed({
    required this.frecuenciaMHz,
    required this.anchoMHz,
    required this.centroMHz,
    required this.banda,
    required this.canalPrimario,
    required this.dentroNorma,
    required this.observacion,
  });

  /// Centro del canal primario de 20 MHz (`frequency` de Android).
  final int frecuenciaMHz;
  final int anchoMHz;

  /// Centro real del bloque (`centerFreq0` si el ancho es > 20 MHz).
  final int centroMHz;

  /// null si la frecuencia no corresponde a ninguna banda Wi-Fi conocida.
  final Banda? banda;

  /// null si la frecuencia no cuadra con la rejilla IEEE.
  final int? canalPrimario;
  final bool dentroNorma;

  /// Explicación para mostrar en la UI ('' si todo está bien).
  final String observacion;

  /// Las redes de 6 GHz van en una lista aparte (no se dibujan).
  bool get vaEnListaAparte => banda == Banda.ghz6;

  double get inicioMHz => centroMHz - anchoMHz / 2;
  double get finMHz => centroMHz + anchoMHz / 2;
}

/// Clasifica una red del escaneo real. Nunca lanza excepción ni descarta la red:
/// si algo no cuadra, lo dice en [ClasificacionRed.observacion].
///
/// [frecuenciaMHz]: `frequency` de Android (centro del primario de 20 MHz).
/// [anchoMHz]: ancho reportado (20, 40, 80, 160...). Si no se conoce, 20.
/// [centroMHz]: `centerFreq0` de Android; se usa solo si el ancho es > 20 MHz.
ClasificacionRed clasificarRed({
  required int frecuenciaMHz,
  int anchoMHz = 20,
  int? centroMHz,
}) {
  final centro =
      (anchoMHz > 20 && centroMHz != null && centroMHz > 0) ? centroMHz : frecuenciaMHz;
  final banda = bandaDeFrecuencia(frecuenciaMHz);

  if (banda == null) {
    return ClasificacionRed(
      frecuenciaMHz: frecuenciaMHz,
      anchoMHz: anchoMHz,
      centroMHz: centro,
      banda: null,
      canalPrimario: null,
      dentroNorma: false,
      observacion: 'Frecuencia fuera de las bandas Wi-Fi conocidas',
    );
  }

  final canal = canalDeFrecuencia(banda, frecuenciaMHz);
  final inicio = centro - anchoMHz / 2;
  final fin = centro + anchoMHz / 2;
  final enTramo = NormaColombia.tramosDe(banda).any((r) => r.contiene(inicio, fin));

  String obs = '';
  if (canal == null) {
    obs = 'Frecuencia no alineada con la rejilla de canales IEEE';
  } else if (!enTramo) {
    obs = 'Fuera de la norma colombiana (ocupa $inicio–$fin MHz)';
  }

  return ClasificacionRed(
    frecuenciaMHz: frecuenciaMHz,
    anchoMHz: anchoMHz,
    centroMHz: centro,
    banda: banda,
    canalPrimario: canal,
    dentroNorma: canal != null && enTramo,
    observacion: obs,
  );
}
