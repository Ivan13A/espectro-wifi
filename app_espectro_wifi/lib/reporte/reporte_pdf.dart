// Incremento 6: reporte PDF del análisis (requisito 8 del examen). Recibe los
// datos ya calculados (DatosReporte) y solo los formatea: no recalcula nada.
// Tamaño carta, en español, con coma decimal (textoDbm/textoDb de analisis.dart).
//
// Fuente: Noto Sans (SIL OFL 1.1, assets/fuentes). No trae ≤ ≥ → ↔ ≈ ≠ ∞ ∫
// (verificado contra el cmap de los dos TTF); textoPdf() los cambia por
// equivalentes ASCII. Sí trae −, ·, ×, —, –, •, §, tildes y ñ.
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../modelo/analisis.dart';
import '../modelo/canales.dart';
import '../modelo/punto_acceso.dart';
import '../vista/pintor_espectro.dart' show ColoresEspectro;
import 'datos_reporte.dart';

// --- Fuentes y texto -------------------------------------------------------------

class FuentesReporte {
  FuentesReporte(this.normal, this.negrita);

  factory FuentesReporte.desdeBytes(ByteData normal, ByteData negrita) =>
      FuentesReporte(pw.Font.ttf(normal), pw.Font.ttf(negrita));

  /// Noto Sans desde los assets de la app.
  static Future<FuentesReporte> cargar() async => FuentesReporte.desdeBytes(
        await rootBundle.load('assets/fuentes/NotoSans-Regular.ttf'),
        await rootBundle.load('assets/fuentes/NotoSans-Bold.ttf'),
      );

  final pw.Font normal;
  final pw.Font negrita;
}

/// Caracteres que Noto Sans no tiene y su equivalente.
const _sinGlifo = {
  '≤': '<=',
  '≥': '>=',
  '→': '->',
  '↔': '<->',
  '≈': '~',
  '≠': '!=',
  '∞': 'inf',
  '∫': 'int',
};

/// [s] con los caracteres sin glifo en Noto Sans reemplazados.
String textoPdf(String s) {
  var r = s;
  for (final e in _sinGlifo.entries) {
    r = r.replaceAll(e.key, e.value);
  }
  return r;
}

String _dos(int n) => n.toString().padLeft(2, '0');

String fechaHoraTexto(DateTime d) =>
    '${_dos(d.day)}/${_dos(d.month)}/${d.year} ${_dos(d.hour)}:${_dos(d.minute)}';

String horaTexto(DateTime d) => '${_dos(d.hour)}:${_dos(d.minute)}:${_dos(d.second)}';

/// "reporte_espectro_wifi_20261125_224500.pdf"
String nombreArchivoReporte(DateTime d) =>
    'reporte_espectro_wifi_${d.year}${_dos(d.month)}${_dos(d.day)}_'
    '${_dos(d.hour)}${_dos(d.minute)}${_dos(d.second)}.pdf';

String _mhz(num v) => v == v.roundToDouble()
    ? v.toInt().toString()
    : v.toString().replaceAll('.', ',');

// --- Filas de las tablas (públicas para las pruebas) ----------------------------

const encabezadoRedes = [
  'SSID',
  'BSSID',
  'Banda',
  'Canal',
  'Ancho',
  'Centro (MHz)',
  'Rango ocupado (MHz)',
  'Estándar',
  'RSSI / nivel',
  'Visto',
  'Origen',
];

String _ssid(PuntoAcceso ap) {
  if (!ap.escaneado) return ap.nombre;
  final s = [for (final x in ap.ssids) x.trim().isEmpty ? '(oculto)' : x];
  return s.isEmpty ? ap.nombre : s.join(', ');
}

String _estandar(PuntoAcceso ap) {
  final rep = ap.estandarReportado;
  if (!ap.escaneado || rep == null) return ap.estandar.nombre;
  return ap.estandarAprox ? '$rep (aprox.)' : rep;
}

/// Una fila por AP que transmite, banda por banda.
List<List<String>> filasTablaRedes(DatosReporte d) => [
      for (final b in d.bandas)
        for (final ap in b.transmitiendo)
          () {
            final c = ap.canalOcupado;
            final nivel = b.analisis.porAp[ap.id]?.nivelDbm;
            final otros = ap.bssids.length - 1;
            return [
              _ssid(ap),
              '${ap.bssid ?? '—'}${otros > 0 ? ' (+$otros)' : ''}',
              b.banda.nombre,
              '${ap.canalPrimario}',
              '${ap.anchoMHz} MHz',
              _mhz(c.centroMHz),
              '${_mhz(c.inicioMHz)}–${_mhz(c.finMHz)}',
              _estandar(ap),
              ap.rssiDbm != null
                  ? 'RSSI ${textoDbm(ap.rssiDbm!)}'
                  : nivel == null
                      ? '—'
                      : 'Nivel ${textoDbm(nivel)} (calc.)',
              ap.vistaEn == null ? '—' : horaTexto(ap.vistaEn!),
              ap.escaneado ? 'Real' : 'Simulado',
            ];
          }(),
    ];

String _tipo(TipoRelacion t) => switch (t) {
      TipoRelacion.independientes => 'Independientes',
      TipoRelacion.seTurnan => 'Se turnan',
      TipoRelacion.asimetrica => 'Asimétrica',
      TipoRelacion.simultanea => 'Simultánea',
    };

/// Nombre del par como en la tarjeta de la app: en la asimétrica la flecha va
/// del que transmite encima al que cede.
String _nombrePar(RelacionPar p) => switch (p.tipo) {
      TipoRelacion.asimetrica => p.aOyeB!.oye
          ? '${p.b.nombre} → ${p.a.nombre}'
          : '${p.a.nombre} → ${p.b.nombre}',
      _ => '${p.a.nombre} y ${p.b.nombre}',
    };

String _sir(PuntoAcceso ap, double? sir) => sir == null
    ? '—'
    : '${ap.nombre}: ${textoDb(sir)} (${gravedadDe(sir).nombre.toLowerCase()})';

const encabezadoPares = [
  'Banda',
  'Par',
  'Tipo',
  'Geometría',
  'Comparten (MHz)',
  'SIR de A',
  'SIR de B',
  'Gravedad',
];

List<List<String>> filasPares(BandaReporte b) => [
      for (final p in b.analisis.conSolape)
        [
          b.banda.nombre,
          _nombrePar(p),
          _tipo(p.tipo),
          p.geometria.nombre,
          textoMhz(p.solapeMHz),
          _sir(p.a, p.sirADb),
          _sir(p.b, p.sirBDb),
          p.peorGravedad?.nombre ?? '—',
        ],
    ];

// --- Documento ----------------------------------------------------------------------

/// Genera el PDF. [fuentes] por defecto se cargan de los assets.
Future<Uint8List> generarReportePdf(DatosReporte d, {FuentesReporte? fuentes}) async {
  final f = fuentes ?? await FuentesReporte.cargar();
  final e = _Estilos(f);
  final doc = pw.Document(
    title: 'Reporte de análisis del espectro Wi-Fi',
    creator: 'Espectro Wi-Fi',
  );
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.letter,
      margin: const pw.EdgeInsets.fromLTRB(40, 36, 40, 32),
      theme: pw.ThemeData.withFont(base: f.normal, bold: f.negrita)
          .copyWith(defaultTextStyle: e.base),
      footer: (ctx) => pw.Container(
        alignment: pw.Alignment.centerRight,
        margin: const pw.EdgeInsets.only(top: 8),
        child: pw.Text(
          textoPdf('Espectro Wi-Fi · página ${ctx.pageNumber} de ${ctx.pagesCount}'),
          style: e.chico,
        ),
      ),
      build: (ctx) => [
        ..._encabezado(d, e),
        ..._resumen(d, e),
        ..._figuras(d, e),
        ..._tablaRedes(d, e),
        ..._ocupacion(d, e),
        ..._pares(d, e),
        ..._recomendaciones(d, e),
        ..._umbrales(e),
        ..._normativa(e),
        ..._anexoPares(d, e),
      ],
    ),
  );
  return doc.save();
}

class _Estilos {
  _Estilos(FuentesReporte f)
      : base = pw.TextStyle(
          font: f.normal,
          fontNormal: f.normal,
          fontBold: f.negrita,
          fontItalic: f.normal,
          fontBoldItalic: f.negrita,
          fontSize: 9,
          lineSpacing: 1.5,
        );

  final pw.TextStyle base;
  pw.TextStyle get negrita => base.copyWith(fontWeight: pw.FontWeight.bold);
  pw.TextStyle get chico => base.copyWith(fontSize: 7.5, color: PdfColors.grey800);
  pw.TextStyle get celda => base.copyWith(fontSize: 6.5, lineSpacing: 0.5);
  pw.TextStyle get celdaNegrita => celda.copyWith(fontWeight: pw.FontWeight.bold);
  pw.TextStyle get titulo => base.copyWith(
        fontSize: 12.5,
        fontWeight: pw.FontWeight.bold,
        color: PdfColors.blue900,
      );
}

pw.Widget _p(String s, pw.TextStyle st, {double abajo = 4}) => pw.Padding(
      padding: pw.EdgeInsets.only(bottom: abajo),
      child: pw.Text(textoPdf(s), style: st),
    );

pw.Widget _seccion(String s, _Estilos e) => pw.Padding(
      padding: const pw.EdgeInsets.only(top: 12, bottom: 5),
      child: pw.Text(textoPdf(s), style: e.titulo),
    );

pw.Widget _vineta(String s, pw.TextStyle st) => pw.Padding(
      padding: const pw.EdgeInsets.only(left: 8, bottom: 2),
      child: pw.Text(textoPdf('• $s'), style: st),
    );

pw.Widget _tabla(
  _Estilos e,
  List<String> encabezado,
  List<List<String>> filas, {
  Map<int, pw.TableColumnWidth>? anchos,
}) =>
    pw.TableHelper.fromTextArray(
      headers: [for (final h in encabezado) textoPdf(h)],
      data: [
        for (final f in filas) [for (final c in f) textoPdf(c)],
      ],
      headerStyle: e.celdaNegrita,
      cellStyle: e.celda,
      headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
      headerAlignment: pw.Alignment.centerLeft,
      cellAlignment: pw.Alignment.centerLeft,
      cellPadding: const pw.EdgeInsets.symmetric(horizontal: 2, vertical: 2),
      headerPadding: const pw.EdgeInsets.symmetric(horizontal: 2, vertical: 2),
      border: pw.TableBorder.all(color: PdfColors.grey500, width: 0.4),
      columnWidths: anchos,
    );

// --- Secciones ------------------------------------------------------------------------

List<pw.Widget> _encabezado(DatosReporte d, _Estilos e) {
  String fila(String k, String v) => '$k: $v';
  final esc = d.horaEscaneo;
  var escaneo = esc == null ? 'sin escaneo (solo APs simulados)' : horaTexto(esc);
  final vistas = d.horaResultados;
  if (esc != null && vistas != null && esc.difference(vistas).inSeconds.abs() > 2) {
    escaneo += ' (Android vio las redes más recientes a las ${horaTexto(vistas)})';
  }
  final soloReales = d.bandas
      .map((b) => '${b.banda.nombre}: ${b.soloReales ? 'activo' : 'no'}')
      .join(' · ');
  return [
    pw.Text(
      textoPdf('Reporte de análisis del espectro Wi-Fi'),
      style: e.base.copyWith(fontSize: 17, fontWeight: pw.FontWeight.bold),
    ),
    pw.SizedBox(height: 6),
    _p(fila('Fecha y hora', fechaHoraTexto(d.fecha)), e.base, abajo: 1),
    _p(fila('Lugar', d.lugar.trim().isEmpty ? 'no indicado' : d.lugar.trim()), e.base,
        abajo: 1),
    _p(fila('Celular', d.modeloCelular ?? 'no disponible'), e.base, abajo: 1),
    _p(fila('Último escaneo', escaneo), e.base, abajo: 1),
    _p(fila('"Solo redes reales"', soloReales), e.base, abajo: 1),
    if (d.observaciones.trim().isNotEmpty)
      _p(fila('Observaciones', d.observaciones.trim()), e.base, abajo: 1),
    pw.SizedBox(height: 4),
    _p(
      'Los APs reales salen del escaneo de Android (RSSI medido). Los simulados los '
      'define el usuario y su nivel se calcula (PIRE − FSPL). El solapamiento y la '
      'interferencia son una simulación con el modelo de la app: Android no entrega '
      'la ocupación del canal en el tiempo.',
      e.chico,
    ),
  ];
}

List<pw.Widget> _resumen(DatosReporte d, _Estilos e) {
  String masOcupado(BandaReporte b) {
    final c = b.canalesMasOcupados;
    if (c.isEmpty) return '—';
    final n = b.ocupacion20[c.first]!;
    return '${c.join(', ')} ($n AP${n == 1 ? '' : 's'}${c.length > 1 ? ' cada uno' : ''})';
  }

  return [
    _seccion('Resumen', e),
    _tabla(
      e,
      const [
        'Banda',
        'En la lista (reales / simulados)',
        'Transmiten (reales / simulados)',
        'Canal de 20 MHz más ocupado',
        'Pares graves',
        'Moderados',
        'Leves',
        'Se turnan',
      ],
      [
        for (final b in d.bandas)
          [
            b.banda.nombre,
            '${b.aps.length} (${b.reales} / ${b.simulados})',
            '${b.transmitiendo.length} (${b.realesTx} / ${b.simuladosTx})',
            masOcupado(b),
            '${b.paresCon(Gravedad.grave)}',
            '${b.paresCon(Gravedad.moderada)}',
            '${b.paresCon(Gravedad.leve)}',
            '${b.paresSeTurnan}',
          ],
      ],
    ),
    pw.SizedBox(height: 3),
    _p(
      'Gravedad de un par: la peor de sus dos direcciones (SIR de cada AP con el otro '
      'como único interferente). Los pares que se turnan comparten el tiempo de aire '
      'pero no se pisan, así que no tienen gravedad.',
      e.chico,
    ),
    _p(
      'La SIR se calcula en el punto donde está el celular. Una SIR negativa de una '
      'red vecina débil significa que desde este punto no sería utilizable; no '
      'describe cómo funciona esa red para sus propios usuarios.',
      e.chico,
    ),
  ];
}

/// Color del AP en el dibujo (el mismo de PintorEspectro).
PdfColor _colorAp(PuntoAcceso ap) =>
    PdfColor.fromInt(ColoresEspectro.deCanal(ap.colorIndice).toARGB32());

/// Leyenda bajo la figura: cuadrito del color del AP, nombre, canal y ancho,
/// en 3 columnas. El dibujo omite etiquetas que se enciman; aquí están todos.
pw.Widget _leyenda(List<PuntoAcceso> aps, _Estilos e) => pw.Wrap(
      runSpacing: 2,
      children: [
        for (final ap in aps)
          pw.SizedBox(
            width: 532 / 3,
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Container(
                  width: 7,
                  height: 7,
                  margin: const pw.EdgeInsets.only(top: 1.5, right: 4),
                  color: _colorAp(ap),
                ),
                pw.Expanded(
                  child: pw.Text(
                    textoPdf('${ap.nombre} · canal ${ap.canalPrimario} · ${ap.anchoMHz} MHz'),
                    style: e.chico,
                  ),
                ),
              ],
            ),
          ),
      ],
    );

List<pw.Widget> _figuras(DatosReporte d, _Estilos e) {
  final w = <pw.Widget>[_seccion('Espectro con los APs', e)];
  var n = 0;
  for (final b in d.bandas) {
    final png = b.figuraPng;
    if (png == null) {
      w.add(_p('Figura de ${b.banda.nombre} no disponible.', e.chico));
      continue;
    }
    n++;
    // Figura, pie y leyenda en un Container: MultiPage no lo parte, así que
    // van juntos en la misma página.
    w.add(pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 10),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Image(pw.MemoryImage(png), width: 532, fit: pw.BoxFit.contain),
          pw.SizedBox(height: 3),
          _p(
            'Figura $n. Espectro de ${b.banda.nombre} con los ${b.transmitiendo.length} '
            'APs que transmiten, dibujados con su forma espectral (sinc² en DSSS, trapecio '
            'en OFDM). La línea vertical gruesa marca el canal primario; el fondo, las '
            'bandas de uso libre en Colombia (Res. ANE 105/2020).',
            e.chico,
          ),
          if (b.transmitiendo.isNotEmpty) _leyenda(b.transmitiendo, e),
        ],
      ),
    ));
  }
  return w;
}

List<pw.Widget> _tablaRedes(DatosReporte d, _Estilos e) {
  final apagados = d.bandas.fold(0, (s, b) => s + b.noTransmiten);
  return [
    _seccion('Redes que transmiten', e),
    _tabla(
      e,
      encabezadoRedes,
      filasTablaRedes(d),
      anchos: const {
        0: pw.FlexColumnWidth(2.2),
        1: pw.FlexColumnWidth(2.5),
        2: pw.FlexColumnWidth(1.1),
        3: pw.FlexColumnWidth(0.8),
        4: pw.FlexColumnWidth(1.1),
        5: pw.FlexColumnWidth(1.1),
        6: pw.FlexColumnWidth(1.6),
        7: pw.FlexColumnWidth(1.5),
        8: pw.FlexColumnWidth(1.8),
        9: pw.FlexColumnWidth(1.2),
        10: pw.FlexColumnWidth(1.1),
      },
    ),
    pw.SizedBox(height: 3),
    _p(
      '${apagados == 0 ? 'Todos los APs de la lista transmiten.' : '$apagados '
          '${apagados == 1 ? 'AP de la lista no transmite' : 'APs de la lista no transmiten'} '
          '(apagados, en un canal desactivado o por "Solo redes reales") y no '
          '${apagados == 1 ? 'aparece' : 'aparecen'} en la tabla ni en el análisis.'} '
          'Centro y rango son los del bloque completo. RSSI: medido por Android; nivel '
          '(calc.): PIRE − FSPL a la distancia del AP simulado. "Visto": hora en que '
          'Android vio la red.',
      e.chico,
    ),
  ];
}

List<pw.Widget> _ocupacion(DatosReporte d, _Estilos e) {
  final w = <pw.Widget>[_seccion('Ocupación por canal de 20 MHz', e)];
  final borde = pw.TableBorder.all(color: PdfColors.grey500, width: 0.4);
  pw.Widget celda(String s, pw.TextStyle st, {PdfColor? fondo}) => pw.Container(
        alignment: pw.Alignment.center,
        color: fondo,
        padding: const pw.EdgeInsets.symmetric(vertical: 2),
        child: pw.Text(s, style: st),
      );
  for (final b in d.bandas) {
    final m = b.ocupacion20.entries.toList();
    w.add(_p(b.banda.nombre, e.negrita, abajo: 2));
    for (var i = 0; i < m.length; i += 13) {
      final tramo = m.sublist(i, i + 13 > m.length ? m.length : i + 13);
      // Celdas vacías para que el último tramo tenga el mismo ancho de columna.
      final relleno = 13 - tramo.length;
      w.add(pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 4),
        // Ancho fijo: 40 pt para "Canal/APs" y 26 pt por canal, sin estirar.
        child: pw.Table(
          border: borde,
          tableWidth: pw.TableWidth.min,
          columnWidths: {
            0: const pw.FixedColumnWidth(40),
            for (var k = 1; k <= 13; k++) k: const pw.FixedColumnWidth(26),
          },
          children: [
            pw.TableRow(children: [
              celda('Canal', e.celdaNegrita, fondo: PdfColors.grey300),
              for (final c in tramo) celda('${c.key}', e.celdaNegrita, fondo: PdfColors.grey300),
              for (var k = 0; k < relleno; k++) celda('', e.celda),
            ]),
            pw.TableRow(children: [
              celda('APs', e.celdaNegrita),
              for (final c in tramo)
                celda('${c.value}', c.value > 1 ? e.celdaNegrita : e.celda,
                    fondo: c.value > 1 ? PdfColors.amber100 : null),
              for (var k = 0; k < relleno; k++) celda('', e.celda),
            ]),
          ],
        ),
      ));
    }
  }
  w.add(_p(
    'Un AP cuenta en cada canal de 20 MHz de su bloque (primario y secundarios). En '
    '2.4 GHz los canales vecinos también se solapan en parte: el número no muestra '
    'ese solape, que sí entra en la tabla de pares.',
    e.chico,
  ));
  return w;
}

List<pw.Widget> _pares(DatosReporte d, _Estilos e) {
  final w = <pw.Widget>[
    _seccion('Pares con solape', e),
    _p(supuestoPuntoObservacion, e.chico),
  ];
  for (final b in d.bandas) {
    final sinSolape = b.analisis.pares.length - b.analisis.conSolape.length;
    w.add(_p(b.banda.nombre, e.negrita, abajo: 2));
    if (b.transmitiendo.length < 2) {
      w.add(_p('Hay menos de dos APs transmitiendo: no hay pares que analizar.', e.base));
      continue;
    }
    if (b.analisis.conSolape.isEmpty) {
      w.add(_p('Ningún par se solapa: no hay interferencia '
          '($sinSolape ${sinSolape == 1 ? 'par independiente' : 'pares independientes'}).', e.base));
      continue;
    }
    w.add(_tabla(
      e,
      encabezadoPares,
      filasPares(b),
      anchos: const {
        0: pw.FlexColumnWidth(0.9),
        1: pw.FlexColumnWidth(2),
        2: pw.FlexColumnWidth(1.1),
        3: pw.FlexColumnWidth(1.5),
        4: pw.FlexColumnWidth(1),
        5: pw.FlexColumnWidth(2),
        6: pw.FlexColumnWidth(2),
        7: pw.FlexColumnWidth(0.9),
      },
    ));
    if (sinSolape > 0) {
      w.add(_p('Además, $sinSolape ${sinSolape == 1 ? 'par no se solapa' : 'pares no se solapan'} '
          '(independientes).', e.chico));
    }
    w.add(pw.SizedBox(height: 4));
  }
  final hayAnexo = d.bandas.any((b) => b.analisis.conSolape.isNotEmpty);
  if (hayAnexo) {
    w.add(_p('La explicación de cada par está en el Anexo A.', e.chico));
  }
  return w;
}

/// Anexo A: la explicación de cada par, como en la tarjeta de la app.
List<pw.Widget> _anexoPares(DatosReporte d, _Estilos e) {
  if (!d.bandas.any((b) => b.analisis.conSolape.isNotEmpty)) return const [];
  final w = <pw.Widget>[_seccion('Anexo A. Detalle de cada par', e)];
  w.add(_p('Tipos de relación', e.negrita, abajo: 1));
  for (final t in [TipoRelacion.seTurnan, TipoRelacion.asimetrica, TipoRelacion.simultanea]) {
    w.add(_vineta('${_tipo(t)}: ${t.descripcion}', e.chico));
  }
  for (final b in d.bandas) {
    if (b.analisis.conSolape.isEmpty) continue;
    w.add(pw.SizedBox(height: 4));
    w.add(_p(b.banda.nombre, e.negrita, abajo: 2));
    for (final p in b.analisis.conSolape) {
      w.add(_p('${_nombrePar(p)} · ${_tipo(p.tipo)}', e.negrita.copyWith(fontSize: 8), abajo: 1));
      for (final l in p.explicacion()) {
        w.add(_vineta(l, e.chico));
      }
      w.add(pw.SizedBox(height: 3));
    }
  }
  return w;
}

/// Lugar para "Sugerir canal": solo aparece si hay recomendaciones.
List<pw.Widget> _recomendaciones(DatosReporte d, _Estilos e) {
  final r = d.recomendaciones;
  if (r == null || r.isEmpty) return const [];
  return [
    _seccion('Recomendaciones', e),
    for (final l in r) _vineta(l, e.base),
  ];
}

List<pw.Widget> _umbrales(_Estilos e) => [
      _seccion('Supuestos, umbrales y fuentes', e),
      for (final u in Umbrales.todos) ...[
        _p('${textoDbm(u.valorDbm)} · ${u.nombre}', e.negrita.copyWith(fontSize: 8), abajo: 0),
        _p(u.uso, e.chico, abajo: 0),
        _p('Fuente: ${u.fuente}. Estado: ${u.estado.descripcion}.', e.chico),
      ],
      _p('Gravedad', e.negrita.copyWith(fontSize: 8), abajo: 0),
      _p(CortesSir.explicacion, e.chico),
      _p('Otros supuestos', e.negrita.copyWith(fontSize: 8), abajo: 0),
      _p(supuestoPuntoObservacion, e.chico, abajo: 1),
      _p(otrosSupuestos, e.chico),
    ];

List<pw.Widget> _normativa(_Estilos e) {
  String r(Rango x) => '${_mhz(x.inicioMHz)}–${_mhz(x.finMHz)} MHz';
  final sub5 = NormaColombia.subbandas5.map((s) => '${s.nombre} ${r(s)}').join(', ');
  return [
    _seccion('Normativa (Colombia)', e),
    _vineta(
      'Res. ANE 105 de 2020, Título 4 y Anexo 1 "Frecuencias de uso libre". '
      '2.4 GHz: ${r(NormaColombia.banda24)} (ISM, canales 1 a 13).',
      e.base,
    ),
    _vineta(
      '5 GHz, numeral 3.8.1 (corregido por la Res. ANE 469 de 2020, art. 8): $sub5. '
      'Entre 5350 y 5470 MHz no hay canales de uso libre.',
      e.base,
    ),
    _vineta(
      '6 GHz, Res. ANE 737 de 2022 (${r(NormaColombia.banda6)}): el escaneo la reconoce, '
      'pero no se dibuja ni se analiza.',
      e.base,
    ),
    _vineta(
      'Numeración IEEE 802.11: en 2.4 GHz f = 2407 + 5·n MHz; en 5 GHz f = 5000 + 5·n MHz.',
      e.base,
    ),
    _vineta(
      'Pendiente: el límite de PIRE y los requisitos DFS/TPC del Anexo 1. La PIRE de '
      'los APs simulados (0 a 30 dBm) no se compara con el límite legal.',
      e.base,
    ),
  ];
}
