import 'recommendation.dart';

class MarketSpaceContext {
  const MarketSpaceContext({
    this.industryBoards = const [],
    this.industryReportScores = const {},
    this.hotKeywords = const {},
  });

  final List<IndustryItem> industryBoards;
  final Map<String, double> industryReportScores;
  final Set<String> hotKeywords;

  static MarketSpaceContext fromIndustryBoards(List<IndustryItem> boards) {
    final sorted = [...boards]
      ..sort((a, b) =>
          (b.changePercent ?? 0).compareTo(a.changePercent ?? 0));
    final hot = sorted
        .take(10)
        .map((b) => b.industry)
        .where((e) => e.isNotEmpty)
        .toSet();
    return MarketSpaceContext(
      industryBoards: boards,
      hotKeywords: hot,
    );
  }
}
