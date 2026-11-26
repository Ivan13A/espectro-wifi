// Incremento 6: botón del reporte PDF en la barra superior. Pide lugar y
// observaciones, arma DatosReporte con lo que ya calcula la app, dibuja las
// figuras, genera el PDF y lo guarda en Descargas por el canal de Android.
// En el navegador solo avisa que el PDF se genera en Android.
import 'package:material_ui/material_ui.dart';

import '../modelo/canales.dart';
import '../modelo/lista_aps.dart';
import '../reporte/captura_espectro.dart';
import '../reporte/datos_reporte.dart';
import '../reporte/reporte_pdf.dart';
import '../servicios/archivos_pdf.dart';
import '../servicios/escaner_wifi.dart';

class BotonReporte extends StatefulWidget {
  const BotonReporte({super.key, required this.modelo});

  final ModeloAps modelo;

  @override
  State<BotonReporte> createState() => _BotonReporteState();
}

class _BotonReporteState extends State<BotonReporte> {
  bool _generando = false;

  void _avisar(String texto, {SnackBarAction? accion}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(texto),
        action: accion,
        duration: Duration(seconds: accion == null ? 4 : 8),
      ));
  }

  Future<void> _generar() async {
    if (!ArchivosPdf.disponible) {
      _avisar('El reporte PDF se genera en la app de Android.');
      return;
    }
    final entrada = await showDialog<(String, String)>(
      context: context,
      builder: (_) => const _DialogoReporte(),
    );
    if (entrada == null || !mounted) return;
    setState(() => _generando = true);
    _avisar('Generando el reporte…');
    try {
      final modelo = widget.modelo;
      final escaneo = ControladorEscaneo.de(modelo);
      final bandas = <BandaReporte>[];
      for (final b in const [Banda.ghz24, Banda.ghz5]) {
        final figura = await capturarEspectro(b, modelo.transmitiendoEn(b));
        bandas.add(BandaReporte.desdeModelo(modelo, b, figuraPng: figura));
      }
      final ahora = DateTime.now();
      final datos = DatosReporte(
        fecha: ahora,
        lugar: entrada.$1,
        observaciones: entrada.$2,
        modeloCelular: await ArchivosPdf.modeloCelular(),
        horaEscaneo: escaneo.horaUltimo,
        horaResultados: escaneo.horaResultados,
        bandas: bandas,
        recomendaciones: recomendacionesDe(modelo),
      );
      final bytes = await generarReportePdf(datos);
      final g = await ArchivosPdf.guardar(bytes, nombreArchivoReporte(ahora));
      if (!mounted) return;
      final compartir = SnackBarAction(
        label: 'Compartir',
        onPressed: () => ArchivosPdf.compartir(g.uri),
      );
      if (g.enDescargas) {
        _avisar('Guardado en Descargas', accion: compartir);
      } else {
        // Android 9 o anterior: queda en la carpeta de la app; se abre
        // Compartir de una vez para poder sacarlo de ahí.
        _avisar('Guardado en la carpeta de la app', accion: compartir);
        await ArchivosPdf.compartir(g.uri);
      }
    } catch (e) {
      if (mounted) _avisar('No se pudo generar el reporte: $e');
    } finally {
      if (mounted) setState(() => _generando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Reporte PDF',
      icon: _generando
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.picture_as_pdf),
      onPressed: _generando ? null : _generar,
    );
  }
}

/// Lugar y observaciones (los dos opcionales). Devuelve (lugar, observaciones)
/// o null si se cancela.
class _DialogoReporte extends StatefulWidget {
  const _DialogoReporte();

  @override
  State<_DialogoReporte> createState() => _DialogoReporteState();
}

class _DialogoReporteState extends State<_DialogoReporte> {
  final _lugar = TextEditingController();
  final _obs = TextEditingController();

  @override
  void dispose() {
    _lugar.dispose();
    _obs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Reporte PDF'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: _lugar,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Lugar del escaneo (opcional)'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _obs,
            textCapitalization: TextCapitalization.sentences,
            minLines: 2,
            maxLines: 5,
            decoration: const InputDecoration(labelText: 'Observaciones (opcional)'),
          ),
        ]),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, (_lugar.text, _obs.text)),
          child: const Text('Generar'),
        ),
      ],
    );
  }
}
