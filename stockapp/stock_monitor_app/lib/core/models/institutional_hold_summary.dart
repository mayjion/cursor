class InstitutionalHoldSummary {
  const InstitutionalHoldSummary({
    this.quarterChangeRate,
    this.summaryAction = '',
    this.increasingTypes = const [],
    this.newHolderCount = 0,
    this.increaseHolderCount = 0,
    this.decreaseHolderCount = 0,
    this.reasons = const [],
  });

  final double? quarterChangeRate;
  final String summaryAction;
  final List<String> increasingTypes;
  final int newHolderCount;
  final int increaseHolderCount;
  final int decreaseHolderCount;
  final List<String> reasons;

  bool get hasData =>
      summaryAction.isNotEmpty ||
      increasingTypes.isNotEmpty ||
      newHolderCount > 0 ||
      increaseHolderCount > 0;
}
