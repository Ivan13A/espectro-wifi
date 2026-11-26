// Dibujo de la simulación animada: espectro en vivo y cascada (frecuencia ×
// tiempo). Los dos comparten la escala de frecuencia (misma ventana y mismo
// ancho), así que lo que ocupa un emisor arriba cae justo sobre sus ráfagas abajo.
//
// Todo lo que se dibuja aquí es SIMULADO; las dos vistas lo dicen con una
// insignia.
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../modelo/simulacion.dart';
import '../modelo/trafico.dart';
import 'escala_espectro.dart';
import 'pintor_espectro.dart';

const _ambar = Color(0xFFFFC107);

/// Insignia "SIMULACIÓN" en la esquina superior derecha de [zona]. Devuelve
/// la caja que ocupa.
Rect _insignia(Canvas canvas, Rect zona, String texto) {
  final tp = TextPainter(
    text: TextSpan(
      text: texto,
      style: const TextStyle(
        fontSize: 8,
        fontWeight: FontWeight.bold,
        color: Color(0xFF1B1B1B),
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  final caja = Rect.fromLTWH(zona.right - tp.width - 10, zona.top + 2, tp.width + 8, tp.height + 3);
  canvas.drawRRect(
    RRect.fromRectAndRadius(caja, const Radius.circular(4)),
    Paint()..color = _ambar,
  );
  tp.paint(canvas, caja.topLeft + const Offset(4, 1.5));
  return caja;
}

TextPainter _texto(String s, double tamano, Color color, {bool negrita = false}) =>
    TextPainter(
      text: TextSpan(
        text: s,
        style: TextStyle(
          fontSize: tamano,
          color: color,
          fontWeight: negrita ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

String _ms(double v) => v == v.roundToDouble()
    ? v.toInt().toString()
    : v.toStringAsFixed(1).replaceAll('.', ',');

// --- Espectro en vivo -------------------------------------------------------

class PintorEspectroEnVivo extends CustomPainter {
  PintorEspectroEnVivo({
    required this.sim,
    required this.ventana,
    required Listenable repaint,
  }) : super(repaint: repaint);

  final SimulacionEspectro sim;
  final VentanaFrecuencia ventana;

  /// Bajo el eje solo van las marcas (3–5 px): el espectro estático reserva
  /// [PintorEspectro.altoEtiquetas] para las frecuencias, pero aquí no hay
  /// etiquetas de canal, así que el dibujo termina en el eje.
  static const margenBajoEje = 6.0;

  @override
  void paint(Canvas canvas, Size size) {
    // Se pinta en un lienzo "virtual" más alto y se recorta al real, así el
    // eje queda a [margenBajoEje] del borde de abajo sin tocar la escala del
    // espectro estático.
    final virtual = Size(
      size.width,
      size.height + PintorEspectro.altoEtiquetas - margenBajoEje,
    );
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    // Fondo, norma, franjas y eje: el mismo del espectro estático, sin canales.
    PintorEspectro(
      banda: sim.banda,
      ventana: ventana,
      canales: const [],
      resaltados: const {},
    ).paint(canvas, virtual);
    canvas.restore();

    final e = PintorEspectro.escalaPara(virtual, ventana);
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    for (final em in sim.emisores) {
      _emisor(canvas, e, em);
    }
    _interferencia(canvas, e);
    final insignia = _insignia(
      canvas,
      Rect.fromLTWH(0, PintorEspectro.altoFranja, size.width, 20),
      'SIMULACIÓN',
    );
    _etiquetas(canvas, e, size, insignia);
    canvas.restore();
  }

  /// Nombres de los emisores en la franja que queda sobre la altura máxima de
  /// las formas (altura 1 = yTope), así el contorno nunca los cruza. No se
  /// enciman entre sí ni con la insignia; el que no cabe se omite (con zoom
  /// aparece). El seleccionado va primero.
  void _etiquetas(Canvas canvas, EscalaEspectro e, Size size, Rect insignia) {
    final fila = FilaEtiquetas()..reservar(insignia.left - 2, insignia.right + 2);
    final orden = [...sim.emisores]
      ..sort((a, b) => (b.demo.animado ? 1 : 0).compareTo(a.demo.animado ? 1 : 0));
    for (final em in orden) {
      final capa = em.capas(sim.potenciaConstante).last;
      if (capa.finMHz < ventana.inicioMHz || capa.inicioMHz > ventana.finMHz) continue;
      final color = ColoresEspectro.deCanal(em.demo.colorIndice);
      for (final s in ['${em.demo.nombre} · ${em.demo.primario}', em.demo.nombre]) {
        final tp = _texto(s, 10, color, negrita: true);
        final maxX = math.max(2.0, size.width - tp.width - 2);
        final x = (e.x(capa.centroMHz) - tp.width / 2).clamp(2.0, maxX).toDouble();
        if (!fila.reservar(x - 3, x + tp.width + 3)) continue;
        tp.paint(canvas, Offset(x, e.yTope - tp.height - 2));
        break;
      }
    }
  }

  Path _contorno(List<(double, double)> perfil, EscalaEspectro e, double escala) {
    final path = Path()..moveTo(e.x(perfil.first.$1), e.yBase);
    for (final (f, a) in perfil) {
      path.lineTo(e.x(f), e.y(a * escala));
    }
    path.lineTo(e.x(perfil.last.$1), e.yBase);
    return path..close();
  }

  void _emisor(Canvas canvas, EscalaEspectro e, EmisorSim em) {
    final color = ColoresEspectro.deCanal(em.demo.colorIndice);
    final capas = em.capas(sim.potenciaConstante);

    for (final capa in capas) {
      if (capa.altura <= 0.001) continue;
      final perfil = capa.perfil();
      // Contorno fantasma: la porción de espectro que el emisor tiene reservada.
      canvas.drawPath(
        _contorno(perfil, e, 1),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = color.withValues(alpha: 0.4),
      );
      // Relleno vivo: sube a la forma completa mientras hay una ráfaga de datos.
      final n = em.nivelDatos;
      if (n > 0.01) {
        final path = _contorno(perfil, e, n);
        canvas.drawPath(path, Paint()..color = color.withValues(alpha: 0.15 + 0.40 * n));
        canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..strokeJoin = StrokeJoin.round
            ..color = color.withValues(alpha: 0.5 + 0.5 * n),
        );
      }
    }

    // Beacon: solo el canal primario, aunque el emisor use más ancho.
    final nb = em.nivelBeacon;
    if (nb > 0.01) {
      final path = _contorno(em.capaBeacon(sim.potenciaConstante).perfil(), e, nb);
      canvas.drawPath(path, Paint()..color = Colors.white.withValues(alpha: 0.35 * nb));
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = Colors.white.withValues(alpha: 0.9 * nb),
      );
    }

  }

  void _interferencia(Canvas canvas, EscalaEspectro e) {
    final zonas = sim.interferenciasAhora();
    for (final z in zonas) {
      final rect = Rect.fromLTRB(e.x(z.fIniMHz), e.yTope, e.x(z.fFinMHz), e.yBase);
      canvas.drawRect(rect, Paint()..color = ColoresEspectro.solape.withValues(alpha: 0.5));
      canvas.drawRect(
        rect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = ColoresEspectro.solape,
      );
    }
    // La etiqueta va una vez por tramo: cruces() da una zona por cada par de
    // ráfagas, y varias pueden caer en el mismo tramo (se montaban). Aquí solo
    // se unen los tramos que se pisan para escribir el texto; las zonas y los
    // cálculos no cambian. Si dos tramos quedan pegados, FilaEtiquetas evita
    // que los textos se encimen (el que no cabe se omite).
    final tramos = <(double, double)>[];
    for (final z in [...zonas]..sort((a, b) => a.fIniMHz.compareTo(b.fIniMHz))) {
      if (tramos.isNotEmpty && z.fIniMHz < tramos.last.$2) {
        final ultimo = tramos.removeLast();
        tramos.add((ultimo.$1, math.max(ultimo.$2, z.fFinMHz)));
      } else {
        tramos.add((z.fIniMHz, z.fFinMHz));
      }
    }
    final fila = FilaEtiquetas();
    final tp = _texto('Interferencia', 10, Colors.white, negrita: true);
    for (final (f0, f1) in tramos) {
      final x0 = e.x(f0), x1 = e.x(f1);
      if (x1 - x0 <= tp.width + 6) continue;
      final x = (x0 + x1) / 2 - tp.width / 2;
      if (!fila.reservar(x - 3, x + tp.width + 3)) continue;
      tp.paint(canvas, Offset(x, e.yTope + 4));
    }
  }

  @override
  bool shouldRepaint(PintorEspectroEnVivo old) =>
      old.sim != sim || old.ventana != ventana;
}

// --- Cascada -------------------------------------------------------------------

class PintorCascada extends CustomPainter {
  PintorCascada({
    required this.sim,
    required this.ventana,
    required this.ventanaMs,
    required Listenable repaint,
  }) : super(repaint: repaint);

  final SimulacionEspectro sim;
  final VentanaFrecuencia ventana;

  /// Cuánto tiempo (simulado) cabe de arriba abajo.
  final double ventanaMs;

  @override
  void paint(Canvas canvas, Size size) {
    final e = PintorEspectro.escalaPara(size, ventana);
    final ahora = sim.tiempoMs;
    double yDe(double t) => (ahora - t) / ventanaMs * size.height;

    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, Paint()..color = ColoresEspectro.fondo);

    // Líneas de tiempo: "ahora" arriba y el pasado hacia abajo.
    for (var k = 0; k <= 4; k++) {
      final y = size.height * k / 4;
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        Paint()
          ..color = ColoresEspectro.textoTenue.withValues(alpha: 0.25)
          ..strokeWidth = 1,
      );
      final etiqueta = k == 0 ? 'ahora' : '−${_ms(ventanaMs * k / 4)} ms';
      final tp = _texto(etiqueta, 9, ColoresEspectro.textoTenue);
      final yTexto = k == 0 ? y + 2 : y - tp.height - 1;
      // Sin sitio debajo de "ahora": se omite la etiqueta en vez de encimarla.
      if (k > 0 && yTexto < 2 + tp.height + 2) continue;
      tp.paint(canvas, Offset(4, yTexto));
    }

    // Una ráfaga = un rectángulo: ancho = espectro que ocupa, alto = su duración.
    for (final em in sim.emisores) {
      final color = ColoresEspectro.deCanal(em.demo.colorIndice);
      for (final r in em.registro) {
        final fin = r.rafaga.finMs;
        if (fin < ahora - ventanaMs) continue;
        final top = yDe(fin < ahora ? fin : ahora);
        var bottom = yDe(r.rafaga.inicioMs);
        final esBeacon = r.rafaga.tipo == TipoRafaga.beacon;
        // Un beacon dura ~0,2–2 ms: con ventanas largas sería invisible, así que
        // se dibuja con un grosor mínimo (la posición sigue siendo la real).
        final minimo = esBeacon ? 2.0 : 1.5;
        if (bottom - top < minimo) bottom = top + minimo;
        final c = esBeacon ? Color.lerp(color, Colors.white, 0.6)! : color;
        final alfa = esBeacon ? 0.95 : (0.30 + 0.55 * r.altura).clamp(0.0, 0.9).toDouble();
        canvas.drawRect(
          Rect.fromLTRB(e.x(r.inicioMHz), top, e.x(r.finMHz), bottom),
          Paint()..color = c.withValues(alpha: alfa),
        );
      }
    }

    // Donde dos emisores coinciden en frecuencia y tiempo.
    for (final z in sim.interferenciasEnVentana(ventanaMs)) {
      final top = yDe(z.tFinMs);
      var bottom = yDe(z.tIniMs);
      if (bottom - top < 1.5) bottom = top + 1.5;
      canvas.drawRect(
        Rect.fromLTRB(e.x(z.fIniMHz), top, e.x(z.fFinMHz), bottom),
        Paint()..color = ColoresEspectro.solape.withValues(alpha: 0.9),
      );
    }

    _insignia(canvas, Offset.zero & size, 'SIMULACIÓN · modelo');
    canvas.restore();
  }

  @override
  bool shouldRepaint(PintorCascada old) =>
      old.sim != sim || old.ventana != ventana || old.ventanaMs != ventanaMs;
}
