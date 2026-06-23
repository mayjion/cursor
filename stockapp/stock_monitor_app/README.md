# 自选股加减仓信号 (stock_monitor_app)

基于 Flutter 的 Android 自选股应用：监控东方财富资金流向与 K 线数据，基于 30 日量价规则生成加减仓信号，并在趋势逆转为左侧下跌时高优先级提醒。

## 功能

- 添加/管理自选股
- 下拉刷新拉取近 6 个月 OHLCV + 资金流
- **30 日加减仓信号**：加仓 / 减仓 / 持有 / 只持底仓
- **趋势逆转提醒**：早期预警 / 确认反转 / 深跌保护（共振评分）
- 信号历史与分布统计
- 个股详情：30 日分析卡、共振信号、ATR 止损参考、资金流图表
- 交易日 15:05 本地收盘提醒
- 趋势逆转高优先级本地推送（可设置开关）

## 运行

```bash
cd stock_monitor_app
flutter pub get
flutter test
flutter run
```

## 架构

`Riverpod` + `go_router` + `Hive` + `features/core` 分层。

核心模块：
- `lib/core/position/position_signal_analyzer.dart` — 30 日加减规则
- `lib/core/position/downtrend_detector.dart` — 左侧下跌共振检测
- `lib/core/position/technical_indicators.dart` — MA/RSI/ADX/MACD/ATR

## 免责声明

数据来源于东方财富公开接口，加减仓信号仅供个人记录与参考，不构成任何投资建议。
