import 'package:flutter_test/flutter_test.dart';
import 'package:stock_monitor_app/core/engine/valuation_scorer.dart';
import 'package:stock_monitor_app/core/models/institutional_hold_summary.dart';
import 'package:stock_monitor_app/core/models/market_space_context.dart';
import 'package:stock_monitor_app/core/models/recommendation.dart';
import 'package:stock_monitor_app/core/models/research_summary.dart';
import 'package:stock_monitor_app/core/models/stock_snapshot.dart';

void main() {
  test('passesHardFilter excludes ST and low liquidity', () {
    final ok = StockSnapshot(code: '600519', name: '茅台', avgAmount: 1e8, peTtm: 25);
    final st = StockSnapshot(code: '600001', name: 'ST测试', avgAmount: 1e8, isSt: true);
    final low = StockSnapshot(code: '000001', name: '测试', avgAmount: 1e6);
    expect(passesHardFilter(ok), isTrue);
    expect(passesHardFilter(st), isFalse);
    expect(passesHardFilter(low), isFalse);
  });

  test('scoreValuation favors low PE within industry', () {
    final snapshots = [
      StockSnapshot(code: '600519', name: '茅台', industry: '白酒', peTtm: 20, pb: 5),
      StockSnapshot(code: '000858', name: '五粮液', industry: '白酒', peTtm: 15, pb: 4),
    ];
    final stats = computeIndustryPePb(snapshots);
    final target = StockSnapshot(code: '000858', name: '五粮液', industry: '白酒', peTtm: 10, pb: 3);
    final result = scoreValuation(target, stats);
    expect(result.score, greaterThan(50));
    expect(result.reasons, isNotEmpty);
  });

  test('scoreHistoricalGrowth rewards high ROE and revenue growth', () {
    final snap = StockSnapshot(
      code: '600519',
      name: '茅台',
      roe: 25,
      revenueGrowth: 18,
      netProfitGrowth: 15,
    );
    final result = scoreHistoricalGrowth(snap);
    expect(result.score, greaterThan(70));
    expect(result.reasons.any((r) => r.contains('ROE')), isTrue);
  });

  test('scoreGrowth merges research consensus', () {
    const research = ResearchSummary(
      reportCount: 5,
      avgRatingScore: 85,
      epsGrowthRate: 0.15,
      topRating: '买入',
    );
    final snap = StockSnapshot(code: '300750', name: '宁德', roe: 12, revenueGrowth: 8);
    final result = scoreGrowth(snap, research: research);
    expect(result.score, greaterThan(60));
    expect(result.reasons.any((r) => r.contains('研报')), isTrue);
  });

  test('scoreMarketSpace favors hot industry board', () {
    const context = MarketSpaceContext(
      industryBoards: [
        IndustryItem(industry: '电池', changePercent: 4.5, mainNetInflow: 1e9),
        IndustryItem(industry: '银行', changePercent: -1.2, mainNetInflow: -1e8),
      ],
      hotKeywords: {'电池'},
    );
    final snap = StockSnapshot(
      code: '300750',
      name: '宁德',
      industry: '电池',
      concepts: ['电池', '新能源'],
    );
    final result = scoreMarketSpace(snap, context);
    expect(result.score, greaterThan(65));
  });

  test('scoreInstitution rewards fund increase', () {
    const summary = InstitutionalHoldSummary(
      quarterChangeRate: 8,
      summaryAction: '增仓',
      increasingTypes: ['基金', '保险'],
      newHolderCount: 1,
      increaseHolderCount: 2,
      reasons: ['基金、保险季度增仓'],
    );
    final result = scoreInstitution(summary);
    expect(result.score, greaterThan(75));
  });

  test('GARP composite weights growth over pure low PE', () {
    final cheapLowGrowth = compositeScoreGarp(
      valuation: 90,
      growth: 40,
      space: 45,
      institution: 50,
      capital: 50,
      technical: 50,
    );
    final balanced = compositeScoreGarp(
      valuation: 70,
      growth: 80,
      space: 75,
      institution: 70,
      capital: 55,
      technical: 55,
    );
    expect(balanced, greaterThan(cheapLowGrowth));
  });

  test('scoreGrowth without research uses historical only', () {
    final snap = StockSnapshot(code: '600519', name: '茅台', roe: 20, revenueGrowth: 12);
    final result = scoreGrowth(snap);
    expect(result.score, greaterThan(55));
  });
}
