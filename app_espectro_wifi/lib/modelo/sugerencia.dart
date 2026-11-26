// "Sugerir canal": prueba el AP objetivo en cada canal y ancho candidatos y
// los ordena con el mismo analizar() del incremento 4b. No hay métricas
// nuevas: solo la gravedad y la SIR propias, la gravedad de los demás y la
// contención (con cuántos se turna). Dart puro, sin Flutter.
//
// Candidatos:
//  - 2.4 GHz: solo 1, 6 y 11 a 20 MHz (los únicos no solapados; 40 MHz no se
//    recomienda en 2.4 GHz). Ver [regla24].
//  - 5 GHz: todos los pares (primario, ancho) válidos para su estándar.
//  - En las dos bandas se descartan los que usan un canal desactivado, y la
//    configuración actual entra siempre para comparar.
//
// Orden lexicográfico (de mejor a peor):
//  1. Gravedad de la SIR propia: {sin interferencia, leve} < moderada < grave
//     (con SIR ≥ 27 dB ya cabe la tasa más alta; las frases muestran la real).
//  2. Cuántos de los otros APs quedan con peor gravedad que con la
//     configuración actual.
//  3. Cuántos APs se turnan con él (contención).
//  4. La SIR mayor, solo dentro de grave o moderada (en leve o sin
//     interferencia ya cabe la tasa más alta, así que no desempata).
//  5. En 5 GHz, el ancho mayor.
//  Empate total: OFDM antes que 802.11b, y luego la configuración actual.
import 'analisis.dart';
import 'canales.dart';
import 'punto_acceso.dart';

/// Regla general de 2.4 GHz, con sus fuentes (hoja y reporte).
const regla24 =
    'En 2.4 GHz solo se sugieren los canales 1, 6 y 11 a 20 MHz: son los únicos '
    'que no se solapan entre sí, y 40 MHz no se recomienda en 2.4 GHz porque ocupa '
    'casi toda la banda. Fuentes: guías de diseño de Cisco Meraki, Extreme Networks '
    'y Sophos.';

/// Supuesto de la evaluación (hoja y reporte).
const supuestoSugerencia =
    'La evaluación es desde el punto donde está el celular, con las redes de este '
    'escaneo (y los APs simulados que transmiten). El AP conserva su nivel: el RSSI '
    'si es real; la PIRE y la distancia si es simulado.';

const canales24Sugeridos = [1, 6, 11];

/// Nota para los candidatos con canales de U-NII-2A o U-NII-2C (52 a 144).
/// Solo se informa: no cambia el orden.
const notaDfs =
    'usa canales que en EE. UU. y Europa exigen DFS (detección de radar); en Colombia, '
    'por confirmar en el Anexo 1 de la Res. ANE 105/2020';

/// Se agrega a la frase de un candidato OFDM que empata en todo con la
/// configuración actual en 802.11b y gana por el desempate de modulación.
const notaDsss =
    '802.11b usa tasas de hasta 11 Mb/s que ocupan más tiempo de aire y obligan a '
    'los equipos g/n cercanos a usar protección.';

/// Si el AP usa algún canal de 20 MHz de U-NII-2A o U-NII-2C (52 a 144).
bool usaCanalesDfs(PuntoAcceso ap) =>
    ap.banda == Banda.ghz5 &&
    {ap.canalPrimario, ...ap.canalOcupado.subcanales}.any((n) => n >= 52 && n <= 144);

/// Una configuración (primario, ancho) evaluada para el AP objetivo.
class OpcionCanal {
  OpcionCanal._({
    required this.ap,
    required this.propio,
    required this.empeorados,
    required this.esActual,
    required this.bloqueados,
  });

  /// El AP objetivo con esta configuración (mismo id y mismo nivel).
  final PuntoAcceso ap;

  /// Análisis del AP objetivo con esta configuración.
  final AnalisisAp propio;

  /// Otros APs que quedan con peor gravedad que con la configuración actual.
  final List<PuntoAcceso> empeorados;

  final bool esActual;

  /// Canales desactivados que usa (solo puede pasar en la actual).
  final List<int> bloqueados;

  /// La razón y la comparación con la actual (las llena [sugerirCanal]).
  late final String razon;
  late final String comparacion;

  int get primario => ap.canalPrimario;
  int get anchoMHz => ap.anchoMHz;
  Gravedad? get gravedad => propio.gravedad;
  double? get sirDb => propio.sirDb;
  List<PuntoAcceso> get contencion => propio.contencion;

  /// "Canal 1 · 20 MHz" o "Canal 100 · 160 MHz (canales 100–128)".
  String get etiqueta {
    final s = ap.canalOcupado.subcanales;
    final bloque = s.length > 1 ? ' (canales ${s.first}–${s.last})' : '';
    return 'Canal $primario · $anchoMHz MHz$bloque';
  }
}

class SugerenciaCanal {
  const SugerenciaCanal({
    required this.objetivo,
    required this.actual,
    required this.mejores,
    required this.actualEsMejor,
  });

  final PuntoAcceso objetivo;
  final OpcionCanal actual;

  /// Las 3 mejores, sin la actual.
  final List<OpcionCanal> mejores;

  /// La actual quedó primera en el orden (y transmite).
  final bool actualEsMejor;

  /// La actual y las mejores, en ese orden.
  List<OpcionCanal> get opciones => [actual, ...mejores];
}

/// 0 = sin interferencia, 1 = leve, 2 = moderada, 3 = grave.
int _rango(Gravedad? g) => g == null ? 0 : g.index + 1;

/// Nivel del criterio 1: sin interferencia y leve van juntos (con SIR ≥ 27 dB
/// ya cabe la tasa más alta), luego moderada y grave. Las frases muestran la
/// gravedad real.
int _nivelOrden(Gravedad? g) => switch (g) {
      null || Gravedad.leve => 0,
      Gravedad.moderada => 1,
      Gravedad.grave => 2,
    };

String _nombres(List<PuntoAcceso> aps) => aps.map((a) => a.nombre).join(', ');

String _cuantos(int n) => n == 1 ? '1 AP' : '$n APs';

String _textoPropio(AnalisisAp p) {
  final g = p.gravedad;
  if (g == null) return 'sin interferencia simultánea';
  return 'interferencia ${g.nombre.toLowerCase()} (SIR ${textoDb(p.sirDb!)}) de '
      '${_nombres(p.interferentes)}';
}

String _textoCorto(AnalisisAp p) {
  final g = p.gravedad;
  return g == null ? 'sin interferencia' : '${g.nombre.toLowerCase()} (SIR ${textoDb(p.sirDb!)})';
}

/// Candidatos (primario, ancho) para [objetivo], sin canales desactivados.
List<PuntoAcceso> _candidatos(PuntoAcceso objetivo, Set<int> desactivados) {
  final lista = <PuntoAcceso>[];
  void probar(int primario, int ancho) {
    final c = objetivo.conCanal(primario, ancho);
    final usados = {c.canalPrimario, ...c.canalOcupado.subcanales};
    if (usados.any(desactivados.contains)) return;
    lista.add(c);
  }

  switch (objetivo.banda) {
    case Banda.ghz24:
      for (final n in canales24Sugeridos) {
        probar(n, 20);
      }
    case Banda.ghz5:
      final anchos = objetivo.estandar.anchosEn(Banda.ghz5);
      for (final ancho in anchos.isEmpty ? const [20] : anchos) {
        for (final n in primariosValidos(Banda.ghz5, ancho)) {
          probar(n, ancho);
        }
      }
    case Banda.ghz6:
      break;
  }
  return lista;
}

/// Sugiere canal y ancho para [objetivo]. [otros]: los APs que transmiten en
/// su banda (si viene el objetivo o APs de otra banda, se ignoran).
/// [desactivados]: canales de 20 MHz desactivados en la banda.
SugerenciaCanal sugerirCanal(
  PuntoAcceso objetivo,
  List<PuntoAcceso> otros, {
  Set<int> desactivados = const {},
  int cuantos = 3,
}) {
  final vecinos = [
    for (final o in otros)
      if (o.id != objetivo.id && o.banda == objetivo.banda) o,
  ];

  AnalisisBanda evaluar(PuntoAcceso x) => analizar([...vecinos, x]);

  final base = evaluar(objetivo);
  final rangoBase = {
    for (final o in vecinos) o.id: _rango(base.porAp[o.id]!.gravedad),
  };

  OpcionCanal opcion(PuntoAcceso x, AnalisisBanda a, {required bool esActual}) {
    final usados = {x.canalPrimario, ...x.canalOcupado.subcanales};
    return OpcionCanal._(
      ap: x,
      propio: a.porAp[x.id]!,
      empeorados: [
        for (final o in vecinos)
          if (_rango(a.porAp[o.id]!.gravedad) > rangoBase[o.id]!) o,
      ],
      esActual: esActual,
      bloqueados: [for (final n in usados) if (desactivados.contains(n)) n]..sort(),
    );
  }

  final actual = opcion(objetivo, base, esActual: true);
  final todas = <OpcionCanal>[actual];
  for (final c in _candidatos(objetivo, desactivados)) {
    if (c.canalPrimario == objetivo.canalPrimario && c.anchoMHz == objetivo.anchoMHz) {
      continue; // es la actual
    }
    todas.add(opcion(c, evaluar(c), esActual: false));
  }

  final indice = {for (var i = 0; i < todas.length; i++) todas[i]: i};
  final es5 = objetivo.banda == Banda.ghz5;
  /// Criterios 1 a 4 (0 = empate total).
  int criterios(OpcionCanal x, OpcionCanal y) {
    var d = _nivelOrden(x.gravedad).compareTo(_nivelOrden(y.gravedad));
    if (d != 0) return d;
    d = x.empeorados.length.compareTo(y.empeorados.length);
    if (d != 0) return d;
    d = x.contencion.length.compareTo(y.contencion.length);
    if (d != 0) return d;
    final g = x.gravedad; // la misma que la de y
    if (g == Gravedad.grave || g == Gravedad.moderada) {
      d = y.sirDb!.compareTo(x.sirDb!);
      if (d != 0) return d;
    }
    return es5 ? y.anchoMHz.compareTo(x.anchoMHz) : 0;
  }

  int comparar(OpcionCanal x, OpcionCanal y) {
    final d = criterios(x, y);
    if (d != 0) return d;
    // Empate total: OFDM (g/n) antes que DSSS (802.11b).
    final dx = x.ap.paso.dsss, dy = y.ap.paso.dsss;
    if (dx != dy) return dx ? 1 : -1;
    return indice[x]!.compareTo(indice[y]!);
  }

  final ordenadas = [...todas]..sort(comparar);
  final mejores = [for (final o in ordenadas) if (!o.esActual) o].take(cuantos).toList();

  for (final o in [actual, ...mejores]) {
    // OFDM que le gana a la actual DSSS solo por el desempate de modulación.
    final porOfdm = !o.esActual &&
        actual.ap.paso.dsss &&
        !o.ap.paso.dsss &&
        criterios(o, actual) == 0;
    o.razon = _razon(o, objetivo) + (porOfdm ? ' $notaDsss' : '');
    o.comparacion = o.esActual ? '' : _comparacion(o, actual);
  }

  return SugerenciaCanal(
    objetivo: objetivo,
    actual: actual,
    mejores: mejores,
    actualEsMejor: identical(ordenadas.first, actual) && actual.bloqueados.isEmpty,
  );
}

String _razon(OpcionCanal o, PuntoAcceso objetivo) {
  final p = o.propio;
  final cont = p.contencion.isEmpty
      ? 'no se turna con ningún AP'
      : 'se turna con ${_cuantos(p.contencion.length)} (${_nombres(p.contencion)})';
  final emp = o.empeorados.isEmpty
      ? ''
      : '; empeora a ${_cuantos(o.empeorados.length)} (${_nombres(o.empeorados)})';
  final bloq = o.bloqueados.isEmpty
      ? ''
      : ' Hoy no transmite: usa ${o.bloqueados.length == 1 ? 'el canal desactivado' : 'los canales desactivados'} '
          '${o.bloqueados.join(', ')}.';
  final estandar = o.ap.estandar == objetivo.estandar
      ? ''
      : ' A ${o.anchoMHz} MHz pasa de ${objetivo.estandar.nombre} a ${o.ap.estandar.nombre}.';
  final dfs = usaCanalesDfs(o.ap) ? '; $notaDfs' : '';
  return '${o.etiqueta}: ${_textoPropio(p)}; $cont$emp$dfs.$bloq$estandar';
}

String _comparacion(OpcionCanal o, OpcionCanal actual) {
  final antes = _textoCorto(actual.propio), despues = _textoCorto(o.propio);
  final ca = actual.contencion.length, co = o.contencion.length;
  if (antes == despues && ca == co && o.empeorados.isEmpty) {
    final wa = actual.anchoMHz, wo = o.anchoMHz;
    if (wa != wo && !actual.ap.paso.dsss && !o.ap.paso.dsss) {
      return 'Mismo resultado, con $wo MHz en vez de $wa MHz '
          '(${wo > wa ? 'más' : 'menos'} capacidad).';
    }
    return 'Igual que la actual (${actual.etiqueta}).';
  }
  final partes = <String>[if (antes != despues) '$antes → $despues'];
  if (ca != co) partes.add('se turna con $ca → $co');
  if (o.empeorados.isNotEmpty) partes.add('empeora a ${_cuantos(o.empeorados.length)}');
  return 'Frente a la actual (${actual.etiqueta}): ${partes.join('; ')}.';
}
