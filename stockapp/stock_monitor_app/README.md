# 星沉大海 (stock_monitor_app)

基于 Flutter 的 Android 投资分析应用：可对接局域网 **stockserver** 推荐池，也可在无服务端时本地扫描。

## 功能

- **服务端对接**：同一 Wi‑Fi 下自动搜索 stockserver；也可手动填写电脑 IP（端口默认 **8787**）
- **自选上云**：自选列表与加入价保存在 stockserver；App 展示加入后收益率（均收益/胜率/单票收益）
- **今日推荐**：已连接服务端时展示服务端 A 股初选池；未连接时可本地扫描
- **夜间扫描**：设置页开启定时任务（默认 02:00，仅工作日），或手动「立即扫描」
- **资讯洞察 / 自选股 / 个股详情**：沿用本地能力

## 运行

```bash
# 电脑端服务
cd ../stockserver && ./scripts/run.sh

# 手机 App
cd stock_monitor_app
flutter pub get
flutter run
```

## 使用说明

1. 电脑启动 stockserver（默认 `http://0.0.0.0:8787`）
2. 手机与电脑连同一 Wi‑Fi → **设置 → 搜索局域网** → 选中服务端
3. 不在同一局域网：在设置里填写电脑 IP，端口保持 **8787**，点「保存并连接」
4. **首次连接**需输入密码（默认 `sprite123`），验证通过后本机记住，换 IP 会重新要求输入
4. 连接成功后，「推荐」Tab 显示服务端股票池；未连接时仍可用本地扫描

## 架构

- Flutter: `Riverpod` + `go_router` + `Hive`
- 本地引擎: `lib/core/engine/`（评分 + 扫描编排）
- 数据源: 东方财富公开 API（`EastmoneyClient`）
- 后台: `workmanager`（定时）+ `flutter_foreground_task`（扫描保活）

## 免责声明

数据来源于东方财富公开接口，本地扫描与加减仓信号仅供个人记录与参考，不构成任何投资建议。
