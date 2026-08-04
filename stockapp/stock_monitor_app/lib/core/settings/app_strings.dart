import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/position_signal.dart';
import 'app_settings.dart';

class AppStrings {
  const AppStrings(this.locale);

  final Locale locale;
  bool get isZh => locale.languageCode == 'zh';

  String get navRecommendations => isZh ? '推荐' : 'Picks';
  String get navInsights => isZh ? '资讯' : 'Insights';
  String get navOverview => isZh ? '总览' : 'Overview';
  String get navWatchlist => isZh ? '自选' : 'Watchlist';
  String get navStats => isZh ? '信号' : 'Signals';
  String get navSettings => isZh ? '设置' : 'Settings';

  String get etfOverviewTitle => isZh ? 'ETF 总览' : 'ETF Overview';
  String get etfOverviewEmpty =>
      isZh ? '暂无自选 ETF，请先在自选中添加' : 'No ETF in watchlist yet';
  String get etfBuyIndex => isZh ? '购买指数' : 'Buy index';
  String get etfModelBasis => isZh ? '模型依据' : 'Model basis';
  String get etfShareSection => isZh ? '季报申购赎回与份额' : 'Quarterly flow & shares';
  String get etfDisclaimer => isZh
      ? '评分以季报「期间申购/期间赎回」为主（日频份额变动仅作辅助），基于历史统计关系，仅供参考，不构成投资建议。'
      : 'Scores primarily use quarterly apply/redeem disclosures; for reference only.';
  String get etfLatestQuarter => isZh ? '最近季报' : 'Latest quarter';
  String get etfPeriodApply => isZh ? '期间申购' : 'Period apply';
  String get etfPeriodRedeem => isZh ? '期间赎回' : 'Period redeem';
  String get etfPeriodNet => isZh ? '期间净申购' : 'Period net';
  String get etfInQuarterToDate => isZh ? '本季至今份额变动' : 'QTD share change';
  String get etfQuarterChart =>
      isZh ? '周K与季报净申购' : 'Weekly K & quarterly net';
  String get etfChartNetLegend => isZh ? '净申购(柱)' : 'Net (bars)';
  String get etfChartPriceLegend => isZh ? '周K' : 'Weekly K';
  String get etfChartUpLegend => isZh ? '涨' : 'Up';
  String get etfChartDownLegend => isZh ? '跌' : 'Down';
  String get etfSignalAdd => isZh ? '适合加仓' : 'Add now';
  String get etfSignalAddHistory => isZh ? '历史/候选' : 'History/candidate';
  String get etfSignalRisk => isZh ? '风险点' : 'Risk point';
  String get etfSignalSection => isZh ? '量价依据' : 'Flow-price signals';
  String get etfSignalEmpty =>
      isZh ? '暂无满足规则的加仓/风险点' : 'No rule-based signals yet';
  String get etfSignalRuleHint => isZh
      ? '加仓判断条件：①底条件：当季净申购≥上一季2倍（上季为正且占份额≥0.3%）；'
          '②计胜：预测点后约一季涨幅>15%（全池>30%过稀无法成规则）；'
          '③辅助条件由全自选历史胜出样本提炼；'
          '④完整规则须在全部自选ETF不同历史阶段回测胜率>80%才用于当下预测；'
          '⑤近一季窗口内命中已校验规则→适合加仓并置顶。'
      : 'Add rules: ① QoQ net ≥2×; ② win if +1Q return >15%; '
          '③ aux from pool; ④ pool win-rate >80%; ⑤ recent hits rank first.';
  String etfSignalWinRateLine(double? rate, int hits, int samples) {
    if (samples <= 0) {
      return isZh
          ? '全池规则胜率：样本不足'
          : 'Pool rule win rate: insufficient samples';
    }
    final pct = ((rate ?? 0) * 100).toStringAsFixed(0);
    return isZh
        ? '全池加仓规则胜率 $pct%（$hits/$samples）'
        : 'Pool rule win rate $pct% ($hits/$samples)';
  }

  String get etfAddFitness => isZh ? '加仓适配度' : 'Add fitness';
  String get watchlistStocks => isZh ? '股票' : 'Stocks';
  String get watchlistEtfs => isZh ? 'ETF' : 'ETF';
  String get addEtf => isZh ? '添加 ETF' : 'Add ETF';
  String get etfCodeHint => isZh ? '例如 510300' : 'e.g. 510300';
  String get bulkAddEtf => isZh ? '一键添加 ETF' : 'Bulk add ETFs';
  String get bulkAddEtfHint => isZh
      ? '按基金规模筛选场内 ETF，已在自选中的会自动跳过'
      : 'Filter listed ETFs by AUM; existing ones are skipped';
  String get bulkAddEtfMinScale => isZh ? '最低规模（亿元）' : 'Min AUM (亿元)';
  String get bulkAddEtfPreview => isZh ? '预览匹配' : 'Preview';
  String get bulkAddEtfConfirm => isZh ? '确认添加' : 'Add all';
  String get bulkAddEtfMatched => isZh ? '匹配' : 'Matched';
  String get bulkAddEtfAdded => isZh ? '新增' : 'Added';
  String get bulkAddEtfSkipped => isZh ? '已存在跳过' : 'Skipped';
  String bulkAddEtfDone({
    required int matched,
    required int added,
    required int skipped,
  }) =>
      isZh
          ? '匹配 $matched 只，新增 $added 只，跳过 $skipped 只'
          : 'Matched $matched, added $added, skipped $skipped';
  String get bulkAddEtfLoading => isZh ? '正在拉取 ETF 列表…' : 'Fetching ETFs…';
  String get bulkAddEtfAdding => isZh ? '正在写入自选…' : 'Saving…';
  String get clearAllEtfs => isZh ? '清空 ETF' : 'Clear ETFs';
  String get clearAllEtfsConfirm => isZh
      ? '确定清空全部自选 ETF？此操作不可撤销。'
      : 'Clear all watchlist ETFs? This cannot be undone.';
  String clearAllEtfsDone(int count) =>
      isZh ? '已清空 $count 只 ETF' : 'Cleared $count ETFs';
  String etfSyncProgress(int current, int total) =>
      isZh ? '后台更新 $current/$total' : 'Updating $current/$total';
  String get etfSyncStarted =>
      isZh ? '已在后台更新（锁屏可继续）；今日已拉过的会跳过' : 'Updating in background';
  String get etfSyncDone => isZh ? 'ETF 评分已全部更新' : 'ETF scores updated';
  String etfSyncSummary({required int fetched, required int skipped}) => isZh
      ? '完成：新拉 $fetched 只，今日已缓存跳过 $skipped 只'
      : 'Done: fetched $fetched, skipped $skipped (cached today)';
  String get etfForceRefreshHint =>
      isZh ? '下拉可强制重新拉取本只' : 'Pull to force refresh this ETF';

  String get recTitle => isZh ? '今日低估推荐' : "Today's Picks";
  String get recEmpty =>
      isZh ? '暂无推荐，请开启扫描或手动运行' : 'No picks yet, run a scan';
  String get recDate => isZh ? '推荐日期' : 'Date';
  String get addToWatchlist => isZh ? '加入自选' : 'Add to watchlist';
  String get addedToWatchlist => isZh ? '已加入自选' : 'Added to watchlist';
  String get alreadyInWatchlist => isZh ? '已在自选中' : 'Already in watchlist';
  String get removeFromWatchlist => isZh ? '移出自选' : 'Remove';
  String get scoreValuation => isZh ? '估值' : 'Value';
  String get scoreQuality => isZh ? '质量' : 'Quality';
  String get scoreGrowth => isZh ? '成长' : 'Growth';
  String get scoreSpace => isZh ? '空间' : 'Space';
  String get scoreInstitution => isZh ? '机构' : 'Inst.';
  String get scoreMomentum => isZh ? '动量' : 'Mom.';
  String get researchConsensus => isZh ? '研报共识' : 'Research';
  String get industryOutlook => isZh ? '行业景气' : 'Industry';
  String get institutionHoldChange => isZh ? '机构持股' : 'Inst. Hold';
  String get institutionHoldRecords =>
      isZh ? '股东/高管增减持记录' : 'Holder & executive changes';
  String get institutionHoldRecordsHint => isZh
      ? '含股东增减持公告、董监高增减持、十大流通股东变动'
      : 'Announcements, executives, and top shareholders';
  String get holdChangeDate => isZh ? '时间' : 'Date';
  String get holdChangeAmount => isZh ? '增减持金额' : 'Amount';
  String get holdChangePrice => isZh ? '增减持价格' : 'Price';
  String get holdChangeShares => isZh ? '增减持股数' : 'Shares';
  String get holdChangeDirection => isZh ? '方向' : 'Side';
  String get holdChangeHolder => isZh ? '股东/机构' : 'Holder';
  String get emptyValue => '-';
  String get garpDisclaimer => isZh
      ? '推荐基于估值、成长、行业空间、研报共识与机构持股变动的综合评分，仅供参考。'
      : 'Picks use valuation, growth, space, research and institutional scores. For reference only.';
  String get scoreCapital => isZh ? '资金' : 'Flow';
  String get scoreTechnical => isZh ? '技术' : 'Tech';
  String get dividendYield => isZh ? '股息' : 'Div';
  String get apiError => isZh ? '暂无本地推荐数据' : 'No local recommendations';
  String get retry => isZh ? '重试' : 'Retry';
  String get noData => isZh ? '暂无数据' : 'No data';
  String get runScanNow => isZh ? '立即扫描' : 'Scan now';
  String get nightScanSection => isZh ? '夜间扫描' : 'Night scan';
  String get nightScanSubtitle =>
      isZh ? '在设定时间自动扫描全市场（建议充电+WiFi）' : 'Auto scan at scheduled time';
  String get scanTimeSection => isZh ? '扫描时间' : 'Scan time';
  String get scanRunning => isZh ? '正在扫描...' : 'Scanning...';
  String get scanLastUpdate => isZh ? '上次更新' : 'Last update';
  String get scanDuration => isZh ? '耗时' : 'Duration';
  String get scanHint => isZh
      ? '扫描约需15-30分钟，期间请保持网络连接。系统将可能延迟0-30分钟触发。'
      : 'Scan takes 15-30 min. Trigger may be delayed by system.';
  String get batteryOptimizeTitle => isZh ? '电池优化' : 'Battery optimization';
  String get batteryOptimizeMessage => isZh
      ? '为提高夜间扫描成功率，请将本应用加入电池优化白名单。'
      : 'Add this app to battery optimization whitelist for reliable night scans.';
  String get openSettings => isZh ? '去设置' : 'Open settings';
  String get cancelScan => isZh ? '取消扫描' : 'Cancel scan';

  String get insightsTitle => isZh ? '资讯洞察' : 'Market Insights';
  String get dailyDigest => isZh ? '每日简报' : 'Daily Digest';
  String get industrySection => isZh ? '行业动态' : 'Industries';
  String get newsSection => isZh ? '财经资讯' : 'News';
  String get keyEvents => isZh ? '重点事件' : 'Key Events';

  String get tabOverview => isZh ? '概览' : 'Overview';
  String get tabFundamentals => isZh ? '基本面' : 'Fundamentals';
  String get tabTechnical => isZh ? '技术面' : 'Technical';
  String get tabNews => isZh ? '资讯' : 'News';
  String get tabAnalysis => isZh ? '投研' : 'Analysis';
  String get analysisNeedServer =>
      isZh ? '投研报告需连接 stockserver 后查看' : 'Connect stockserver for analysis';
  String get analysisRefresh => isZh ? '刷新报告' : 'Refresh report';
  String get analysisSwot => isZh ? 'SWOT' : 'SWOT';
  String get analysisRating => isZh ? '综合评级' : 'Rating';
  String get analysisStance => isZh ? '操作参考' : 'Stance';
  String get analysisDisclaimer =>
      isZh ? '仅供研究参考，不构成投资建议' : 'For research only, not advice';
  String get conceptsSection => isZh ? '概念题材' : 'Themes';
  String get companyProfileSection => isZh ? '公司简介' : 'Profile';
  String get refreshNews => isZh ? '刷新资讯' : 'Refresh news';
  String get valuationLabel => isZh ? '估值标签' : 'Valuation';
  String get compositeScore => isZh ? '综合评分' : 'Score';
  String get recommendationScore => isZh ? '推荐评分' : 'Rec. Score';
  String get linkedSignal => isZh ? '关联信号' : 'Linked Signal';
  String get historyPerformance => isZh ? '历史推荐表现' : 'History Performance';
  String get return5d => isZh ? '5日' : '5D';
  String get return20d => isZh ? '20日' : '20D';
  String get return60d => isZh ? '60日' : '60D';

  String get recNotifySection => isZh ? '推荐更新提醒' : 'Recommendation alerts';
  String get recNotifySubtitle =>
      isZh ? '扫描完成后推送今日低估推荐' : 'Notify when scan completes';
  String get recLimitSection => isZh ? '推荐数量' : 'Recommendation count';
  String get filterSection => isZh ? '筛选偏好' : 'Filters';
  String get excludeStar => isZh ? '排除科创板' : 'Exclude STAR market';
  String get marketCapAll => isZh ? '全部' : 'All';
  String get marketCapLarge => isZh ? '大盘' : 'Large';
  String get marketCapMid => isZh ? '中盘' : 'Mid';
  String get marketCapSmall => isZh ? '小盘' : 'Small';

  String get watchlistTitle => isZh ? '自选股' : 'Watchlist';
  String get addStock => isZh ? '添加自选' : 'Add stock';
  String get emptyWatchlist => isZh ? '还没有自选股' : 'No stocks yet';
  String get emptyWatchlistHint =>
      isZh ? '添加股票后，可监控30日加减仓信号' : 'Add stocks to monitor position signals';
  String get stockCode => isZh ? '股票代码' : 'Stock code';
  String get stockCodeHint => isZh ? '例如 600519' : 'e.g. 600519';
  String get pullToRefresh => isZh ? '下拉刷新数据' : 'Pull to refresh';
  String get refreshDone => isZh ? '刷新完成' : 'Refresh done';
  String get refreshFailed => isZh ? '刷新失败' : 'Refresh failed';

  String get mainNetInflow => isZh ? '主力净流入' : 'Main net inflow';
  String get mainNetRatio => isZh ? '主力净占比' : 'Main net ratio';
  String get retailNetInflow => isZh ? '散户净流入' : 'Retail net inflow';
  String get latestPrice => isZh ? '现价' : 'Price';

  String get signalHoldBaseOnly => isZh ? '只持底仓' : 'Base only';
  String get signalHold => isZh ? '持有' : 'Hold';
  String get signalAdd => isZh ? '加仓' : 'Add';
  String get signalReduce => isZh ? '减仓' : 'Reduce';
  String get signalTrendBreak => isZh ? '下跌预警' : 'Break warning';
  String get signalTrendReversal => isZh ? '趋势逆转' : 'Reversal';

  String get analysisSection => isZh ? '30日加减仓分析' : '30-day position analysis';
  String get confidence => isZh ? '置信度' : 'Confidence';
  String get trendPhase => isZh ? '趋势相位' : 'Trend phase';
  String get phaseRightSide => isZh ? '右侧上涨' : 'Right-side up';
  String get phaseLeftSide => isZh ? '左侧下跌' : 'Left-side down';
  String get phaseNeutral => isZh ? '震荡未确认' : 'Neutral';
  String get retracePercent => isZh ? '回撤' : 'Retrace';
  String get volumeRatio => isZh ? '量比' : 'Vol ratio';
  String get atrStopLoss => isZh ? 'ATR止损参考' : 'ATR stop';
  String get resonanceSignals => isZh ? '共振信号' : 'Resonance signals';
  String get reversalBanner => isZh ? '趋势逆转警告' : 'Trend reversal warning';
  String get suggestedAction => isZh ? '建议动作' : 'Suggested action';

  String get flowChart => isZh ? '主力净流入走势' : 'Main inflow trend';
  String get historyFlowChart =>
      isZh ? '历史资金净流入' : 'Historical net inflow';
  String get intradayFlowChart =>
      isZh ? '当日资金净流入' : "Today's net inflow";
  String get chartUnitYi => isZh ? '单位：亿元' : 'Unit: 100M';
  String get chartNotEnough => isZh ? '历史数据不足' : 'Not enough history';
  String get intradayChartEmpty =>
      isZh ? '暂无当日分时数据（非交易时段或接口无数据）' : 'No intraday data';
  String get intradaySnapshotHint =>
      isZh ? '与下方当日曲线末点一致（累计净流入）' : 'Matches last point on intraday chart';
  String get signalHistory => isZh ? '信号历史' : 'Signal history';

  String get statsTitle => isZh ? '信号历史' : 'Signal history';
  String get totalSignals => isZh ? '信号总数' : 'Total signals';
  String get reversalCount => isZh ? '逆转提醒' : 'Reversals';
  String get recentChanges => isZh ? '近7日变更' : '7-day changes';
  String get perStock => isZh ? '各股最新信号' : 'Latest by stock';
  String get signalDistribution => isZh ? '信号分布' : 'Signal distribution';

  String get settingsTitle => isZh ? '设置' : 'Settings';
  String get serverSection => isZh ? '服务端连接' : 'Server';
  String get serverSubtitle => isZh
      ? '同一局域网可自动搜索；否则请手动填写电脑 IP，端口默认 8787。首次连接需输入密码'
      : 'Auto-discover on LAN, or enter PC IP (port 8787). Password required on first connect';
  String get serverEnable => isZh ? '使用 stockserver' : 'Use stockserver';
  String get serverHostLabel => isZh ? '服务端 IP / 主机名' : 'Server IP / host';
  String get serverHostHint => isZh
      ? '同网填局域网IP；异网填 Tailscale IP（如 100.x.x.x）'
      : 'LAN IP on same Wi‑Fi; Tailscale IP (100.x) otherwise';
  String get serverPortLabel => isZh ? '端口' : 'Port';
  String get serverPasswordLabel => isZh ? '连接密码' : 'Password';
  String get serverPasswordHint => isZh ? '首次连接时输入' : 'Required on first connect';
  String get serverPasswordTitle => isZh ? '输入服务端密码' : 'Enter server password';
  String get serverPasswordMessage => isZh
      ? '首次连接需验证密码，验证通过后本机将记住'
      : 'Required once; saved on this device after success';
  String get serverPasswordWrong => isZh ? '密码错误' : 'Wrong password';
  String get serverPasswordNeeded => isZh ? '请输入连接密码' : 'Enter password';
  String get serverSearchLan => isZh ? '搜索局域网' : 'Search LAN';
  String get serverSearching => isZh ? '正在搜索…' : 'Searching…';
  String get serverTest => isZh ? '测试连接' : 'Test connection';
  String get serverConnected => isZh ? '已连接' : 'Connected';
  String get serverDisconnected => isZh ? '未连接' : 'Not connected';
  String get serverFound => isZh ? '发现服务端' : 'Servers found';
  String get serverNotFound =>
      isZh ? '未发现服务端，请确认电脑已启动 stockserver 且在同一 Wi‑Fi' : 'No server found';
  String get serverSave => isZh ? '保存并连接' : 'Save & connect';
  String get serverPoolBanner =>
      isZh ? '数据来自局域网服务端推荐池' : 'From LAN stockserver pool';
  String get themeSection => isZh ? '主题' : 'Theme';
  String get themeIndigo => isZh ? '靛蓝' : 'Indigo';
  String get themeTeal => isZh ? '青绿' : 'Teal';
  String get themeOrange => isZh ? '橙色' : 'Orange';
  String get languageSection => isZh ? '语言' : 'Language';
  String get notifySection => isZh ? '收盘提醒' : 'Close reminder';
  String get notifySubtitle =>
      isZh ? '交易日 15:05 提醒刷新并查看信号' : 'Weekday 15:05 reminder to refresh';
  String get reversalNotifySection => isZh ? '趋势逆转提醒' : 'Reversal alerts';
  String get reversalNotifySubtitle =>
      isZh ? '检测到左侧下跌趋势时高优先级推送' : 'High-priority alerts on downtrend reversal';
  String get disclaimer => isZh
      ? '数据来源于东方财富公开接口，本地扫描与加减仓信号仅供个人记录与参考，不构成任何投资建议。'
      : 'Data from East Money public APIs. Local scans and signals are for personal reference only, not investment advice.';

  String signalTypeLabel(PositionSignalType type) {
    return switch (type) {
      PositionSignalType.holdBaseOnly => signalHoldBaseOnly,
      PositionSignalType.hold => signalHold,
      PositionSignalType.add => signalAdd,
      PositionSignalType.reduce => signalReduce,
      PositionSignalType.trendBreak => signalTrendBreak,
      PositionSignalType.trendReversal => signalTrendReversal,
    };
  }

  String trendPhaseLabel(TrendPhase phase) {
    return switch (phase) {
      TrendPhase.rightSideUptrend => phaseRightSide,
      TrendPhase.leftSideDowntrend => phaseLeftSide,
      TrendPhase.neutral => phaseNeutral,
    };
  }

  String severityLabel(ReversalSeverity severity) {
    return switch (severity) {
      ReversalSeverity.earlyWarning => isZh ? '早期预警' : 'Early warning',
      ReversalSeverity.confirmed => isZh ? '确认反转' : 'Confirmed',
      ReversalSeverity.deepDrop => isZh ? '深跌保护' : 'Deep drop',
    };
  }

  String get triggerConditions => isZh ? '触发条件' : 'Triggers';
  String get executeAction => isZh ? '执行建议' : 'Action';

  String triggeredSignalLabel(String id) {
    const zh = {
      // 下跌逆转
      'lowerHighsLows': '更低高低点',
      'breakSupport': '破支撑放量',
      'maDeathCross': '均线死叉',
      'belowMa30Sustained': '持续MA30下',
      'downOnVolume': '下跌放量',
      'upOnLowVolume': '反弹缩量',
      'bearishDivergence': '量价背离',
      'rsiWeak': 'RSI走弱',
      'rsiBearishDiv': 'RSI负背离',
      'adxWeak': 'ADX转弱',
      'macdBearish': 'MACD偏空',
      'bearishCandles': '大阴/吞没',
      'weeklyBreak': '周线破位',
      'invalidRebounds': '无效反弹',
      // 右侧趋势 / 加仓
      'rightSideUptrend': '右侧趋势确认',
      'healthyRetrace': '健康回调5-20%',
      'volumeShrink': '缩量回调',
      'holdSupport': '未破30日支撑',
      'rsiOversold': 'RSI超卖',
      'bullishReversal': '阳线反转',
      // 减仓
      'nearHigh30': '近30日高点',
      'volumeStagnation': '缩量滞涨',
      'rsiOverbought': 'RSI超买',
      // 只持底仓
      'belowMa': '未站稳均线',
      'noHigherHL': '无更高高低点',
      'ma30Down': 'MA30向下',
      'weeklyWeak': '周线偏弱',
      'noActionYet': '暂无触发',
    };
    if (isZh) return zh[id] ?? id;
    return id;
  }

  String formatMoney(double v) {
    final abs = v.abs();
    final sign = v < 0 ? '-' : '';
    if (abs >= 1e8) {
      return '$sign${(abs / 1e8).toStringAsFixed(2)}亿';
    }
    if (abs >= 1e4) {
      return '$sign${(abs / 1e4).toStringAsFixed(2)}万';
    }
    return '$sign${abs.toStringAsFixed(0)}';
  }

  String formatShares(double shares) {
    final abs = shares.abs();
    if (abs >= 1e8) return '${(abs / 1e8).toStringAsFixed(2)}亿股';
    if (abs >= 1e4) return '${(abs / 1e4).toStringAsFixed(2)}万股';
    return '${abs.toStringAsFixed(0)}股';
  }

  String orDash(String? value) =>
      (value == null || value.isEmpty) ? emptyValue : value;
}

final appStringsProvider = Provider<AppStrings>((ref) {
  final settings = ref.watch(appSettingsProvider);
  return AppStrings(settings.locale);
});
