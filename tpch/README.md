# tpch-bench

用一套脚本，针对 **SeekDB**（OceanBase 兼容协议）和 **MySQL** 跑 TPC-H 基准测试，便于横向对比。

只用 `mysql` 客户端，通过 `--db seekdb|mysql` 一个参数切换被测对象。

---

## 目录结构

```
tpch-bench/
├── README.md
├── .gitignore
├── ddl/
│   ├── seekdb/                  # 含 tablegroup / partition / OB hint 的 DDL
│   │   ├── 01_tables.sql
│   │   └── 02_indexes.sql
│   ├── mysql/                   # 纯 MySQL DDL（去掉 OB 专有语法）
│   │   ├── 01_tables.sql
│   │   └── 02_indexes.sql
│   └── drop_tables.sql
├── queries/                     # 22 条 TPC-H 查询（与 OB 官方 benchmark 一致）
│   └── 1.sql ... 22.sql
├── explain/                     # 22 条 EXPLAIN 版本，调优时用
│   └── 1.sql ... 22.sql
├── scripts/
│   ├── common.sh                # 公共参数解析 / mysql 命令构造
│   ├── prepare.sh               # 调用 dbgen 生成数据
│   ├── create_schema.sh         # 建库 + 建表 + 建索引
│   ├── load.sh                  # LOAD DATA LOCAL INFILE 导入
│   ├── post_load.sh             # seekdb 触发 major freeze；统一收集统计
│   ├── run.sh                   # 跑 22 条 TPC-H 查询一次
│   └── cleanup.sh               # 删表
└── dbgen/                       # 用户自行放置 dbgen 二进制 + dists.dss
```

`data/` 和 `logs/` 由脚本自动创建，已在 `.gitignore` 中排除。

---

## 准备工作

### 1. 客户端

需要 `mysql` 命令行客户端（5.7 / 8.x 都可以）。

### 2. dbgen

仓库不携带 TPC-H 数据，需要自己编译 dbgen：

```bash
# 推荐 https://github.com/electrum/tpch-dbgen 这个长期维护的 fork
git clone https://github.com/electrum/tpch-dbgen.git dbgen
cd dbgen && make
cd ..

# 生成的二进制和 dists.dss 都在 dbgen/ 目录下，无需移动
```

### 3. 目标库

- **SeekDB**：保证用户能连，且对目标 database 有 DDL/DML 权限；如需要触发 major freeze，还需 `root@sys` 账号（脚本里通过 `SYS_PASSWORD` 环境变量提供）。
- **MySQL**：保证 `local_infile=ON`，否则 `LOAD DATA LOCAL INFILE` 会失败：
  ```sql
  SET GLOBAL local_infile = ON;
  ```

---

## 公共参数

所有脚本都接受同一组参数：

| 参数 | 说明 | 默认值 |
|---|---|---|
| `--db` | `seekdb` 或 `mysql` | `mysql` |
| `-h HOST` | 数据库地址 | `127.0.0.1` |
| `-P PORT` | 端口 | `3306` |
| `-u USER` | 用户名 | `root` |
| `-p PASS` | 密码（无密码省略） | 空 |
| `-D DBNAME` | 数据库名 | `tpch` |
| `-s SCALE` | TPC-H 规模因子 | `1` |
| `-d DIR` | 数据文件目录 | `./data/tpch_<scale>g` |

`run.sh` 额外支持：

| 参数 | 说明 | 默认值 |
|---|---|---|
| `--queries "1 3 7"` | 只跑指定编号 | 全跑 22 条 |

---

## 一次完整测试（SeekDB）

```bash
# 0. 生成 1G 数据
./scripts/prepare.sh -s 1

# 1. 建表
./scripts/create_schema.sh --db seekdb \
    -h 11.124.9.34 -P 2881 -u root -D tpch

# 2. 导入数据
./scripts/load.sh --db seekdb \
    -h 11.124.9.34 -P 2881 -u root -D tpch -s 1

# 3. 合并 + 收集统计（major freeze 需要 sys 租户密码时：SYS_PASSWORD=xxx）
./scripts/post_load.sh --db seekdb \
    -h 11.124.9.34 -P 2881 -u root -D tpch

# 4. 跑查询
./scripts/run.sh --db seekdb \
    -h 11.124.9.34 -P 2881 -u root -D tpch -s 1
```

## 一次完整测试（MySQL）

```bash
./scripts/prepare.sh -s 1
./scripts/create_schema.sh --db mysql -h <host> -P 3306 -u root -p <pass> -D tpch
./scripts/load.sh         --db mysql -h <host> -P 3306 -u root -p <pass> -D tpch -s 1
./scripts/post_load.sh    --db mysql -h <host> -P 3306 -u root -p <pass> -D tpch
./scripts/run.sh          --db mysql -h <host> -P 3306 -u root -p <pass> -D tpch -s 1
```

---

## 输出

`run.sh` 在 `logs/` 下产生两个文件：

- `tpch_<db>_<scale>g_<时间戳>.log` —— 每条 SQL 的完整输出
- `tpch_<db>_<scale>g_<时间戳>.tsv` —— `query, cost_ms` 的耗时表，方便贴到 Excel / 画图

结束时控制台也会用 `column -t` 把 tsv 打印出来。

---

## 清理

```bash
./scripts/cleanup.sh --db mysql -h <host> -P 3306 -u root -D tpch
```

---

## 已知坑

- **MySQL 报 `The used command is not allowed`**：服务端没开 `local_infile`，按上面说明打开。
- **SeekDB major freeze 卡住**：脚本会循环查 `oceanbase.cdb_ob_major_compaction` 直到 `IDLE`，10G 以上数据可能要等几分钟。
- **DDL 中的 `tablegroup`、`partition by hash 256`** 只在 seekdb DDL 里出现；如果用 1G/10G 小规模，分区数 256 可能偏大，按需调整 `ddl/seekdb/01_tables.sql`。

---

## License

脚本部分 MIT；TPC-H 查询沿用 TPC 规范，dbgen 请遵循其上游许可。
