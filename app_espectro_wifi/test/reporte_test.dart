// Incremento 6: reporte PDF. (Escritas sin correr; ver PROGRESO.md.)
// Las figuras van en null: PictureRecorder → PNG se prueba en el celular.
import 'dart:io';
import 'dart:typed_data';

import 'package:app_espectro_wifi/modelo/canales.dart';
import 'package:app_espectro_wifi/modelo/lista_aps.dart';
import 'package:app_espectro_wifi/modelo/punto_acceso.dart';
import 'package:app_espectro_wifi/reporte/datos_reporte.dart';
import 'package:app_espectro_wifi/reporte/reporte_pdf.dart';
import 'package:flutter_test/flutter_test.dart';

ByteData _fuente(String nombre) =>
    ByteData.sublistView(File('assets/fuentes/$nombre').readAsBytesSync());

/// Los 6 APs de ejemplo (3 por banda), con el primero de 2.4 GHz apagado,
/// más una red escaneada en el canal 6.
DatosReporte _ejemplo() {
  final m = ModeloAps.conEjemplo();
  m.alternarActivo('ghz24-ej0');
  m.reemplazarEscaneados([
    PuntoAcceso(
      id: 'esc-1',
      nombre: 'Laboratorio',
      banda: Banda.ghz24,
      canalPrimario: 6,
      anchoMHz: 20,
      estandar: Estandar.n,
      origen: OrigenAp.escaneado,
      rssiDbm: -60,
      bssid: 'aa:bb:cc:dd:ee:01',
      ssids: const ['Laboratorio'],
      bssids: const ['aa:bb:cc:dd:ee:01'],
      estandarReportado: '802.11n',
      vistaEn: DateTime(2026, 11, 25, 10, 29, 50),
    ),
  ]);
  return DatosReporte(
    fecha: DateTime(2026, 11, 25, 10, 30),
    lugar: 'Edificio de ingenierías, piso 2',
    observaciones: 'Prueba con datos de ejemplo.',
    horaEscaneo: DateTime(2026, 11, 25, 10, 29, 55),
    bandas: [
      BandaReporte.desdeModelo(m, Banda.ghz24),
      BandaReporte.desdeModelo(m, Banda.ghz5),
    ],
  );
}

void main() {
  final fuentes = FuentesReporte.desdeBytes(
    _fuente('NotoSans-Regular.ttf'),
    _fuente('NotoSans-Bold.ttf'),
  );

  test('con datos de ejemplo genera bytes de PDF no vacíos', () async {
    final bytes = await generarReportePdf(_ejemplo(), fuentes: fuentes);
    expect(bytes, isNotEmpty);
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  });

  test('la tabla de redes tiene una fila por AP que transmite', () {
    final d = _ejemplo();
    final filas = filasTablaRedes(d);
    // 2.4 GHz: 3 de ejemplo − 1 apagado + 1 escaneado = 3; 5 GHz: 3.
    expect(filas.length, 6);
    expect(filas.length, d.bandas.fold(0, (s, b) => s + b.transmitiendo.length));
    expect(d.bandas.first.noTransmiten, 1);
    expect(filas.every((f) => f.length == encabezadoRedes.length), isTrue);

    final real = filas.singleWhere((f) => f.last == 'Real');
    expect(real[0], 'Laboratorio');
    expect(real[8], 'RSSI −60 dBm');
    expect(real[9], '10:29:50');
    expect(filas.where((f) => f.last == 'Simulado').length, 5);
  });

  test('textoPdf cambia los caracteres que Noto Sans no tiene', () {
    expect(textoPdf('SIR ≥ 27 dB → leve; PIRE ≤ 17 dBm'),
        'SIR >= 27 dB -> leve; PIRE <= 17 dBm');
    // Los que sí tiene quedan igual.
    expect(textoPdf('−82 dBm · 2×2 · canal 6 – 11 · señal'), '−82 dBm · 2×2 · canal 6 – 11 · señal');
  });

  test('nombre del archivo con fecha y hora', () {
    expect(nombreArchivoReporte(DateTime(2026, 11, 5, 9, 4, 7)),
        'reporte_espectro_wifi_20261105_090407.pdf');
  });
}
