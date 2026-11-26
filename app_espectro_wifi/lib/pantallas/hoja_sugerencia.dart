// "Sugerir canal": hoja inferior con la configuración actual y las 3 mejores
// del orden de sugerirCanal(). AP simulado: "Aplicar" lo edita. AP real:
// "Probar en simulación" crea una copia simulada y apaga la red real.
import 'package:material_ui/material_ui.dart';

import '../modelo/canales.dart';
import '../modelo/lista_aps.dart';
import '../modelo/punto_acceso.dart';
import '../modelo/sugerencia.dart';

/// La sugerencia para [ap] con lo que transmite ahora en su banda.
SugerenciaCanal sugerenciaPara(ModeloAps modelo, PuntoAcceso ap) => sugerirCanal(
      ap,
      modelo.transmitiendoEn(ap.banda),
      desactivados: modelo.canalesDesactivados(ap.banda),
    );

Future<void> abrirSugerencia(BuildContext context, ModeloAps modelo, PuntoAcceso ap) {
  final s = sugerenciaPara(modelo, ap);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => _HojaSugerencia(modelo: modelo, sugerencia: s),
  );
}

class _HojaSugerencia extends StatelessWidget {
  const _HojaSugerencia({required this.modelo, required this.sugerencia});

  final ModeloAps modelo;
  final SugerenciaCanal sugerencia;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context).textTheme;
    final esquema = Theme.of(context).colorScheme;
    final s = sugerencia;
    final ap = s.objetivo;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Sugerir canal para ${ap.nombre}', style: tema.titleMedium),
          const SizedBox(height: 4),
          Text(supuestoSugerencia, style: tema.bodySmall),
          if (ap.banda == Banda.ghz24) ...[
            const SizedBox(height: 4),
            Text(regla24, style: tema.bodySmall?.copyWith(fontStyle: FontStyle.italic)),
          ],
          if (s.actualEsMejor)
            Container(
              margin: const EdgeInsets.only(top: 10),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: esquema.primaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Ya está en la mejor opción según el análisis.',
                style: tema.bodyMedium?.copyWith(color: esquema.onPrimaryContainer),
              ),
            ),
          const SizedBox(height: 12),
          Text('Configuración actual', style: tema.titleSmall),
          _TarjetaOpcion(opcion: s.actual),
          const SizedBox(height: 8),
          Text(
            s.mejores.isEmpty ? 'No hay otros canales disponibles.' : 'Mejores alternativas',
            style: tema.titleSmall,
          ),
          for (final o in s.mejores)
            _TarjetaOpcion(
              opcion: o,
              accion: ap.escaneado
                  ? FilledButton.tonal(
                      onPressed: () {
                        modelo.probarEnSimulacion(ap, o.primario, o.anchoMHz);
                        Navigator.of(context).pop();
                      },
                      child: const Text('Probar en simulación'),
                    )
                  : FilledButton.tonal(
                      onPressed: () {
                        modelo.editar(o.ap);
                        Navigator.of(context).pop();
                      },
                      child: const Text('Aplicar'),
                    ),
            ),
          if (ap.escaneado && s.mejores.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '"Probar en simulación" crea una copia simulada con esa configuración y el '
                'mismo nivel, y apaga la red real (sigue apagada aunque vuelvas a escanear; '
                'se enciende con su interruptor o con "Limpiar").',
                style: tema.bodySmall,
              ),
            ),
        ]),
      ),
    );
  }
}

class _TarjetaOpcion extends StatelessWidget {
  const _TarjetaOpcion({required this.opcion, this.accion});

  final OpcionCanal opcion;
  final Widget? accion;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context).textTheme;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(opcion.razon, style: tema.bodyMedium),
          if (opcion.comparacion.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(opcion.comparacion, style: tema.bodySmall),
          ],
          if (accion != null) Align(alignment: Alignment.centerRight, child: accion),
        ]),
      ),
    );
  }
}
