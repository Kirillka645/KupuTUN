import 'package:flutter/material.dart';

import '../../core/models/server.dart';
import '../../core/util/country.dart';
import '../../tester/server_sorter.dart';
import '../l10n.dart';

Future<ServerFilter?> showFilterSheet(BuildContext context, ServerFilter current, Set<String> countries) =>
    showModalBottomSheet<ServerFilter>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _FilterSheet(current: current, countries: countries),
    );

class _FilterSheet extends StatefulWidget {
  final ServerFilter current;
  final Set<String> countries;
  const _FilterSheet({required this.current, required this.countries});
  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late ServerFilter f = widget.current;
  late final _ping = TextEditingController(text: widget.current.maxPingMs?.toString() ?? '');
  late final _speed = TextEditingController(text: widget.current.minSpeedMbps?.toString() ?? '');

  @override
  void dispose() {
    _ping.dispose();
    _speed.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final countries = widget.countries.toList()..sort();
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.of(context).viewInsets.bottom + 16),
      child: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(context.tr('onlyAlive')),
            value: f.onlyAlive,
            onChanged: (v) => setState(() => f = f.copyWith(onlyAlive: v)),
          ),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _ping,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: context.tr('maxPing')),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _speed,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: context.tr('minSpeed')),
              ),
            ),
          ]),
          const SizedBox(height: 16),
          Text(context.tr('protocol'), style: Theme.of(context).textTheme.titleSmall),
          Wrap(spacing: 6, children: [
            for (final p in ProxyProtocol.values)
              FilterChip(
                label: Text(p.label),
                selected: f.protocols.contains(p),
                onSelected: (v) => setState(() => f = f.copyWith(protocols: v ? {...f.protocols, p} : ({...f.protocols}..remove(p)))),
              ),
          ]),
          const SizedBox(height: 16),
          if (countries.isNotEmpty) ...[
            Text(context.tr('country'), style: Theme.of(context).textTheme.titleSmall),
            Wrap(spacing: 6, children: [
              for (final c in countries)
                FilterChip(
                  label: Text('${CountryDetector.flagOf(c)} $c'),
                  selected: f.countries.contains(c),
                  onSelected: (v) => setState(() => f = f.copyWith(countries: v ? {...f.countries, c} : ({...f.countries}..remove(c)))),
                ),
            ]),
          ],
          const SizedBox(height: 16),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            TextButton(onPressed: () => Navigator.pop(context, ServerFilter(query: f.query)), child: Text(context.tr('reset'))),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: () {
                final ping = int.tryParse(_ping.text.trim());
                final speed = double.tryParse(_speed.text.trim().replaceAll(',', '.'));
                Navigator.pop(
                  context,
                  f.copyWith(maxPingMs: ping, clearMaxPing: ping == null, minSpeedMbps: speed, clearMinSpeed: speed == null),
                );
              },
              child: Text(context.tr('apply')),
            ),
          ]),
        ]),
      ),
    );
  }
}
