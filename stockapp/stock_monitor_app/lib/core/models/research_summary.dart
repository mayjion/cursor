class ResearchSummary {
  const ResearchSummary({
    this.reportCount = 0,
    this.avgRatingScore = 50,
    this.epsGrowthRate,
    this.avgPredictPe,
    this.topRating = '',
    this.indvInduCode = '',
  });

  final int reportCount;
  final double avgRatingScore;
  final double? epsGrowthRate;
  final double? avgPredictPe;
  final String topRating;
  final String indvInduCode;

  static double ratingToScore(String rating) {
    if (rating.contains('买入') || rating.contains('强烈推荐')) return 90;
    if (rating.contains('增持') || rating.contains('推荐')) return 75;
    if (rating.contains('中性') || rating.contains('持有')) return 50;
    if (rating.contains('减持') || rating.contains('卖出')) return 30;
    return 50;
  }
}
