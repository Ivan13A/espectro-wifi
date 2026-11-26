// Incremento 6: figura del espectro para el reporte, dibujada fuera de
// pantalla con el mismo PintorEspectro de la vista de APs (PictureRecorder →
// PNG). 800×300 lógicos con canvas.scale(2): PNG de 1600×600 y las etiquetas
// del pintor conservan su tamaño relativo.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

import '../modelo/canales.dart';
import '../modelo/punto_acceso.dart';
import '../vista/escala_espectro.dart';
import '../vista/pintor_espectro.dart';

const tamanoFigura = Size(800, 300);
const escalaFigura = 2.0;

/// PNG de [banda] completa con [aps] (los que transmiten), como en la vista
/// de APs: los canales de 20 MHz solo como referencia. null si falla.
Future<Uint8List?> capturarEspectro(Banda banda, List<PuntoAcceso> aps) async {
  final grabadora = ui.PictureRecorder();
  final lienzo = Canvas(grabadora);
  lienzo.scale(escalaFigura);
  PintorEspectro(
    banda: banda,
    ventana: VentanaFrecuencia.completa(banda),
    canales: banda == Banda.ghz24
        ? CatalogoCanales.canales24(Modo24.ofdm20)
        : CatalogoCanales.canales5(20),
    resaltados: const <int>{},
    aps: aps,
    soloNumeros: true,
  ).paint(lienzo, tamanoFigura);
  final dibujo = grabadora.endRecording();
  final imagen = await dibujo.toImage(
    (tamanoFigura.width * escalaFigura).round(),
    (tamanoFigura.height * escalaFigura).round(),
  );
  dibujo.dispose();
  try {
    final datos = await imagen.toByteData(format: ui.ImageByteFormat.png);
    return datos?.buffer.asUint8List();
  } finally {
    imagen.dispose();
  }
}
