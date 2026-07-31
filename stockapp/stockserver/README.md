# stockserver — 投资观察后台（Phase C+ 择时）

常驻 Web 服务：公开行情 + 评分灯色 + 赛道轮动 + 预警。  
**零付费数据源**（东方财富 A 股/ETF + 东财美股公开日K 代理）。

## 快速启动（Linux / macOS）

```bash
cd stockserver
chmod +x scripts/run.sh scripts/collect_once.sh
./scripts/run.sh
```

浏览器打开：

- 本机：http://127.0.0.1:8787
- 局域网：http://\<本机IP\>:8787
- 预警页：http://127.0.0.1:8787/alerts
- App 发现：UDP `48787` 广播 + `/api/health`（手机「搜索局域网」）

## Docker

```bash
docker compose up -d --build
```

## 主要接口

| 路径 | 说明 |
|---|---|
| `GET /` | 网页仪表盘（温度/轮动/预警摘要） |
| `GET /alerts` | 预警中心 |
| `GET /etf/{code}` | ETF 详情（因子 + 仓位建议） |
| `GET /api/health` | 健康检查 |
| `GET /api/universe` | 10+3 池配置 |
| `GET /api/dashboard?refresh=1` | JSON 仪表盘 |
| `GET /api/allocation` | 赛道轮动权重 |
| `GET /api/timing` | 今日择时行动（受回测门控） |
| `GET /api/timing/backtest?window=252` | 半年/一年加→减交易与指标 |
| `POST /api/admin/collect` | 全量采集评分 |

## 配置

- `config/etf_universe.yaml` — ETF 池与因子（`public` / `proxy` / `stub`）
- `config/settings.yaml` — 端口、限频、缓存 TTL
- `config/events.yaml` — 手工事件（并入预警）

## 数据策略

- 禁止 Wind / iFinD / 付费 Tushare 等
- **Phase A**：实时行情快照
- **Phase B**：日 K + ETF 份额/净申购 + 通用因子加权评分
- **Phase C**：东财美股外盘代理因子、赛道轮动参考、规则预警 + events.yaml
- **Phase C+**：点位择时（无未来函数回测）；未达门控不推加仓；满仓权重降为折叠参考

## 手动全量采集并评分

```bash
./scripts/collect_once.sh
# 或
curl -X POST http://127.0.0.1:8787/api/admin/collect
```

定时任务：每个交易日 11:35 / 16:10（Asia/Shanghai）自动全量采集评分。

## 免责声明

仅供个人研究学习，不构成投资建议。
