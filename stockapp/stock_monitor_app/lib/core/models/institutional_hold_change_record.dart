/// 机构/股东增减持明细记录。
class InstitutionalHoldChangeRecord {
  const InstitutionalHoldChangeRecord({
    required this.holderName,
    required this.direction,
    this.tradeDate,
    this.noticeDate,
    this.reportDate,
    this.changeShares,
    this.changeAmount,
    this.tradePrice,
    this.closePrice,
    this.changeRatio,
    this.market = '',
    this.source = '',
  });

  /// 股东/机构名称
  final String holderName;

  /// 增持 / 减持 / 新进 / 不变 等
  final String direction;

  /// 变动日期（优先交易日）
  final String? tradeDate;

  /// 公告日
  final String? noticeDate;

  /// 报告期（季报十大股东变动）
  final String? reportDate;

  /// 增减持股数（股）；无法获取则为 null
  final double? changeShares;

  /// 增减持金额（元）；无法获取则为 null
  final double? changeAmount;

  /// 增减持成交均价（元）；无法获取则为 null
  final double? tradePrice;

  /// 当日/期末收盘价（元）；无法获取则为 null
  final double? closePrice;

  /// 变动比例（%）
  final double? changeRatio;

  /// 交易市场/方式（如大宗交易）
  final String market;

  /// 数据来源标签
  final String source;

  String get displayDate {
    final raw = tradeDate ?? noticeDate ?? reportDate;
    if (raw == null || raw.isEmpty) return '';
    return raw.length >= 10 ? raw.substring(0, 10) : raw;
  }
}
