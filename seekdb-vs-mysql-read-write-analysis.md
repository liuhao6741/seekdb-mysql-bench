# SeekDB vs MySQL 9.7：sysbench OLTP read_write 性能差距归因分析

## 摘要

在 16 核 / 30G 内存、64 并发的相同配置下，对 SeekDB（OceanBase 内核）与 MySQL 9.7 跑 sysbench OLTP 三组负载，发现：

- **read_only / write_only 两者性能基本持平**（差距 < 6%）；
- **read_write 混合负载下 MySQL 明显领先**（TPS 高约 69%）。

经逐层归因 + 两组受控验证，结论是：**差距几乎全部来自 read_write 中的范围扫描（range select）在 SeekDB LSM-Tree 架构下的"增量层读放大"**，而非锁竞争、事务冲突重试或 read-your-own-writes。该短板是 LSM（write-optimized）架构换取写性能的固有代价，且会随单表数据量增大（写入更分散、增量密度更低）而自然减轻。

---

## 1. 测试环境

| 项 | 配置 |
|---|---|
| 物理机 | hudson@6.13.1.216，Alibaba Cloud Linux 3，128 核 |
| 部署方式 | Docker，`--network host`，均限 `--cpuset-cpus=0-15`（16 核） |
| SeekDB | `quay.io/oceanbase/seekdb:latest`，`MEMORY_LIMIT=30G`，`CPU_COUNT=0`，端口 2881 |
| MySQL | `mysql:9.7.0-lts`，`innodb-buffer-pool-size=30G`，`buffer-pool-instances=16`，`max-connections=2000`，端口 3306 |
| 压测工具 | sysbench 1.0.20 |
| 并发 | 64 线程 |
| 数据规模 | 30 表 × 10,000 行（基准）；验证实验另用 200,000 行 |

> 说明：两库数据量在 10,000 行/表时约数百 MB、200,000 行/表时约 1.2GB，均**全内存**，不引入磁盘 IO，保证对比聚焦于引擎读写路径本身。SeekDB 在压测前关闭了 sql_audit / perf_event / trace 等（仅在归因分析时临时开启）。

---

## 2. 基准结果（table_size=10,000，64 并发，60s）

| Workload | SeekDB TPS | SeekDB QPS | SeekDB P99 | MySQL TPS | MySQL QPS | MySQL P99 |
|---|---|---|---|---|---|---|
| read_only | 22,867 | 365,876 | 5.00 ms | 24,033 | 384,527 | 5.37 ms |
| write_only | 43,144 | 258,862 | 3.07 ms | 42,048 | 252,288 | 3.49 ms |
| **read_write** | **~8,000** | **~160,000** | **~16 ms** | **13,544** | **270,875** | **11.87 ms** |

> read_write 的 SeekDB 多次运行为 8,060 / 7,875 / 6,985，并呈现轻微的**时间衰减**（运行越久越慢）；major compaction 后回升至 8,006。取 ~8,000 为代表值。

**现象**：纯读、纯写两库几乎一致，唯独混合读写差距悬殊。

---

## 3. 归因分析

### 3.1 延迟叠加分析（定位"额外开销"存在）

read_write 的工作量本质 = read_only 的读 + write_only 的写，放进同一个事务。若无额外开销，单事务延迟应约等于两者之和：

| | read_only avg | write_only avg | 叠加预期 | read_write 实测 | 超出倍数 |
|---|---|---|---|---|---|
| **SeekDB** | 2.80 ms | 1.48 ms | 4.28 ms | 7.94 ms | **1.85×** |
| **MySQL** | 2.66 ms | 1.52 ms | 4.18 ms | 4.72 ms | **1.13×** |

MySQL 混合事务延迟几乎就是"读+写"的简单相加（仅多 13%）；SeekDB 多出 85%。**额外开销存在于 SeekDB 的混合事务中。**

### 3.2 QPS 吞吐塌陷（横向印证）

| | read_only QPS | write_only QPS | read_write QPS |
|---|---|---|---|
| **SeekDB** | 365,876 | 258,862 | ~160k（异常偏低） |
| **MySQL** | 384,527 | 252,288 | 270,875（落在两者之间，正常） |

MySQL 的 read_write QPS 正常地落在自己纯读/纯写之间；SeekDB 却塌陷到比自己纯读、纯写都低 40–60%。

### 3.3 SQL Audit 单语句耗时分解（定位"哪条语句变慢"）

临时开启 `enable_sql_audit` / `enable_perf_event`，对比每类语句在**独立事务 vs 混合事务**中的服务端耗时（elapsed，μs）：

| 语句 | 独立事务（ro/wo） | 混合事务（rw） | 增量 | 增幅 |
|---|---|---|---|---|
| **SELECT** | 84 | 136 | +52 | +62% |
| UPDATE | 55 | 76 | +21 | +38% |
| DELETE | 49 | 67 | +18 | +37% |
| INSERT | 46 | 68 | +22 | +48% |
| COMMIT | 18–24 | 40 | +16~22 | +67~122% |

每类语句都变慢，**SELECT 变慢最多**。同时 audit 显示：

- `application_wait_time`（行锁等待）= **0** → 排除锁竞争
- `concurrency_wait_time`（latch 等待）= **0** → 排除并发控制等待
- `retry_cnt` ≈ **0** → 排除乐观事务冲突重试
- 慢在 `execute_time` 本身（执行阶段变重）

### 3.4 关键证据：SELECT 按 point/range 拆分 + 读行数来源

进一步把 SELECT 拆成 point / range 子类型，并读取 audit 的 `MEMSTORE_READ_ROW_COUNT`（从 memtable 增量层扫描的行数）和 `SSSTORE_READ_ROW_COUNT`（从 sstable 基线层扫描的行数）：

| SELECT 类型 | read_only 耗时 | read_write 耗时 | 放大 | ro 增量/基线行 | rw 增量/基线行 |
|---|---|---|---|---|---|
| **point** | 21 μs | 29 μs | 1.4× | 0 / 0 | 1 / 0 |
| **sum_range** | 88 μs | 186 μs | 2.1× | **0 / 100** | **77 / 99** |
| **simple_range** | 97 μs | 200 μs | 2.1× | **0 / 100** | **77 / 99** |
| **order_range** | 126 μs | 235 μs | 1.9× | **0 / 100** | **77 / 99** |
| **distinct_range** | 132 μs | 235 μs | 1.8× | **0 / 100** | **77 / 99** |

**机制一目了然**：

- **read_only 状态**：memtable 为空，所有 range 查询 `mem_rows=0`，100 行全部命中基线 sstable，单层扫描。
- **read_write 状态**：64 并发的 INSERT/UPDATE/DELETE 把大量行写入 memtable 增量层，同一个 range 查询的 `mem_rows` 从 0 暴涨到 **77**，基线层仍有 99 行 → 每个 range 扫描行数 **100 → 176**（基线 + 增量两层归并），耗时翻倍。

这 77 行**不是本事务写的**（point select 的 `mem_rows` 仅为 1），而是**所有并发事务**写入污染了读路径。因此正确机制是**全局增量层读放大**，而非 read-your-own-writes（后者成本极小，不足以解释 +52μs）。

**额外开销构成（每事务 14 个 SELECT）**：

| 来源 | 每事务额外 | 占 SELECT 额外开销 |
|---|---|---|
| **4 个 range 查询翻倍**（+104μs × 4） | **+416 μs** | **~84%** |
| 10 个 point 查询（+8μs × 10） | +80 μs | ~16% |

> range 只占 SELECT 的 29%、占全部语句的 20%，却贡献了 ~84% 的额外开销。

---

## 4. 受控验证

### 验证一：关闭 range 查询（range_selects=off）

预测：若差距来自 range，关掉它差距应坍缩。

| 配置 | SeekDB TPS | MySQL TPS | 差距 |
|---|---|---|---|
| range_selects = **ON**（含 4 类 range） | 8,006 | 13,544 | MySQL +**69%** |
| range_selects = **OFF**（仅 point + 写） | **21,407** | **22,935** | MySQL +**7%** |

差距从 **69% → 7%**，SeekDB 的 P99 反而更低（5.28 ms vs 9.06 ms）。**证明差距几乎全部来自 range 查询。**

### 验证二：增大单表行数（稀释增量密度）

预测：range 窗口固定 100 行、写入速率受 CPU 限制大致恒定。把 `table_size` 增大 N 倍，等于把写入分散到 N 倍 key 空间，任意 100 行窗口内被写脏的行数降到约 1/N，`mem_rows` 下降、读放大减轻、差距缩小。

| table_size | SeekDB TPS | MySQL TPS | 差距 | range 的 mem_rows |
|---|---|---|---|---|
| **10,000** | 8,006 | 13,544 | +**69%** | 77 |
| **200,000**（稀释 20×） | **11,116** | 13,085 | +**18%** | **14.6** |

range 查询耗时随之逼近 read_only 单层基准：

| range 类型 | table_size=10,000 | table_size=200,000 | read_only 基准 |
|---|---|---|---|
| sum_range | 186 μs | 107 μs | 88 μs |
| simple_range | 200 μs | 98 μs | 97 μs |
| order_range | 235 μs | 128 μs | 126 μs |
| distinct_range | 235 μs | 134 μs | 132 μs |

`mem_rows` 77 → 14.6，range 耗时几乎腰斩、接近基准，差距 69% → 18%。**证明 range 慢来自 LSM 增量层读放大，且可通过降低增量密度缓解。**

> 残留的 ~18% 是结构性的：即使增量层很薄，LSM 的 range 扫描仍需走"基线 + 增量"的 merge iterator 框架，叠加列式编码块解码 vs InnoDB B+Tree 顺序页扫描的固有差异，靠稀释无法消除。继续增大表会把差距进一步压低，直到撞上内存上限引入磁盘 IO。

---

## 5. 架构根因：LSM-Tree vs B+Tree

| | SeekDB（OceanBase，LSM-Tree） | MySQL InnoDB（B+Tree 原地更新） |
|---|---|---|
| 写入 | 追加到 memtable 增量层，基线 sstable 不动 | 在聚簇索引 B+Tree 页**原地修改**，旧版本进 undo |
| range 读 | 必须扫 **基线 sstable + 增量 memtable 两层**并归并；写得越多增量层越厚、读越慢 | 在**一棵 B+Tree** 上顺序扫叶子页，**单层** |
| 版本可见性 | 行只要在 memtable 有修改就要走融合路径（不论谁改的） | 仅当扫到的行**恰好**被未提交事务改过才回溯 undo，**逐行按需、稀疏** |

核心差异：**InnoDB 的写入不改变读取的数据结构层次** —— 无论并发写多少，range 读永远是一棵 B+Tree 的范围扫描（30G buffer pool 全内存即纯内存遍历），版本回溯稀疏且局部。而 **LSM 的写入会抬高 memtable 增量层，把所有 range 读从"单层扫描"变成"两层归并扫描"**，读放大随并发写入量增长。这正是 LSM 用写性能换取的读侧代价。

**这也解释了三组结果为何自洽**：

- **write_only** SeekDB ≥ MySQL：LSM 顺序写 memtable 是强项；
- **read_only** 两者持平：无增量层，都是单层读；
- **read_write** SeekDB 落后：LSM 读放大恰好在"边写边做范围扫描"时被放大暴露。

---

## 6. 结论与实践启示

1. **OLTP 点查 + 写混合负载，SeekDB 与 MySQL 9.7 基本同档**（range_off 时差距仅 7%）。
2. **SeekDB 的明显短板是"在写活跃表上做范围扫描"** —— 来自 LSM 增量层读放大，是架构权衡而非 bug 或调参问题。
3. **该短板随单表数据量增大而减轻**：sysbench 默认 10,000 行/表的小表场景**放大**了 SeekDB 的劣势；真实业务大表（行数远超 20 万）写入更分散、增量密度更低，差距会显著小于本基准所示。
4. **缓解手段**：更频繁的 major compaction（清空增量层，但只要持续写就会重新累积，故有时间衰减）、更大的单表数据量、或避免在高频写入表上做大范围扫描。

---

## 附录：归因证据链

| 步骤 | 方法 | 关键发现 |
|---|---|---|
| 定位额外开销 | 延迟叠加分析 | SeekDB 1.85× vs MySQL 1.13× |
| 横向印证 | QPS 对比 | SeekDB read_write QPS 异常塌陷 |
| 定位到语句 | SQL Audit 分解 | SELECT 变慢最多；锁等待/重试均为 0 |
| 定位到 range | point/range 拆分 + mem_rows | range 的 mem_rows 0→77，扫描行数翻倍 |
| 验证（充分性） | range_selects=off | 差距 69% → 7% |
| 验证（机制） | table_size 10k→200k | mem_rows 77→14.6，差距 69% → 18% |
