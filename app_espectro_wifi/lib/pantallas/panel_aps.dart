// Incremento 4a: lista de puntos de acceso de una banda, editor de AP y
// diálogo para activar o desactivar canales.
//
// Requisitos del examen que cubre: 6 (agregar y visualizar varios APs con su
// canal y frecuencia) y 7 (activar/desactivar canales y modificar parámetros).
import 'package:material_ui/material_ui.dart';

import '../modelo/canales.dart';
import '../modelo/lista_aps.dart';
import '../modelo/punto_acceso.dart';
import '../modelo/redes_escaneadas.dart';
import '../vista/pintor_espectro.dart';
import 'hoja_sugerencia.dart';
import 'panel_analisis.dart';
import 'panel_escaneo.dart';

/// Lista de APs de [banda]. Es una columna sin scroll propio: quien la usa
/// decide si va dentro de un scroll.
class PanelAps extends StatelessWidget {
  const PanelAps({super.key, required this.modelo, required this.banda});

  final ModeloAps modelo;
  final Banda banda;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: modelo,
      builder: (context, _) {
        final tema = Theme.of(context).textTheme;
        final aps = modelo.de(banda);
        final sel = modelo.seleccionado(banda);
        final off = modelo.canalesDesactivados(banda);
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 8, 0),
            child: Row(children: [
              Expanded(
                child: Text(
                  'Puntos de acceso (${aps.length}'
                  '${aps.any((a) => a.escaneado) ? ', ${aps.where((a) => a.escaneado).length} escaneados' : ''})',
                  style: tema.titleSmall,
                ),
              ),
              TextButton.icon(
                onPressed: () => abrirDialogoCanales(context, modelo, banda),
                icon: const Icon(Icons.tune, size: 18),
                label: Text(off.isEmpty ? 'Canales' : 'Canales (${off.length} off)'),
              ),
              FilledButton.tonalIcon(
                onPressed: () => abrirEditorAp(context, modelo, modelo.borrador(banda)),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('AP'),
              ),
            ]),
          ),
          PanelEscaneo(modelo: modelo, banda: banda),
          if (off.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
              child: Text(
                'Canales desactivados: ${(off.toList()..sort()).join(', ')}',
                style: tema.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ),
          if (aps.isEmpty)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                'No hay puntos de acceso en ${banda.nombre}. Pulsa "+ AP" para agregar uno.',
                style: tema.bodySmall,
              ),
            ),
          for (final ap in aps)
            _TarjetaAp(
              ap: ap,
              modelo: modelo,
              seleccionado: sel?.id == ap.id,
            ),
          const Divider(height: 24),
          PanelAnalisis(modelo: modelo, banda: banda),
        ]);
      },
    );
  }
}

class _TarjetaAp extends StatelessWidget {
  const _TarjetaAp({required this.ap, required this.modelo, required this.seleccionado});

  final PuntoAcceso ap;
  final ModeloAps modelo;
  final bool seleccionado;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context).textTheme;
    final color = ColoresEspectro.deCanal(ap.colorIndice);
    final bloqueados = modelo.canalesBloqueados(ap);
    final String? estado = !ap.activo
        ? 'Apagado: no transmite.'
        : bloqueados.isNotEmpty
            ? 'Usa ${bloqueados.length == 1 ? 'el canal desactivado' : 'los canales desactivados'} '
                '${bloqueados.join(', ')}: no transmite.'
            : null;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: seleccionado ? color : Colors.transparent,
          width: 2,
        ),
      ),
      child: InkWell(
        onTap: () => modelo.seleccionar(ap),
        // Franja de 4 dp a la izquierda con el color del AP en el espectro.
        child: Stack(children: [
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          width: 4,
          child: ColoredBox(color: color),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 4, 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Fila 1: nombre completo (hasta 2 líneas) y, si es real, la
            // etiqueta. Ningún control le quita espacio al nombre.
            Padding(
              padding: const EdgeInsets.only(right: 8, top: 4),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: Text(
                    ap.nombre,
                    style: tema.titleSmall,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (ap.escaneado) ...[
                  const SizedBox(width: 8),
                  _EtiquetaReal(variosSsid: ap.variosSsid),
                ],
              ]),
            ),
            // Fila 2: nivel a la izquierda y los controles a la derecha.
            Row(children: [
              Expanded(
                child: Text(
                  ap.escaneado && ap.rssiDbm != null
                      ? 'RSSI ${ap.rssiDbm!.round()} dBm'
                      : 'PIRE ${ap.potenciaDbm.round()} dBm · ${ap.distanciaM.round()} m',
                  style: tema.bodySmall,
                ),
              ),
              Switch(
                value: ap.activo,
                onChanged: (_) => modelo.alternarActivo(ap.id),
              ),
              if (!ap.escaneado)
                IconButton(
                  tooltip: 'Editar',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () => abrirEditorAp(context, modelo, ap, existente: true),
                ),
              if (!ap.escaneado)
                IconButton(
                  tooltip: 'Quitar',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _confirmarQuitar(context),
                ),
            ]),
            for (final linea in describirOperacion(ap))
              Text(linea, style: tema.bodySmall),
            if (ap.escaneado) ..._datosEscaneo(context),
            if (estado != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  estado,
                  style: tema.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            _acciones(context),
          ]),
        ),
        ]),
      ),
    );
  }

  /// Datos crudos de Android, notas y el botón "Duplicar como simulado".
  List<Widget> _datosEscaneo(BuildContext context) {
    final tema = Theme.of(context).textTheme;
    final c = ap.canalOcupado;
    return [
      if (ap.variosSsid)
        Text('Varios SSID (${ap.ssids.length}): ${ap.ssids.join(' · ')}', style: tema.bodySmall),
      if (ap.vistaEn != null)
        Text(
          'Vista a las ${[ap.vistaEn!.hour, ap.vistaEn!.minute, ap.vistaEn!.second].map((v) => v.toString().padLeft(2, '0')).join(':')}',
          style: tema.bodySmall,
        ),
      Text(
        ap.bssids.length > 1 ? 'BSSID: ${ap.bssids.join(', ')}' : 'BSSID: ${ap.bssid ?? '—'}',
        style: tema.bodySmall,
      ),
      Text(
        'Android: frequency ${ap.frecuenciaPrimariaMHz} MHz · ancho ${c.anchoMHz} MHz'
        '${(ap.centro0Android ?? 0) > 0 ? ' · centerFreq0 ${ap.centro0Android} MHz' : ''}'
        '${(ap.centro1Android ?? 0) != 0 ? ' · centerFreq1 ${ap.centro1Android} MHz' : ''}'
        ' · RSSI ${ap.rssiDbm?.round() ?? '—'} dBm',
        style: tema.bodySmall,
      ),
      for (final nota in ap.notasEscaneo)
        Text(nota, style: tema.bodySmall?.copyWith(fontStyle: FontStyle.italic)),
    ];
  }

  /// "Sugerir canal" y, si es real, "Duplicar como simulado".
  Widget _acciones(BuildContext context) => Align(
        alignment: Alignment.centerRight,
        child: Wrap(alignment: WrapAlignment.end, children: [
          TextButton.icon(
            onPressed: () => abrirSugerencia(context, modelo, ap),
            icon: const Icon(Icons.auto_fix_high, size: 18),
            label: const Text('Sugerir canal'),
          ),
          if (ap.escaneado)
            TextButton.icon(
              onPressed: () {
                final b = modelo.borrador(ap.banda);
                abrirEditorAp(
                  context,
                  modelo,
                  duplicarComoSimulado(ap, id: b.id, colorIndice: b.colorIndice),
                );
              },
              icon: const Icon(Icons.copy, size: 18),
              label: const Text('Duplicar como simulado'),
            ),
        ]),
      );

  void _confirmarQuitar(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Quitar ${ap.nombre}'),
        content: Text('Se quita ${ap.nombre} (${resumenAp(ap)}) de la simulación.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () {
              modelo.quitar(ap.id);
              Navigator.of(ctx).pop();
            },
            child: const Text('Quitar'),
          ),
        ],
      ),
    );
  }
}

/// Etiqueta pequeña tipo chip de las redes escaneadas: "Real" o
/// "Real · varios SSID". Colores del ColorScheme actual.
class _EtiquetaReal extends StatelessWidget {
  const _EtiquetaReal({required this.variosSsid});

  final bool variosSsid;

  @override
  Widget build(BuildContext context) {
    final esquema = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: esquema.secondaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        variosSsid ? 'Real · varios SSID' : 'Real',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: esquema.onSecondaryContainer,
            ),
      ),
    );
  }
}

// --- Editor ------------------------------------------------------------------

/// Abre el editor con [ap]. Si [existente] es false, al guardar se agrega.
Future<void> abrirEditorAp(BuildContext context, ModeloAps modelo, PuntoAcceso ap,
    {bool existente = false}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => _EditorAp(modelo: modelo, inicial: ap, existente: existente),
  );
}

class _EditorAp extends StatefulWidget {
  const _EditorAp({required this.modelo, required this.inicial, required this.existente});

  final ModeloAps modelo;
  final PuntoAcceso inicial;
  final bool existente;

  @override
  State<_EditorAp> createState() => _EditorApState();
}

class _EditorApState extends State<_EditorAp> {
  late PuntoAcceso ap = widget.inicial;
  late final _nombre = TextEditingController(text: widget.inicial.nombre);

  @override
  void dispose() {
    _nombre.dispose();
    super.dispose();
  }

  Set<int> get _off => widget.modelo.canalesDesactivados(ap.banda);

  /// Aplica un cambio y deja el AP coherente: estándar válido en la banda,
  /// ancho válido para el estándar y primario válido para el ancho.
  void _cambiar(PuntoAcceso nuevo) {
    var a = nuevo;
    if (!a.estandar.permite(a.banda)) {
      a = a.copyWith(estandar: Estandar.elegiblesEn(a.banda).last);
    }
    final anchos = a.estandar.anchosEn(a.banda);
    if (!anchos.contains(a.anchoMHz)) a = a.copyWith(anchoMHz: anchos.first);
    final p = ajustarPrimario(a.banda, a.anchoMHz, a.canalPrimario, evitar: _offDe(a.banda));
    setState(() => ap = a.copyWith(canalPrimario: p));
  }

  Set<int> _offDe(Banda b) => widget.modelo.canalesDesactivados(b);

  void _guardar() {
    final listo = ap.copyWith(nombre: _nombre.text.trim());
    if (validarAp(listo) != null) return;
    if (widget.existente) {
      widget.modelo.editar(listo);
    } else {
      widget.modelo.agregar(listo);
    }
    Navigator.of(context).pop();
  }

  Widget _titulo(String s) => Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 4),
        child: Text(s, style: Theme.of(context).textTheme.titleSmall),
      );

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context).textTheme;
    final error = validarAp(ap.copyWith(nombre: _nombre.text.trim()));
    final primarios = primariosValidos(ap.banda, ap.anchoMHz);
    final off = _off;
    final usaOff = widget.modelo.canalesBloqueados(ap);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(widget.existente ? 'Editar ${widget.inicial.nombre}' : 'Nuevo punto de acceso',
                style: tema.titleMedium),
            const SizedBox(height: 8),
            TextField(
              controller: _nombre,
              decoration: const InputDecoration(labelText: 'Nombre', isDense: true),
              onChanged: (_) => setState(() {}),
            ),
            _titulo('Banda'),
            Wrap(spacing: 8, children: [
              for (final b in [Banda.ghz24, Banda.ghz5])
                ChoiceChip(
                  label: Text(b.nombre),
                  selected: ap.banda == b,
                  onSelected: (_) => _cambiar(ap.copyWith(
                    banda: b,
                    canalPrimario: b == Banda.ghz24 ? 1 : 36,
                  )),
                ),
            ]),
            _titulo('Estándar'),
            Wrap(spacing: 8, runSpacing: 4, children: [
              for (final e in Estandar.elegiblesEn(ap.banda))
                ChoiceChip(
                  label: Text(e.etiqueta),
                  selected: ap.estandar == e,
                  onSelected: (_) => _cambiar(ap.copyWith(estandar: e)),
                ),
            ]),
            _titulo('Ancho de canal'),
            Wrap(spacing: 8, children: [
              for (final w in ap.estandar.anchosEn(ap.banda))
                ChoiceChip(
                  label: Text('$w MHz'),
                  selected: ap.anchoMHz == w,
                  onSelected: (_) => _cambiar(ap.copyWith(anchoMHz: w)),
                ),
            ]),
            _titulo('Canal primario'),
            DropdownButton<int>(
              value: primarios.contains(ap.canalPrimario) ? ap.canalPrimario : null,
              isExpanded: true,
              items: [
                for (final n in primarios)
                  DropdownMenuItem(
                    value: n,
                    enabled: !off.contains(n),
                    child: Text(
                      '$n · ${frecuenciaDeCanal(ap.banda, n)} MHz'
                      '${off.contains(n) ? ' (desactivado)' : ''}',
                    ),
                  ),
              ],
              onChanged: (n) {
                if (n != null) _cambiar(ap.copyWith(canalPrimario: n));
              },
            ),
            if (ap.banda == Banda.ghz5 && ap.anchoMHz > 20)
              Text(
                'Solo aparecen los canales que forman un bloque de ${ap.anchoMHz} MHz.',
                style: tema.bodySmall,
              ),
            if (ap.banda == Banda.ghz24 && ap.anchoMHz == 40)
              Text(
                'HT40: el secundario va 4 canales arriba del primario (abajo desde el 10).',
                style: tema.bodySmall,
              ),
            _titulo('Potencia (PIRE): ${ap.potenciaDbm.round()} dBm'),
            Slider(
              value: ap.potenciaDbm,
              min: 0,
              max: 30,
              divisions: 30,
              label: '${ap.potenciaDbm.round()} dBm',
              onChanged: (v) => setState(() => ap = ap.copyWith(potenciaDbm: v)),
            ),
            Text(
              'Se usa en el análisis de interferencia. El límite legal en Colombia está '
              'pendiente de confirmar en el Anexo 1 de la Res. ANE 105/2020.',
              style: tema.bodySmall,
            ),
            _titulo('Distancia al punto de observación: ${ap.distanciaM.round()} m'),
            Slider(
              value: ap.distanciaM.clamp(1, 200).toDouble(),
              min: 1,
              max: 200,
              divisions: 199,
              label: '${ap.distanciaM.round()} m',
              onChanged: (v) => setState(() => ap = ap.copyWith(distanciaM: v)),
            ),
            Text(
              'Nivel en el celular = PIRE − pérdida en espacio libre (ITU-R P.525). '
              'Con poca PIRE o mucha distancia aparecen los casos asimétricos.',
              style: tema.bodySmall,
            ),
            _titulo('Carga de tráfico (animación): ${(ap.carga * 100).round()} %'),
            Slider(
              value: ap.carga,
              min: 0.05,
              max: 0.9,
              divisions: 17,
              label: '${(ap.carga * 100).round()} %',
              onChanged: (v) => setState(() => ap = ap.copyWith(carga: v)),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Encendido'),
              value: ap.activo,
              onChanged: (v) => setState(() => ap = ap.copyWith(activo: v)),
            ),
            const Divider(),
            Text('Así opera', style: tema.titleSmall),
            const SizedBox(height: 4),
            for (final linea in describirOperacion(ap)) Text(linea, style: tema.bodySmall),
            if (usaOff.isNotEmpty)
              Text(
                'Usa canales desactivados (${usaOff.join(', ')}): no transmitirá.',
                style: tema.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  error,
                  style: tema.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ),
            const SizedBox(height: 12),
            Row(children: [
              if (widget.existente)
                TextButton.icon(
                  onPressed: () {
                    widget.modelo.quitar(ap.id);
                    Navigator.of(context).pop();
                  },
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Quitar'),
                ),
              const Spacer(),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancelar'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: error == null ? _guardar : null,
                child: Text(widget.existente ? 'Guardar' : 'Agregar'),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}

// --- Canales activados / desactivados ------------------------------------------

Future<void> abrirDialogoCanales(BuildContext context, ModeloAps modelo, Banda banda) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Canales de ${banda.nombre}'),
      // El diálogo entero se desplaza: en 5 GHz se llega hasta el 165.
      scrollable: true,
      content: ListenableBuilder(
        listenable: modelo,
        builder: (ctx, _) {
          final tema = Theme.of(ctx).textTheme;
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Toca un canal para activarlo o desactivarlo. Un canal desactivado no '
                'se puede asignar, y el AP que lo use (como primario o dentro de su '
                'bloque de 40/80/160 MHz) deja de transmitir, como cuando DFS obliga '
                'a desalojar un canal.',
                style: tema.bodySmall,
              ),
              const SizedBox(height: 8),
              // Cuadrícula pareja: todos los botones de 72 × 48 dp.
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final n in canales20De(banda))
                  _BotonCanal(
                    numero: n,
                    frecuenciaMHz: frecuenciaDeCanal(banda, n),
                    activo: modelo.canalActivo(banda, n),
                    alTocar: () => modelo.alternarCanal(banda, n),
                  ),
              ]),
            ],
          );
        },
      ),
      actions: [
        TextButton(
          onPressed: () => modelo.activarTodos(banda),
          child: const Text('Activar todos'),
        ),
        FilledButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cerrar')),
      ],
    ),
  );
}

/// Canal alternable de 72 × 48 dp: tonal si está activo, con borde si no.
class _BotonCanal extends StatelessWidget {
  const _BotonCanal({
    required this.numero,
    required this.frecuenciaMHz,
    required this.activo,
    required this.alTocar,
  });

  final int numero;
  final int frecuenciaMHz;
  final bool activo;
  final VoidCallback alTocar;

  static const _estilo = ButtonStyle(
    fixedSize: WidgetStatePropertyAll(Size(72, 48)),
    padding: WidgetStatePropertyAll(EdgeInsets.zero),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  );

  @override
  Widget build(BuildContext context) {
    final texto = Text('$numero', maxLines: 1);
    return Tooltip(
      message: '$frecuenciaMHz MHz · ${activo ? 'activo' : 'desactivado'}',
      child: Semantics(
        toggled: activo,
        child: activo
            ? FilledButton.tonal(onPressed: alTocar, style: _estilo, child: texto)
            : OutlinedButton(onPressed: alTocar, style: _estilo, child: texto),
      ),
    );
  }
}
