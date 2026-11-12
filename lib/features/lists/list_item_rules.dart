/// Pure validation for shopping/checklist entries.
class ListItemRules {
  const ListItemRules._();

  static bool isValid({
    required String label,
    required double quantity,
    required String unit,
    required String note,
  }) =>
      label.trim().isNotEmpty &&
      label.trim().length <= 200 &&
      quantity.isFinite &&
      quantity > 0 &&
      quantity <= 99999 &&
      unit.length <= 24 &&
      note.length <= 500;
}
