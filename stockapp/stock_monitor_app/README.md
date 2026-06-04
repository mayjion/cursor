# 自选股监控 (stock_monitor_app)

基于 Flutter 的 Android 自选股应用：监控东方财富资金流向，按规则推测次日涨跌，记录并统计命中率。

## 功能

- 添加/管理自选股
- 下拉刷新拉取资金流向（东方财富 API）
- 拉取近 **6 个月**（约126个交易日）收盘价、涨跌幅、主力/散户净流入
- 综合 **最新一日主力 vs 散户**、6 月价格趋势、20 日资金累计、历史同模式胜率生成推测
- 次日自动校验推测（刷新时）
- 命中率统计与分股图表
- 交易日 15:05 本地收盘提醒

## 运行

```bash
cd stock_monitor_app
flutter pub get
flutter run
```

## 架构

与 `cursor/app/iot_serial_app` 一致：`Riverpod` + `go_router` + `Hive` + `features/core` 分层。

## 免责声明

数据来源于东方财富公开接口，推测结果仅供个人记录，不构成投资建议。
