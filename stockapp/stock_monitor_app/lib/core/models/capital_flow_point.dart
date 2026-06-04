/// 分时或用于图表的单点资金流数据。
class CapitalFlowPoint {
  const CapitalFlowPoint({
    required this.timeLabel,
    required this.mainNetInflow,
    required this.retailNetInflow,
  });

  final String timeLabel;
  final double mainNetInflow;
  final double retailNetInflow;
}
