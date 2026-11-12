import 'package:material_ui/material_ui.dart';

/// A local-only planning preview. Server persistence and partner sync come later.
enum PlanPriority { low, normal, high }
enum PlanFilter { all, open, completed }

class PlanTask {
  PlanTask({
    required this.title,
    required this.priority,
    this.targetDate,
  });

  final String title;
  final PlanPriority priority;
  final DateTime? targetDate;
  bool completed = false;
}

class PlansScreen extends StatefulWidget {
  const PlansScreen({super.key});

  @override
  State<PlansScreen> createState() => _PlansScreenState();
}

class _PlansScreenState extends State<PlansScreen> {
  final List<PlanTask> _tasks = [];
  PlanFilter _filter = PlanFilter.all;

  int get _openCount => _tasks.where((task) => !task.completed).length;

  List<PlanTask> get _visibleTasks {
    switch (_filter) {
      case PlanFilter.open:
        return _tasks.where((task) => !task.completed).toList();
      case PlanFilter.completed:
        return _tasks.where((task) => task.completed).toList();
      case PlanFilter.all:
        return List<PlanTask>.from(_tasks);
    }
  }

  Future<void> _addTask() async {
    final controller = TextEditingController();
    var priority = PlanPriority.normal;
    DateTime? targetDate;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, updateSheet) {
          return SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                8,
                20,
                20 + MediaQuery.viewInsetsOf(sheetContext).bottom,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'New task',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: controller,
                      textCapitalization: TextCapitalization.sentences,
                      maxLength: 120,
                      decoration: const InputDecoration(
                        labelText: 'What needs doing?',
                        hintText: 'e.g. Plan our next video call',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text('Priority', style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: PlanPriority.values.map((value) {
                        return ChoiceChip(
                          label: Text(_priorityLabel(value)),
                          selected: priority == value,
                          onSelected: (_) => updateSheet(() => priority = value),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.event_outlined),
                      label: Text(targetDate == null
                          ? 'Add optional target date'
                          : 'Target: ${_formatDate(targetDate!)}'),
                      onPressed: () async {
                        final date = await showDatePicker(
                          context: sheetContext,
                          initialDate: targetDate ?? DateTime.now(),
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2100),
                        );
                        if (date != null) {
                          updateSheet(() => targetDate = date);
                        }
                      },
                    ),
                    if (targetDate != null)
                      TextButton(
                        onPressed: () => updateSheet(() => targetDate = null),
                        child: const Text('Remove target date'),
                      ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () {
                          final title = controller.text.trim();
                          if (title.isEmpty) return;
                          setState(() {
                            _tasks.add(PlanTask(
                              title: title,
                              priority: priority,
                              targetDate: targetDate,
                            ));
                          });
                          Navigator.of(sheetContext).pop();
                        },
                        child: const Text('Save task'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
    controller.dispose();
  }

  String _priorityLabel(PlanPriority priority) {
    switch (priority) {
      case PlanPriority.low:
        return 'Low';
      case PlanPriority.normal:
        return 'Normal';
      case PlanPriority.high:
        return 'High';
    }
  }

  String _formatDate(DateTime date) => '${date.day}/${date.month}/${date.year}';

  @override
  Widget build(BuildContext context) {
    final shown = _visibleTasks;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'Plans & tasks',
          style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          _tasks.isEmpty
              ? 'Keep the little things moving forward.'
              : '$_openCount open • ${_tasks.length} total',
          style: TextStyle(color: Colors.blueGrey.shade700),
        ),
        const SizedBox(height: 16),
        Card(
          elevation: 0,
          color: const Color(0xFFFFF3DB),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline_rounded, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Preview only: tasks are kept in this app session. '
                    'Saving and partner sync are coming later.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _addTask,
            icon: const Icon(Icons.add),
            label: const Text('Add task'),
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          children: [
            _filterChip(PlanFilter.all, 'All'),
            _filterChip(PlanFilter.open, 'Open'),
            _filterChip(PlanFilter.completed, 'Completed'),
          ],
        ),
        const SizedBox(height: 12),
        if (shown.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 52),
            child: Column(
              children: [
                Icon(Icons.task_alt_outlined,
                    size: 54, color: Colors.blueGrey.shade300),
                const SizedBox(height: 12),
                Text(
                  _tasks.isEmpty ? 'No tasks yet' : 'Nothing in this filter',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                const Text('Add something you want to plan together.'),
              ],
            ),
          )
        else
          ...shown.map(_taskTile),
      ],
    );
  }

  Widget _filterChip(PlanFilter filter, String label) {
    return ChoiceChip(
      label: Text(label),
      selected: _filter == filter,
      onSelected: (_) => setState(() => _filter = filter),
    );
  }

  Widget _taskTile(PlanTask task) {
    final details = [
      _priorityLabel(task.priority) + ' priority',
      if (task.targetDate != null) 'Target ${_formatDate(task.targetDate!)}',
    ].join(' • ');

    return Card(
      elevation: 0,
      child: CheckboxListTile(
        value: task.completed,
        onChanged: (value) => setState(() => task.completed = value ?? false),
        controlAffinity: ListTileControlAffinity.leading,
        title: Text(
          task.title,
          style: TextStyle(
            decoration: task.completed ? TextDecoration.lineThrough : null,
            color: task.completed ? Colors.blueGrey : null,
          ),
        ),
        subtitle: Text(details),
        secondary: IconButton(
          tooltip: 'Delete task',
          icon: const Icon(Icons.delete_outline),
          onPressed: () => setState(() => _tasks.remove(task)),
        ),
      ),
    );
  }
}
