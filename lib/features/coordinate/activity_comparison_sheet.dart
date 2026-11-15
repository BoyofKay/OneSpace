import 'package:material_ui/material_ui.dart';

import 'activity_comparison_matrix.dart';
import 'package:onespace/l10n/phrases.dart';

/// Structured comparison of the same questions across different candidates.
/// The first column holds criteria, and each option is a horizontally
/// scrollable column. Absent information is explicitly marked as unknown.
class ActivityComparisonSheet extends StatelessWidget {
  const ActivityComparisonSheet({
    super.key,
    required this.matrix,
    required this.onChoose,
    required this.onOpenSource,
  });

  final ActivityComparisonMatrix matrix;
  final void Function(String optionId) onChoose;
  final void Function(String url) onOpenSource;

  String _opinion(int? value) => switch (value) {
    1 => '👍',
    -1 => '👎',
    _ => '—',
  };

  Widget _optionHeader(BuildContext context, ActivityComparisonColumn option) {
    return SizedBox(
      width: 180,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tt(option.title),
            maxLines: 2, overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600)),
          Row(children: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                onChoose(option.id);
              },
              child: Text(tt('Choose')),
            ),
            if (option.sourceUrl.isNotEmpty)
              IconButton(
                tooltip: tt('Open source'),
                icon: const Icon(Icons.open_in_new, size: 18),
                onPressed: () => onOpenSource(option.sourceUrl),
              ),
          ]),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: FractionallySizedBox(
        heightFactor: 0.84,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(14, 4, 14, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${tt('Compare')} ${matrix.columns.length} ${tt('options')}',
                    style: theme.textTheme.titleLarge),
                  const SizedBox(height: 3),
                  Text(tt('Swipe sideways to see every candidate. '
                    'Prices are manually recorded, not live.'),
                    style: theme.textTheme.bodySmall),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.vertical,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    horizontalMargin: 12,
                    columnSpacing: 12,
                    headingRowHeight: 98,
                    dataRowMinHeight: 48,
                    dataRowMaxHeight: 144,
                    columns: [
                      DataColumn(label: SizedBox(
                        width: 98,
                        child: Text(tt('Compare by'),
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      )),
                      for (final option in matrix.columns)
                        DataColumn(label: _optionHeader(context, option)),
                    ],
                    rows: [
                      DataRow(cells: [
                        DataCell(Text(tt('Opinions'))),
                        for (final option in matrix.columns)
                          DataCell(SizedBox(width: 180, child: Text(
                            tt('You ${_opinion(option.myOpinion)}  '
                            'Partner ${_opinion(option.partnerOpinion)}'),
                            style: theme.textTheme.bodyMedium))),
                      ]),
                      for (final row in matrix.rows)
                        DataRow(cells: [
                          DataCell(SizedBox(width: 98, child: Text(
                            tt(row.key == 'price' ? 'Price (observed)' : row.label),
                            style: theme.textTheme.labelMedium,
                            softWrap: true))),
                          for (final option in matrix.columns)
                            DataCell(SizedBox(width: 180, child: Text(
                              tt(matrix.value(row.key, option)),
                              maxLines: 6,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium))),
                        ]),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
