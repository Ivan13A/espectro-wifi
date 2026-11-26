// Incremento 4b: análisis de solapamiento e interferencia de los APs de una
// banda. Va debajo de la lista de APs.
//
// Requisito del examen que cubre: 5 (evidenciar solapamiento e interferencia).
import 'package:material_ui/material_ui.dart';

import '../modelo/analisis.dart';
import '../modelo/canales.dart';
import '../modelo/lista_aps.dart';
import '../modelo/punto_acceso.dart';

/// Color de una gravedad. Grave y "sin gravedad" salen del ColorScheme; leve y
/// moderada no tienen rol (verde y ámbar), así que se ajustan al brillo del
/// tema para que se lean tanto en claro como en oscuro.
Color colorGravedad(Gravedad? g, ColorScheme esquema) {
  final oscuro = esquema.brightness == Brightness.dark;
  return switch (g) {
    Gravedad.leve => oscuro ? Colors.green.shade300 : Colors.green.shade700,
    Gravedad.moderada => oscuro ? Colors.amber.shade400 : Colors.amber.shade800,
    Gravedad.grave => esquema.error,
    null => esquema.onSurfaceVariant,
  };
}

IconData iconoRelacion(TipoRelacion t) => switch (t) {
      TipoRelacion.independientes => Icons.check_circle_outline,
      TipoRelacion.seTurnan => Icons.sync_alt,
      TipoRelacion.asimetrica => Icons.arrow_right_alt,
      TipoRelacion.simultanea => Icons.flash_on,
    };

/// Análisis de [banda]. Columna sin scroll propio, como PanelAps.
class PanelAnalisis extends StatefulWidget {
  const PanelAnalisis({super.key, required this.modelo, required this.banda});

  final ModeloAps modelo;
  final Banda banda;

  @override
  State<PanelAnalisis> createState() => _PanelAnalisisState();
}

class _PanelAnalisisState extends State<PanelAnalisis> {
  bool _soloSeleccionado = false;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.modelo,
      builder: (context, _) {
        final tema = Theme.of(context).textTheme;
        final aps = widget.modelo.transmitiendoEn(widget.banda);
        final analisis = analizar(aps);
        final sel = widget.modelo.seleccionado(widget.banda);
        final filtrar = _soloSeleccionado && sel != null;
        final pares = [
          for (final p in analisis.conSolape)
            if (!filtrar || p.incluye(sel.id)) p,
        ];
        final sinSolape = analisis.pares.length - analisis.conSolape.length;

        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: Text('Análisis de solapamiento e interferencia (simulación)',
                style: tema.titleSmall),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 2, 12, 4),
            child: Text(supuestoPuntoObservacion, style: tema.bodySmall),
          ),
          if (aps.length < 2)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text('Hacen falta al menos dos APs transmitiendo en '
                  '${widget.banda.nombre} para analizar pares.', style: tema.bodySmall),
            )
          else ...[
            _ResumenAps(analisis: analisis, aps: aps),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Wrap(
                spacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text('Pares con solape (${analisis.conSolape.length})',
                      style: tema.titleSmall),
                  if (sel != null)
                    FilterChip(
                      label: Text('Solo ${sel.nombre}'),
                      selected: _soloSeleccionado,
                      onSelected: (v) => setState(() => _soloSeleccionado = v),
                    ),
                ],
              ),
            ),
            if (sinSolape > 0)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
                child: Text(
                  '$sinSolape ${sinSolape == 1 ? 'par no se solapa' : 'pares no se solapan'}: '
                  'independientes.',
                  style: tema.bodySmall,
                ),
              ),
            if (pares.isEmpty)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  filtrar
                      ? '${sel.nombre} no se solapa con ningún AP.'
                      : 'Ningún par se solapa: no hay interferencia.',
                  style: tema.bodySmall,
                ),
              ),
            for (final p in pares) _TarjetaPar(par: p),
          ],
          const _Umbrales(),
        ]);
      },
    );
  }
}

/// Una fila por AP: nivel, SIR y con quién se turna.
class _ResumenAps extends StatelessWidget {
  const _ResumenAps({required this.analisis, required this.aps});

  final AnalisisBanda analisis;
  final List<PuntoAcceso> aps;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context).textTheme;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Por AP', style: tema.titleSmall),
          for (final ap in aps)
            () {
              final r = analisis.porAp[ap.id]!;
              final g = r.gravedad;
              final sir = r.sirDb == null
                  ? 'sin interferencia simultánea'
                  : 'SIR ${textoDb(r.sirDb!)} · ${g!.nombre.toLowerCase()} '
                      '(interfieren: ${r.interferentes.map((x) => x.nombre).join(', ')})';
              final turno = r.contencion.isEmpty
                  ? ''
                  : ' · se turna con ${r.contencion.map((x) => x.nombre).join(', ')}';
              return Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 3, right: 6),
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: colorGravedad(g, Theme.of(context).colorScheme),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      '${ap.nombre}: nivel ${textoDbm(r.nivelDbm)} · $sir$turno',
                      style: tema.bodySmall,
                    ),
                  ),
                ]),
              );
            }(),
        ]),
      ),
    );
  }
}

class _TarjetaPar extends StatelessWidget {
  const _TarjetaPar({required this.par});

  final RelacionPar par;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context).textTheme;
    final t = par.tipo;
    // Color: la peor gravedad de las dos direcciones; azul si se turnan.
    final peor = par.peorGravedad;
    final color = colorGravedad(peor, Theme.of(context).colorScheme);
    // En la asimétrica la flecha va del que transmite encima al que cede.
    final titulo = switch (t) {
      TipoRelacion.asimetrica => par.aOyeB!.oye
          ? '${par.b.nombre} → ${par.a.nombre}'
          : '${par.a.nombre} → ${par.b.nombre}',
      _ => '${par.a.nombre} y ${par.b.nombre}',
    };
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: color.withValues(alpha: 0.7), width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(iconoRelacion(t), size: 18, color: color),
            const SizedBox(width: 6),
            Expanded(child: Text('$titulo · ${t.nombre}', style: tema.titleSmall)),
            if (peor != null)
              Text(peor.nombre,
                  style: tema.labelMedium?.copyWith(color: color, fontWeight: FontWeight.bold)),
          ]),
          Text(t.descripcion, style: tema.bodySmall?.copyWith(fontStyle: FontStyle.italic)),
          const SizedBox(height: 2),
          for (final linea in par.explicacion()) Text('• $linea', style: tema.bodySmall),
        ]),
      ),
    );
  }
}

/// Lista plegable de umbrales con su fuente y si está verificado.
class _Umbrales extends StatelessWidget {
  const _Umbrales();

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context).textTheme;
    return ExpansionTile(
      tilePadding: const EdgeInsets.symmetric(horizontal: 12),
      childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      title: Text('Umbrales y fuentes', style: tema.titleSmall),
      children: [
        for (final u in Umbrales.todos)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${textoDbm(u.valorDbm)} · ${u.nombre}',
                  style: tema.bodySmall?.copyWith(fontWeight: FontWeight.bold)),
              Text(u.uso, style: tema.bodySmall),
              Text('Fuente: ${u.fuente}. Estado: ${u.estado.descripcion}.',
                  style: tema.bodySmall?.copyWith(fontStyle: FontStyle.italic)),
            ]),
          ),
        Text('Gravedad', style: tema.bodySmall?.copyWith(fontWeight: FontWeight.bold)),
        Text(CortesSir.explicacion, style: tema.bodySmall),
        const SizedBox(height: 6),
        Text('Otros supuestos', style: tema.bodySmall?.copyWith(fontWeight: FontWeight.bold)),
        Text(otrosSupuestos, style: tema.bodySmall),
      ],
    );
  }
}
