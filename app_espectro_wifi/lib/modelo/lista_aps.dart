// Lista de puntos de acceso de la app (incremento 4). Una sola lista para las
// dos bandas y para los dos orígenes: simulados (el usuario) y escaneados
// (incremento 5, con reemplazarEscaneados). La pantalla, el análisis y la
// animación la escuchan.
//
// Canales desactivados: un canal de 20 MHz desactivado no se puede asignar, y
// un AP que lo usa (en su primario o dentro de su bloque) deja de transmitir,
// como cuando DFS obliga a desalojar un canal. Es una simplificación: un AP
// real con un secundario bloqueado se estrecharía en vez de apagarse.
import 'package:flutter/foundation.dart';

import 'canales.dart';
import 'punto_acceso.dart';
import 'redes_escaneadas.dart' show duplicarComoSimulado;
import 'simulacion.dart';

class ModeloAps extends ChangeNotifier {
  ModeloAps([List<PuntoAcceso> iniciales = const []]) : _aps = [...iniciales] {
    _contador = _aps.length;
  }

  /// Arranca con los APs de demostración del incremento 3 (editables).
  /// Queda seleccionado el que era el emisor animado (AP-B en 2.4, AP-A en 5).
  factory ModeloAps.conEjemplo() {
    final m = ModeloAps([
      ..._ejemplo(Banda.ghz24, EmisoresDemo.ghz24, const [Estandar.b, Estandar.g, Estandar.g]),
      ..._ejemplo(Banda.ghz5, EmisoresDemo.ghz5, const [Estandar.ac, Estandar.ac, Estandar.ac]),
    ]);
    for (final banda in [Banda.ghz24, Banda.ghz5]) {
      final i = EmisoresDemo.de(banda).indexWhere((d) => d.animado);
      if (i >= 0) m._seleccion[banda] = '${banda.name}-ej$i';
    }
    return m;
  }

  static List<PuntoAcceso> _ejemplo(
      Banda banda, List<EmisorDemo> demos, List<Estandar> estandares) {
    return [
      for (var i = 0; i < demos.length; i++)
        PuntoAcceso(
          id: '${banda.name}-ej$i',
          nombre: demos[i].nombre,
          banda: banda,
          canalPrimario: demos[i].primario,
          anchoMHz: demos[i].paso.anchoMHz,
          estandar: estandares[i],
          carga: demos[i].carga,
          colorIndice: demos[i].colorIndice,
        ),
    ];
  }

  final List<PuntoAcceso> _aps;
  final _desactivados = <Banda, Set<int>>{};
  final _seleccion = <Banda, String>{};
  int _contador = 0;

  List<PuntoAcceso> get aps => List.unmodifiable(_aps);

  List<PuntoAcceso> de(Banda banda) => [for (final a in _aps) if (a.banda == banda) a];

  PuntoAcceso? porId(String id) => _aps.where((a) => a.id == id).firstOrNull;

  // --- Canales -----------------------------------------------------------------

  Set<int> canalesDesactivados(Banda banda) =>
      Set.unmodifiable(_desactivados[banda] ?? const <int>{});

  bool canalActivo(Banda banda, int n) => !(_desactivados[banda]?.contains(n) ?? false);

  /// Canales desactivados que usa el AP (vacío si no usa ninguno).
  List<int> canalesBloqueados(PuntoAcceso ap) {
    final off = _desactivados[ap.banda];
    if (off == null || off.isEmpty) return const [];
    final usados = {ap.canalPrimario, ...ap.canalOcupado.subcanales};
    return [for (final n in usados) if (off.contains(n)) n]..sort();
  }

  /// Si el AP transmite: encendido y sin canales desactivados.
  bool transmite(PuntoAcceso ap) => ap.activo && canalesBloqueados(ap).isEmpty;

  List<PuntoAcceso> transmitiendoEn(Banda banda) =>
      [for (final a in _aps) if (a.banda == banda && transmite(a)) a];

  void alternarCanal(Banda banda, int n) {
    final off = _desactivados.putIfAbsent(banda, () => <int>{});
    if (!off.remove(n)) off.add(n);
    notifyListeners();
  }

  void activarTodos(Banda banda) {
    _desactivados.remove(banda);
    notifyListeners();
  }

  // --- Selección (el AP al que mandan los chips de ancho al animar) ------------

  /// El AP seleccionado en [banda]; si no hay, el primero de la banda.
  PuntoAcceso? seleccionado(Banda banda) {
    final id = _seleccion[banda];
    final enBanda = de(banda);
    return enBanda.where((a) => a.id == id).firstOrNull ?? enBanda.firstOrNull;
  }

  void seleccionar(PuntoAcceso ap) {
    _seleccion[ap.banda] = ap.id;
    notifyListeners();
  }

  // --- Agregar, editar, quitar ------------------------------------------------

  /// Un AP nuevo para [banda] con valores razonables: nombre libre, color
  /// libre y el primer canal sin solaparse que no esté en uso ni desactivado.
  /// No lo agrega a la lista (eso lo hace [agregar] al guardar el editor).
  PuntoAcceso borrador(Banda banda) {
    final enBanda = de(banda);
    final usados = {for (final a in enBanda) a.canalPrimario};
    final off = _desactivados[banda] ?? const <int>{};
    final preferidos = banda == Banda.ghz24
        ? const [1, 6, 11, 3, 9, 13]
        : const [36, 52, 100, 149, 44, 60, 116, 157];
    final libre = preferidos.firstWhere(
      (n) => !usados.contains(n) && !off.contains(n),
      orElse: () => ajustarPrimario(banda, 20, preferidos.first, evitar: off),
    );
    final colores = {for (final a in enBanda) a.colorIndice};
    var color = 0;
    while (colores.contains(color)) {
      color++;
    }
    return PuntoAcceso(
      id: 'ap-${DateTime.now().microsecondsSinceEpoch}-${_contador + 1}',
      nombre: _nombreLibre(),
      banda: banda,
      canalPrimario: libre,
      anchoMHz: 20,
      estandar: banda == Banda.ghz24 ? Estandar.n : Estandar.ac,
      colorIndice: color,
    );
  }

  String _nombreLibre() {
    final nombres = {for (final a in _aps) a.nombre};
    for (var i = 0; i < 26; i++) {
      final s = 'AP-${String.fromCharCode(65 + i)}';
      if (!nombres.contains(s)) return s;
    }
    var k = _aps.length + 1;
    while (nombres.contains('AP-$k')) {
      k++;
    }
    return 'AP-$k';
  }

  void agregar(PuntoAcceso ap) {
    _contador++;
    _aps.add(ap);
    _seleccion[ap.banda] = ap.id;
    notifyListeners();
  }

  /// Reemplaza el AP con el mismo id. Si cambió de banda, queda seleccionado allá.
  void editar(PuntoAcceso ap) {
    final i = _aps.indexWhere((a) => a.id == ap.id);
    if (i < 0) return;
    _aps[i] = ap;
    _seleccion[ap.banda] = ap.id;
    notifyListeners();
  }

  void quitar(String id) {
    _aps.removeWhere((a) => a.id == id);
    _seleccion.removeWhere((_, v) => v == id);
    notifyListeners();
  }

  void alternarActivo(String id) {
    final ap = porId(id);
    if (ap == null) return;
    if (ap.escaneado) {
      if (ap.activo) {
        _realesApagados.add(id);
      } else {
        _realesApagados.remove(id);
      }
    }
    editar(ap.copyWith(activo: !ap.activo));
  }

  // --- Redes reales apagadas por el usuario ------------------------------------

  /// Ids de las redes reales que el usuario apagó (con su interruptor o con
  /// "Probar en simulación"). Siguen apagadas después de un escaneo nuevo; se
  /// encienden solo con su interruptor o con "Limpiar" ([limpiarEscaneados]).
  final _realesApagados = <String>{};

  bool realApagada(String id) => _realesApagados.contains(id);

  /// "Probar en simulación" de "Sugerir canal": crea una copia simulada de la
  /// red real [real] en el canal [primario] con [ancho] (mismo nivel, como
  /// duplicarComoSimulado), apaga la real y deja seleccionada la copia.
  PuntoAcceso probarEnSimulacion(PuntoAcceso real, int primario, int ancho) {
    final b = borrador(real.banda);
    // Primero el canal nuevo y luego la copia: así la distancia se despeja con
    // la frecuencia nueva y el nivel simulado queda igual al RSSI.
    final copia = duplicarComoSimulado(
      real.conCanal(primario, ancho),
      id: b.id,
      colorIndice: b.colorIndice,
    );
    final i = _aps.indexWhere((a) => a.id == real.id);
    if (i >= 0 && real.escaneado) {
      _aps[i] = _aps[i].copyWith(activo: false);
      _realesApagados.add(real.id);
    }
    _contador++;
    _aps.add(copia);
    _seleccion[copia.banda] = copia.id;
    notifyListeners();
    return copia;
  }

  // --- "Solo redes reales" -----------------------------------------------------

  /// Por banda: ids de los simulados que estaban encendidos cuando se activó.
  final _apagadosPorSoloReales = <Banda, Set<String>>{};

  bool soloReales(Banda banda) => _apagadosPorSoloReales.containsKey(banda);

  /// Activado: apaga los simulados encendidos de [banda] (sin borrarlos) y
  /// recuerda cuáles eran. Desactivado: enciende solo esos.
  void fijarSoloReales(Banda banda, bool valor) {
    if (valor == soloReales(banda)) return;
    if (valor) {
      final ids = <String>{};
      for (var i = 0; i < _aps.length; i++) {
        final a = _aps[i];
        if (a.banda == banda && !a.escaneado && a.activo) {
          ids.add(a.id);
          _aps[i] = a.copyWith(activo: false);
        }
      }
      _apagadosPorSoloReales[banda] = ids;
    } else {
      final ids = _apagadosPorSoloReales.remove(banda) ?? const <String>{};
      for (var i = 0; i < _aps.length; i++) {
        if (ids.contains(_aps[i].id)) _aps[i] = _aps[i].copyWith(activo: true);
      }
    }
    notifyListeners();
  }

  /// Incremento 5: cambia todos los APs escaneados por los del último escaneo
  /// y deja intactos los simulados. Las redes reales que el usuario apagó
  /// llegan apagadas.
  void reemplazarEscaneados(List<PuntoAcceso> escaneados) {
    _aps
      ..removeWhere((a) => a.escaneado)
      ..addAll([
        for (final a in escaneados)
          _realesApagados.contains(a.id) ? a.copyWith(activo: false) : a,
      ]);
    notifyListeners();
  }

  /// "Limpiar": quita las redes reales y olvida cuáles estaban apagadas.
  void limpiarEscaneados() {
    _realesApagados.clear();
    reemplazarEscaneados(const []);
  }
}
