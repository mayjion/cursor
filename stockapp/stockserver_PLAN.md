# stockserver 投资观察后台 — 功能模块与实现规划

> 目标：将「投资观察」核心逻辑放到常驻 Web 服务；浏览器通过 `http://IP:PORT` 访问。  
> 新代码目录：`/home/may/work/cursor/stockapp/stockserver`  
> 现有 `stock_monitor_app` 本地业务逻辑废弃重做；App 后续仅作客户端访问同一后端。

---

## 0. 数据原则（硬约束）

**一律不使用付费数据源**（Wind / iFinD / Tushare Pro 付费档 / 商业资讯 API 等一律不接入）。

| 原则 | 做法 |
|---|---|
| 默认 | 仅公开可抓取 / 免费接口 |
| 重要缺口 | 用**替代指标**或**公开页面/公告**间接估算，不强求原文档字段 |
| 缺失 | 因子标为 `stub`，评分时剔除并重新归一化权重，页面标注「暂无公开源」 |
| 频率 | 遵守公开接口限频，采集加间隔与本地缓存，避免封禁 |
| 合规 | 仅个人研究；页面固定免责声明；不转售数据 |

### 0.1 公开主数据源（计划接入）

| 用途 | 公开来源 | 备注 |
|---|---|---|
| A 股 / ETF 行情、K 线 | 东方财富公开接口（沿用现 App 经验） | 主力 |
| ETF 列表、份额、净申购 | 东财基金/ETF 相关公开接口 | 加仓规则基础 |
| 估值 PE/PB（部分指数/ETF） | 东财、新浪财经公开页/接口；中证指数公司官网披露 | 能拿到再算百分位 |
| 宏观（通胀、利率、PMI 等） | 国家统计局、中国人民银行、FRED（美）公开数据 | AkShare 封装或直连 |
| 美股指数/个股联动 | Yahoo Finance / Stooq 等免费源 | 外盘联动代理，不保证稳定 |
| 商品/汇率 | 公开行情接口或东财/新浪 | 有色、能源外部因子代理 |
| 政策/事件 | 政府网站公开文件 + 标题关键词规则 | **不做**付费舆情；首期 `config/events.yaml` 规则/人工 |

### 0.2 「重要数据」的免费替代思路（示例）

| 原设想（常付费） | 免费替代 |
|---|---|
| Wind 重仓股营收/利润增速 | 东财/巨潮公开财报；或 ETF 重仓列表 + 成分股公开财报同比 |
| SEMI/IDC/Gartner 行业报告 | 暂 `stub`；或统计局/海关公开产量、出口同比作粗糙代理 |
| 专业资金流拥挤度 | ETF/板块成交额占全市场比例的历史分位 |
| 北向资金 | 公开接口可用则接；否则用宽基成交额/涨跌家数代理 |
| 费城半导体 / XBI | Yahoo 等免费行情 |
| 医保谈判/产业招标细节 | 公开新闻标题关键词 + 手动事件表 |

**结论**：评分主干 = 量价 + 份额资金 + 可得估值 + 少量外盘/宏观公开序列；赛道叙事能替则替，不能替则占位，**绝不付费**。

---

## 1. 目标架构

```
浏览器 / 日后 App(WebView)
        │
        ▼
┌───────────────────┐
│  FastAPI stockserver │  ← 常驻 0.0.0.0:8787
│  · REST API         │
│  · 静态/模板网页     │
│  · 定时采集与评分    │
└─────────┬─────────┘
          │
    ┌─────┴─────┐
    ▼           ▼
 SQLite      仅公开数据源
 (可换 PG)   东财 / AkShare免费 / FRED / Yahoo 等
```

**可移植原则**

- 纯 Python 3.11+，`pip`/`uv` 或 Docker 一键跑
- 配置与数据与代码分离（`config/` + `data/`）
- 不依赖本机 Flutter / Android SDK
- MacOS / Linux 同一套启动命令

---

## 2. 技术选型

| 层 | 选型 | 说明 |
|---|---|---|
| API | FastAPI + Uvicorn | 单进程常驻即可 |
| 网页（首期） | Jinja2 模板 + 少量 JS（Chart.js） | 少构建、易部署 |
| 调度 | APScheduler（进程内） | 单机够用 |
| 存储 | SQLite 默认 / 可切 PostgreSQL | 拷贝 `data/` 即可迁移 |
| 配置 | `config/*.yaml` + `.env` | 改池不改代码 |
| 部署 | Docker + `scripts/run.sh` | Mac/Linux 一致 |
| 采集 | `httpx` + 可选 AkShare（免费） | **禁止**付费 Key 成为核心路径必需项 |

**明确不做**：Wind / iFinD / 任何付费行情与资讯、商用 NLP、Black-Litterman、微服务拆分。

---

## 3. 功能模块

### M1 配置与 ETF 池（10+3）

- `config/etf_universe.yaml`：10 高景气 + 3 稳健
- 每个因子标注：`source: public | proxy | stub`（禁止出现 paid）
- API：`GET /api/universe`

### M2 数据采集（仅公开）

- 日/周 K、快照、ETF 份额与净申购、公开估值、免费宏观/外盘
- 限频 + 本地缓存；`make collect-once`
- **验收**：无任何付费账号时，日更仍能跑通

### M3 因子与评分

**主干（均可公开）**：动量、波动回撤、成交拥挤代理、净申购突发、PE/PB 百分位（可得时）、外盘联动（可选）

**输出**：0–100 分 + 三色灯；市场温度；高景气/稳健大类比例；赛道轮动（单票 2%–20%）

### M4 预警

- 涨幅/拥挤/评分连降 + `events.yaml` 公开事件规则

### M5 API 与网页

- `/` 仪表盘、`/etf/{code}` 详情、`/alerts`、对应 `/api/*`、同端口 `8787`

### M6 运维

- Docker / `run.sh`；README 中付费 API Key **不得**列为必需

---

## 4. 目录结构

```
stockserver/
  README.md
  pyproject.toml
  Dockerfile
  docker-compose.yml
  .env.example              # 仅端口/代理等；无付费 key
  config/
    settings.yaml
    etf_universe.yaml
    events.yaml
  app/
    main.py
    collectors/             # 仅 public
    factors/
    scoring/
    allocation/
    api/
    web/
    jobs/
    db/
  data/
  scripts/
```

---

## 5. 分阶段

| 阶段 | 交付 | 状态 |
|---|---|---|
| A | 骨架 + 公开行情仪表盘网页 | ✅ |
| B | 公开日 K/份额 + 评分灯色 | ✅ |
| C | 净申购/轮动/代理外部因子/预警（仍全免费） | ✅ |
| C+ | 择时加/减仓：点位回测门控（禁止未来函数） | ✅ |
| D | App WebView 壳 | 下一步 |

---

## 6. 与旧 App

废弃端上 Hive 主路径；可借鉴东财公开接口字段；UI 不迁移。

---

## 7. 进度

1. ✅ 创建 `stockserver` 骨架  
2. ✅ 写入 10+3 池（因子标注 public/proxy/stub）  
3. ✅ 公开行情仪表盘（Phase A）  
4. ✅ 日 K / 份额 / 因子评分 / 定时任务（Phase B）  
5. ✅ Phase C：赛道轮动、预警、东财美股外盘代理（Yahoo 境内不可用时回退 A 股相关 ETF）  
6. ✅ 择时主路径：无未来函数点位回测门控 + 加仓→减仓收益验证后再推今日行动  
7. ⏳ Phase D：App WebView 壳（可选）  
