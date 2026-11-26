// Dibujo del espectro de una banda: norma colombiana de fondo, eje de
// frecuencia y cada canal con su forma espectral (sinc² o trapecio OFDM).
// Se dibuja solo la ventana de frecuencias visible (zoom horizontal), siempre
// a escala lineal.
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../modelo/canales.dart';
import '../modelo/forma_espectral.dart';
import '../modelo/punto_acceso.dart';
import 'escala_espectro.dart';

abstract final class ColoresEspectro {
  static const fondo = Color(0xFF0F1720);
  static const permitido = Color(0xFF17293B);
  static const franjaA = Color(0xFF22384F);
  static const franjaB = Color(0xFF1B2E42);
  static const rayado = Color(0x55FFFFFF);
  static const eje = Color(0xCCFFFFFF);
  static const texto = Color(0xDDFFFFFF);
  static const textoTenue = Color(0x88FFFFFF);
  static const sinBloque = Color(0xFF8A8F98);
  static const solape = Color(0xFFFF5252);

  /// Color de cada canal. El ángulo áureo (137,5°) separa bien los tonos de
  /// canales vecinos aunque sean muchos.
  static Color deCanal(int indice) =>
      HSVColor.fromAHSV(1, (indice * 137.5 + 200) % 360, 0.65, 0.95).toColor();
}

/// Una fila de etiquetas: guarda los tramos horizontales ya usados para que
/// ninguna etiqueta se encime con otra.
class FilaEtiquetas {
  final _ocupados = <(double, double)>[];

  /// Reserva [desde, hasta] si está libre. Devuelve false si se encima.
  bool reservar(double desde, double hasta) {
    for (final (a, b) in _ocupados) {
      if (desde < b && a < hasta) return false;
    }
    _ocupados.add((desde, hasta));
    return true;
  }
}

class PintorEspectro extends CustomPainter {
  PintorEspectro({
    required this.banda,
    required this.ventana,
    required this.canales,
    required this.resaltados,
    this.sinBloque = const [],
    this.seleccionado,
    this.aps = const [],
    this.apsSinTransmitir = const {},
    this.apSeleccionado,
    this.soloNumeros = false,
  });

  final Banda banda;

  /// Tramo de frecuencias que se ve.
  final VentanaFrecuencia ventana;
  final List<Canal> canales;

  /// Números de los canales del conjunto sin solapamiento (se ven más fuertes).
  final Set<int> resaltados;

  /// Canales de 20 MHz que no forman bloque del ancho actual (en gris).
  final List<int> sinBloque;

  /// Número del canal tocado, o null.
  final int? seleccionado;

  /// Puntos de acceso a dibujar encima de los canales (incremento 4).
  final List<PuntoAcceso> aps;

  /// Ids de los APs apagados o en un canal desactivado: solo contorno punteado.
  final Set<String> apsSinTransmitir;

  /// Id del AP seleccionado (borde blanco).
  final String? apSeleccionado;

  /// Los canales se dibujan solo como referencia: número arriba, frecuencia y
  /// marca en el eje, sin formas (vista de APs).
  final bool soloNumeros;

  static const altoFranja = 22.0;
  static const altoEtiquetas = 40.0;

  /// Separación mínima entre etiquetas vecinas, en px.
  static const _holgura = 3.0;

  /// La misma escala sirve para dibujar y para saber qué canal se tocó.
  static EscalaEspectro escalaPara(Size size, VentanaFrecuencia v) => EscalaEspectro(
        fMinMHz: v.inicioMHz,
        fMaxMHz: v.finMHz,
        xIzq: 0,
        xDer: size.width,
        yBase: size.height - altoEtiquetas,
        yTope: altoFranja + 24,
      );

  /// Canal bajo la frecuencia [fMHz]; si hay varios, el de centro más cercano.
  static Canal? canalEn(List<Canal> canales, double fMHz) {
    Canal? mejor;
    for (final c in canales) {
      if (fMHz < c.inicioMHz || fMHz > c.finMHz) continue;
      if (mejor == null ||
          (c.centroMHz - fMHz).abs() < (mejor.centroMHz - fMHz).abs()) {
        mejor = c;
      }
    }
    return mejor;
  }

  /// 3 = seleccionado, 2 = se solapa con el seleccionado, 1 = sin solapamiento,
  /// 0 = tenue. Define el orden de dibujo y la prioridad de las etiquetas.
  int _capa(Canal c, Canal? sel) {
    if (sel != null) {
      if (c.numero == sel.numero) return 3;
      return c.solapaCon(sel) ? 2 : 0;
    }
    return resaltados.contains(c.numero) ? 1 : 0;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final e = escalaPara(size, ventana);
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, Paint()..color = ColoresEspectro.fondo);

    _pintarNorma(canvas, e, size);
    _pintarFranjaSuperior(canvas, e, size);

    final sel = seleccionado == null
        ? null
        : canales.where((c) => c.numero == seleccionado).firstOrNull;
    final grises = [for (final n in sinBloque) _canal20(n)];
    final indices = List.generate(canales.length, (i) => i)
      ..sort((a, b) => _capa(canales[a], sel).compareTo(_capa(canales[b], sel)));

    if (soloNumeros) {
      // Vista de APs: los canales son solo referencia, sin formas.
      for (final c in canales) {
        if (_visible(c, e)) _marcaEje(canvas, e, c.centroMHz.toDouble(), ColoresEspectro.textoTenue);
      }
    } else {
      for (final c in grises) {
        _pintarSinBloque(canvas, e, c);
      }
      for (final i in indices) {
        _pintarCanal(canvas, e, canales[i], i, _capa(canales[i], sel), sel != null);
      }
    }
    _pintarEje(canvas, e, size);

    // Etiquetas, de la más importante a la menos: si no caben, se omiten las
    // menos importantes. Al hacer zoom hay más espacio y aparecen las demás.
    final numeros = FilaEtiquetas(),
        frecuencias = FilaEtiquetas(),
        subcanales = FilaEtiquetas();
    for (final i in indices.reversed) {
      final c = canales[i];
      final capa = _capa(c, sel);
      final fuerte = capa > 0;
      final color = ColoresEspectro.deCanal(i);
      // En la vista de APs los números van en gris, para no confundirlos con
      // los colores de los APs.
      final colorNumero = soloNumeros
          ? (capa == 3 ? ColoresEspectro.texto : ColoresEspectro.textoTenue)
          : capa == 2
              ? ColoresEspectro.solape
              : color.withValues(alpha: fuerte ? 1 : 0.6);
      _etiquetaNumero(canvas, e, size, numeros, c, colorNumero, fuerte);
      _etiquetaFrecuencia(canvas, e, size, frecuencias, c.centroMHz.toDouble(),
          fuerte ? ColoresEspectro.texto : ColoresEspectro.textoTenue);
      if (fuerte && c.subcanales.length > 1) {
        for (final s in c.subcanales) {
          _etiquetaCentrada(canvas, size, subcanales, '$s',
              Offset(e.x(frecuenciaDeCanal(banda, s).toDouble()), e.yBase - 10),
              9, ColoresEspectro.texto, false);
        }
      }
    }
    for (final c in grises) {
      _etiquetaNumero(canvas, e, size, numeros, c, ColoresEspectro.sinBloque, false);
      _etiquetaFrecuencia(canvas, e, size, frecuencias, c.centroMHz.toDouble(),
          ColoresEspectro.sinBloque);
    }
    if (aps.isNotEmpty) _pintarAps(canvas, e, size);
    canvas.restore();
  }

  // --- Puntos de acceso (incremento 4) ---------------------------------------

  /// Cada AP con su forma real: relleno si transmite, contorno punteado si
  /// está apagado o usa un canal desactivado. Una línea vertical marca el
  /// canal primario y otras, punteadas, los límites de 20 MHz del bloque.
  void _pintarAps(Canvas canvas, EscalaEspectro e, Size size) {
    // El seleccionado se dibuja al final, encima de los demás.
    final orden = [...aps]..sort((a, b) =>
        (a.id == apSeleccionado ? 1 : 0).compareTo(b.id == apSeleccionado ? 1 : 0));
    for (final ap in orden) {
      final c = ap.canalOcupado;
      if (!_visible(c, e)) continue;
      final color = ColoresEspectro.deCanal(ap.colorIndice);
      final apagado = apsSinTransmitir.contains(ap.id);
      final sel = ap.id == apSeleccionado;
      final path = _contorno(c, e, 1);
      if (apagado) {
        _trazoPunteado(canvas, path, color.withValues(alpha: 0.8));
      } else {
        canvas.drawPath(path, Paint()..color = color.withValues(alpha: sel ? 0.40 : 0.28));
        canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = sel ? 3 : 2
            ..strokeJoin = StrokeJoin.round
            ..color = sel ? Colors.white : color,
        );
      }
      for (var k = 1; k < c.subcanales.length; k++) {
        final f = c.inicioMHz + 20.0 * k;
        _lineaPunteada(canvas, Offset(e.x(f), e.y(1)), Offset(e.x(f), e.yBase),
            color.withValues(alpha: 0.6));
      }
      final xp = e.x(ap.frecuenciaPrimariaMHz.toDouble());
      canvas.drawLine(
        Offset(xp, e.y(1) + 18),
        Offset(xp, e.yBase),
        Paint()
          ..color = color.withValues(alpha: apagado ? 0.5 : 0.95)
          ..strokeWidth = 2,
      );
    }

    _etiquetasAps(canvas, e, orden.reversed.toList());
  }

  /// Etiquetas de los APs, con la misma lógica que las de los canales: por
  /// prioridad (el seleccionado primero, luego en orden de la lista), cada
  /// una en la primera fila libre bajo la parte alta de las formas y, si no
  /// cabe en ninguna, se omite (con zoom aparece).
  ///  - La separación entre filas sale del alto real del texto, así dos
  ///    filas nunca se pisan (con un paso fijo se enciman en el navegador).
  ///  - Solo se escribe si cabe dentro del ancho de su forma; si no, se prueba
  ///    el nombre solo.
  ///  - Lleva un fondo, para que la línea del primario no la tache.
  void _etiquetasAps(Canvas canvas, EscalaEspectro e, List<PuntoAcceso> porPrioridad) {
    const maxFilas = 4, pad = 2.0;
    final filas = List.generate(maxFilas, (_) => FilaEtiquetas());
    for (final ap in porPrioridad) {
      final c = ap.canalOcupado;
      if (!_visible(c, e)) continue;
      final apagado = apsSinTransmitir.contains(ap.id);
      final sel = ap.id == apSeleccionado;
      final color = apagado ? ColoresEspectro.textoTenue : ColoresEspectro.texto;
      // En DSSS la parte alta es más angosta que en el trapecio OFDM.
      final util = (e.x(c.finMHz) - e.x(c.inicioMHz)) * (ap.paso.dsss ? 0.45 : 0.7);
      final cx = e.x(c.centroMHz.toDouble());
      var puesto = false;
      for (final texto in ['${ap.nombre} · ${ap.canalPrimario}', ap.nombre]) {
        final tp = _medir(texto, 10, color, true);
        if (tp.width + 2 * pad > util) continue;
        final paso = tp.height + 2 * pad + 2;
        for (var k = 0; k < maxFilas && !puesto; k++) {
          final y = e.y(1) + 4 + k * paso;
          if (y + tp.height + 2 * pad > e.yBase - 4) break;
          final x0 = cx - tp.width / 2 - pad;
          if (!filas[k].reservar(x0 - 1, x0 + tp.width + 2 * pad + 1)) continue;
          final caja = Rect.fromLTWH(x0, y, tp.width + 2 * pad, tp.height + 2 * pad);
          canvas.drawRRect(
            RRect.fromRectAndRadius(caja, const Radius.circular(3)),
            Paint()..color = ColoresEspectro.fondo.withValues(alpha: 0.75),
          );
          if (sel) {
            canvas.drawRRect(
              RRect.fromRectAndRadius(caja, const Radius.circular(3)),
              Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = 1
                ..color = ColoresEspectro.deCanal(ap.colorIndice),
            );
          }
          tp.paint(canvas, Offset(x0 + pad, y + pad));
          puesto = true;
        }
        if (puesto) break;
      }
    }
  }

  /// AP bajo la frecuencia [fMHz]; si hay varios, el de centro más cercano.
  static PuntoAcceso? apEn(List<PuntoAcceso> aps, double fMHz) {
    PuntoAcceso? mejor;
    for (final ap in aps) {
      final c = ap.canalOcupado;
      if (fMHz < c.inicioMHz || fMHz > c.finMHz) continue;
      if (mejor == null ||
          (c.centroMHz - fMHz).abs() < (mejor.canalOcupado.centroMHz - fMHz).abs()) {
        mejor = ap;
      }
    }
    return mejor;
  }

  Canal _canal20(int n) => Canal(
        banda: banda,
        numero: n,
        centroMHz: frecuenciaDeCanal(banda, n),
        anchoMHz: 20,
        subcanales: [n],
      );

  // --- Fondo: lo que permite la norma colombiana -------------------------

  void _pintarNorma(Canvas canvas, EscalaEspectro e, Size size) {
    final tramos = NormaColombia.tramosDe(banda);
    for (final r in tramos) {
      canvas.drawRect(
        Rect.fromLTRB(e.x(r.inicioMHz), altoFranja, e.x(r.finMHz), e.yBase),
        Paint()..color = ColoresEspectro.permitido,
      );
    }
    // Huecos entre tramos (en 5 GHz: 5350-5470 MHz), rayados.
    for (var i = 0; i + 1 < tramos.length; i++) {
      final a = tramos[i].finMHz, b = tramos[i + 1].inicioMHz;
      final rect = Rect.fromLTRB(e.x(a), altoFranja, e.x(b), e.yBase);
      _rayar(canvas, rect, size);
      _textoQueQuepa(
        canvas,
        size,
        rect,
        [
          'No permitido en Colombia\n${_mhz(a)}–${_mhz(b)} MHz',
          'No permitido\n${_mhz(a)}–${_mhz(b)}',
          'No\npermitido',
        ],
        11,
        conFondo: true,
      );
    }
    // Bordes de la norma: línea punteada.
    final bordes = {for (final r in tramos) ...[r.inicioMHz, r.finMHz]};
    for (final f in bordes) {
      _lineaPunteada(canvas, Offset(e.x(f), altoFranja), Offset(e.x(f), e.yBase),
          ColoresEspectro.textoTenue);
    }
  }

  void _pintarFranjaSuperior(Canvas canvas, EscalaEspectro e, Size size) {
    final franjas =
        banda == Banda.ghz5 ? NormaColombia.subbandas5 : NormaColombia.tramosDe(banda);
    for (var i = 0; i < franjas.length; i++) {
      final r = franjas[i];
      final rect = Rect.fromLTRB(e.x(r.inicioMHz), 0, e.x(r.finMHz), altoFranja);
      canvas.drawRect(
        rect.deflate(0.5),
        Paint()..color = i.isEven ? ColoresEspectro.franjaA : ColoresEspectro.franjaB,
      );
      _textoQueQuepa(
        canvas,
        size,
        rect,
        [
          '${r.nombre} · ${_mhz(r.inicioMHz)}–${_mhz(r.finMHz)} MHz',
          r.nombre,
          r.nombre.replaceAll('U-NII-', ''),
        ],
        10,
      );
    }
  }

  // --- Canales ------------------------------------------------------------

  void _pintarSinBloque(Canvas canvas, EscalaEspectro e, Canal c) {
    if (!_visible(c, e)) return;
    final path = _contorno(c, e, 0.55);
    canvas.drawPath(path, Paint()..color = ColoresEspectro.sinBloque.withValues(alpha: 0.12));
    _trazoPunteado(canvas, path, ColoresEspectro.sinBloque);
    _marcaEje(canvas, e, c.centroMHz.toDouble(), ColoresEspectro.sinBloque);
  }

  void _pintarCanal(Canvas canvas, EscalaEspectro e, Canal c, int indice, int capa,
      bool haySeleccion) {
    if (!_visible(c, e)) return;
    final color = ColoresEspectro.deCanal(indice);
    final path = _contorno(c, e, 1);
    final double relleno, borde, grosor;
    Color colorBorde = color, colorRelleno = color;

    switch (capa) {
      case 3: // seleccionado
        relleno = 0.45;
        borde = 1;
        grosor = 3;
        colorBorde = Colors.white;
      case 2: // se solapa con el seleccionado
        relleno = 0.30;
        borde = 0.95;
        grosor = 1.5;
        colorBorde = colorRelleno = ColoresEspectro.solape;
      case 1: // conjunto sin solapamiento
        relleno = 0.30;
        borde = 1;
        grosor = 2;
      default: // tenue
        relleno = haySeleccion ? 0.04 : 0.08;
        borde = haySeleccion ? 0.25 : 0.45;
        grosor = 1;
    }

    canvas.drawPath(path, Paint()..color = colorRelleno.withValues(alpha: relleno));
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = grosor
        ..strokeJoin = StrokeJoin.round
        ..color = colorBorde.withValues(alpha: borde),
    );

    // Divisiones de 20 MHz dentro de los bloques de 40/80/160 MHz.
    final fuerte = capa > 0;
    final colorDiv = (fuerte ? ColoresEspectro.texto : ColoresEspectro.textoTenue)
        .withValues(alpha: 0.5);
    for (var k = 1; k < c.subcanales.length; k++) {
      final f = c.inicioMHz + 20.0 * k;
      _lineaPunteada(canvas, Offset(e.x(f), e.y(1)), Offset(e.x(f), e.yBase), colorDiv);
    }
    _marcaEje(canvas, e, c.centroMHz.toDouble(),
        fuerte ? ColoresEspectro.texto : ColoresEspectro.textoTenue);
  }

  bool _visible(Canal c, EscalaEspectro e) =>
      c.finMHz > e.fMinMHz && c.inicioMHz < e.fMaxMHz;

  Path _contorno(Canal c, EscalaEspectro e, double altura) {
    final puntos = perfilCanal(c);
    final path = Path()..moveTo(e.x(puntos.first.$1), e.yBase);
    for (final (f, a) in puntos) {
      path.lineTo(e.x(f), e.y(a * altura));
    }
    path.lineTo(e.x(puntos.last.$1), e.yBase);
    return path..close();
  }

  // --- Eje de frecuencia -----------------------------------------------------

  void _pintarEje(Canvas canvas, EscalaEspectro e, Size size) {
    canvas.drawLine(Offset(0, e.yBase), Offset(size.width, e.yBase),
        Paint()
          ..color = ColoresEspectro.eje
          ..strokeWidth = 1);
    // Marcas menores: el paso más fino que deje al menos 6 px entre marcas.
    final paso = [1, 2, 5, 10, 20, 50, 100]
        .firstWhere((p) => p * e.pxPorMHz >= 6, orElse: () => 100);
    final p = Paint()
      ..color = ColoresEspectro.textoTenue
      ..strokeWidth = 1;
    for (var f = (e.fMinMHz / paso).ceil() * paso; f <= e.fMaxMHz; f += paso) {
      canvas.drawLine(Offset(e.x(f.toDouble()), e.yBase),
          Offset(e.x(f.toDouble()), e.yBase + 3), p);
    }
  }

  void _marcaEje(Canvas canvas, EscalaEspectro e, double f, Color color) {
    final x = e.x(f);
    canvas.drawLine(Offset(x, e.yBase), Offset(x, e.yBase + 5),
        Paint()
          ..color = color
          ..strokeWidth = 1);
  }

  // --- Etiquetas ------------------------------------------------------------

  void _etiquetaNumero(Canvas canvas, EscalaEspectro e, Size size, FilaEtiquetas fila,
      Canal c, Color color, bool negrita) {
    _etiquetaCentrada(canvas, size, fila, '${c.numero}',
        Offset(e.x(c.centroMHz.toDouble()), e.yTope - 12), 12, color, negrita);
  }

  void _etiquetaCentrada(Canvas canvas, Size size, FilaEtiquetas fila, String s,
      Offset centro, double tamano, Color color, bool negrita) {
    if (centro.dx < 0 || centro.dx > size.width) return;
    final tp = _medir(s, tamano, color, negrita);
    final a = centro.dx - tp.width / 2 - _holgura, b = centro.dx + tp.width / 2 + _holgura;
    if (!fila.reservar(a, b)) return;
    tp.paint(canvas, centro - Offset(tp.width / 2, tp.height / 2));
  }

  /// Frecuencia central bajo el eje, en vertical. Ocupa a lo ancho lo que mide
  /// de alto la letra, así caben muchas más que en horizontal.
  void _etiquetaFrecuencia(Canvas canvas, EscalaEspectro e, Size size, FilaEtiquetas fila,
      double f, Color color) {
    final x = e.x(f);
    if (x < 0 || x > size.width) return;
    final tp = _medir('${f.round()}', 9, color, false);
    if (!fila.reservar(x - tp.height / 2 - 1, x + tp.height / 2 + 1)) return;
    canvas.save();
    canvas.translate(x, e.yBase + 7);
    canvas.rotate(-math.pi / 2);
    // Tras rotar, el texto termina en el punto de anclaje (pegado al eje).
    tp.paint(canvas, Offset(-tp.width, -tp.height / 2));
    canvas.restore();
  }

  /// Escribe la primera opción de texto que quepa en la parte visible de
  /// [rect]. Si ninguna cabe, no escribe nada.
  void _textoQueQuepa(Canvas canvas, Size size, Rect rect, List<String> opciones,
      double tamano, {bool conFondo = false}) {
    final visible = rect.intersect(Offset.zero & size);
    if (visible.width <= 0) return;
    for (final s in opciones) {
      final tp = _medir(s, tamano, ColoresEspectro.texto, false);
      final margen = conFondo ? 12 : 6;
      if (tp.width + margen > visible.width) continue;
      final origen = visible.center - Offset(tp.width / 2, tp.height / 2);
      if (conFondo) {
        canvas.drawRRect(
          RRect.fromRectAndRadius((origen & tp.size).inflate(4), const Radius.circular(4)),
          Paint()..color = ColoresEspectro.fondo.withValues(alpha: 0.85),
        );
      }
      tp.paint(canvas, origen);
      return;
    }
  }

  // --- Utilidades de dibujo ---------------------------------------------------

  TextPainter _medir(String s, double tamano, Color color, bool negrita) =>
      TextPainter(
        text: TextSpan(
          text: s,
          style: TextStyle(
            fontSize: tamano,
            color: color,
            fontWeight: negrita ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      )..layout();

  void _rayar(Canvas canvas, Rect rect, Size size) {
    final r = rect.intersect(Offset.zero & size);
    if (r.width <= 0) return;
    canvas.save();
    canvas.clipRect(r);
    final p = Paint()
      ..color = ColoresEspectro.rayado
      ..strokeWidth = 1;
    // Las rayas se anclan al rect completo para que no "bailen" al desplazar.
    final h = rect.height;
    final primera = rect.left + ((r.left - h - rect.left) / 9).floor() * 9;
    for (var x = primera; x < r.right; x += 9) {
      canvas.drawLine(Offset(x, rect.bottom), Offset(x + h, rect.top), p);
    }
    canvas.restore();
  }

  void _lineaPunteada(Canvas canvas, Offset a, Offset b, Color color) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 1;
    final largo = (b - a).distance;
    if (largo == 0) return;
    final dir = (b - a) / largo;
    for (var d = 0.0; d < largo; d += 7) {
      canvas.drawLine(a + dir * d, a + dir * math.min(d + 4, largo), p);
    }
  }

  void _trazoPunteado(Canvas canvas, Path path, Color color) {
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = color;
    for (final m in path.computeMetrics()) {
      for (var d = 0.0; d < m.length; d += 7) {
        canvas.drawPath(m.extractPath(d, math.min(d + 4, m.length)), p);
      }
    }
  }

  static String _mhz(double v) => v == v.roundToDouble()
      ? v.toInt().toString()
      : v.toString().replaceAll('.', ',');

  @override
  bool shouldRepaint(PintorEspectro old) =>
      old.banda != banda ||
      old.ventana != ventana ||
      old.canales != canales ||
      old.seleccionado != seleccionado ||
      old.sinBloque != sinBloque ||
      old.aps != aps ||
      old.apsSinTransmitir != apsSinTransmitir ||
      old.apSeleccionado != apSeleccionado ||
      old.soloNumeros != soloNumeros ||
      old.resaltados.length != resaltados.length ||
      !old.resaltados.containsAll(resaltados);
}
