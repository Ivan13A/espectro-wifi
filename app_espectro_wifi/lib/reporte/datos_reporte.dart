// Incremento 6: datos del reporte PDF. Se arman con lo que la app ya calcula
// (ModeloAps.transmitiendoEn y analizar()); reporte_pdf.dart solo los
// formatea, no recalcula nada. Dart puro, sin Flutter.
import 'dart:typed_data';

import '../modelo/analisis.dart';
import '../modelo/canales.dart';
import '../modelo/lista_aps.dart';
import '../modelo/punto_acceso.dart';
import '../modelo/sugerencia.dart';

/// Lo de una banda: sus APs, el análisis y la figura del espectro.
class BandaReporte {
  const BandaReporte({
    required this.banda,
    required this.aps,
    required this.transmitiendo,
    required this.analisis,
    required this.soloReales,
    this.figuraPng,
  });

  /// Toma la lista y el análisis tal como los usa la pantalla.
  factory BandaReporte.desdeModelo(
    ModeloAps modelo,
    Banda banda, {
    Uint8List? figuraPng,
  }) {
    final tx = modelo.transmitiendoEn(banda);
    return BandaReporte(
      banda: banda,
      aps: modelo.de(banda),
      transmitiendo: tx,
      analisis: analizar(tx),
      soloReales: modelo.soloReales(banda),
      figuraPng: figuraPng,
    );
  }

  final Banda banda;

  /// Todos los APs de la banda (también los apagados).
  final List<PuntoAcceso> aps;

  /// Los que transmiten: encendidos y sin canales desactivados.
  final List<PuntoAcceso> transmitiendo;
  final AnalisisBanda analisis;

  /// Si "Solo redes reales" estaba activo en la banda.
  final bool soloReales;

  /// Espectro con los APs, en PNG (null si no se pudo dibujar o en pruebas).
  final Uint8List? figuraPng;

  /// APs de la lista que no transmiten (apagados o en un canal desactivado).
  int get noTransmiten => aps.length - transmitiendo.length;

  int get reales => aps.where((a) => a.escaneado).length;
  int get simulados => aps.length - reales;
  int get realesTx => transmitiendo.where((a) => a.escaneado).length;
  int get simuladosTx => transmitiendo.length - realesTx;

  /// Cuántos APs que transmiten usan cada canal de 20 MHz de la banda: un AP
  /// cuenta en cada canal de su bloque (primario y secundarios). Están todos
  /// los canales de la banda, también los que tienen 0.
  Map<int, int> get ocupacion20 {
    final m = {for (final n in canales20De(banda)) n: 0};
    for (final ap in transmitiendo) {
      for (final s in ap.canalOcupado.subcanales) {
        if (m.containsKey(s)) m[s] = m[s]! + 1;
      }
    }
    return m;
  }

  /// Canales de 20 MHz con más APs (vacío si ninguno tiene APs).
  List<int> get canalesMasOcupados {
    final m = ocupacion20;
    final max = m.values.fold(0, (a, b) => a > b ? a : b);
    if (max == 0) return const [];
    return [for (final e in m.entries) if (e.value == max) e.key];
  }

  /// Pares con solape de cada gravedad (la peor de las dos direcciones, como
  /// en la tarjeta de la app). Los que se turnan no tienen gravedad.
  int paresCon(Gravedad g) =>
      analisis.conSolape.where((p) => p.peorGravedad == g).length;

  int get paresSeTurnan =>
      analisis.conSolape.where((p) => p.tipo == TipoRelacion.seTurnan).length;
}

class DatosReporte {
  const DatosReporte({
    required this.fecha,
    required this.bandas,
    this.lugar = '',
    this.observaciones = '',
    this.modeloCelular,
    this.horaEscaneo,
    this.horaResultados,
    this.recomendaciones,
  });

  /// Cuándo se generó.
  final DateTime fecha;
  final String lugar;
  final String observaciones;

  /// Build.MODEL del celular; null en pruebas o si no se pudo leer.
  final String? modeloCelular;

  /// Último escaneo con respuesta de Android (null si no se escaneó).
  final DateTime? horaEscaneo;

  /// Cuándo vio Android las redes más recientes (si fue rechazado por el
  /// límite, puede ser anterior a [horaEscaneo]).
  final DateTime? horaResultados;

  /// 2.4 GHz y 5 GHz, en ese orden.
  final List<BandaReporte> bandas;

  /// Sección "Recomendaciones" (ver [recomendacionesDe]). Con null o vacía
  /// la sección no aparece.
  final List<String>? recomendaciones;
}

/// "Recomendaciones" del reporte: la sugerencia de canal para el AP
/// seleccionado en cada banda (el que el usuario tocó; si no tocó ninguno,
/// el primero de la banda), el supuesto y la regla general de 2.4 GHz. Si el
/// seleccionado no transmite (p. ej. un simulado apagado por "Solo redes
/// reales"), se usa la red real que transmite con mayor RSSI; si no hay
/// ninguna, la banda se omite.
List<String> recomendacionesDe(ModeloAps modelo) {
  final l = <String>[];
  for (final banda in const [Banda.ghz24, Banda.ghz5]) {
    final tx = modelo.transmitiendoEn(banda);
    final sel = modelo.seleccionado(banda);
    final PuntoAcceso ap;
    final String porQue;
    if (sel != null && modelo.transmite(sel)) {
      ap = sel;
      porQue = '${sel.escaneado ? 'real' : 'simulado'}, el AP seleccionado en la banda';
    } else {
      final reales = [for (final a in tx) if (a.escaneado && a.rssiDbm != null) a];
      if (reales.isEmpty) continue;
      ap = reales.reduce((x, y) => y.rssiDbm! > x.rssiDbm! ? y : x);
      porQue = 'la red real con señal más fuerte';
    }
    final s = sugerirCanal(ap, tx, desactivados: modelo.canalesDesactivados(banda));
    final quien = '${banda.nombre}, para ${ap.nombre} ($porQue)';
    l.add('$quien. Actual: ${s.actual.razon}');
    if (s.actualEsMejor) {
      l.add('${ap.nombre} ya está en la mejor opción según el análisis.');
    }
    for (final (i, o) in s.mejores.indexed) {
      l.add('${s.actualEsMejor ? 'Alternativa' : 'Opción'} ${i + 1}: ${o.razon} ${o.comparacion}');
    }
  }
  if (l.isEmpty) return l;
  l.add(supuestoSugerencia);
  l.add(regla24);
  return l;
}
