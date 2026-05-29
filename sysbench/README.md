# sysbench-bench

用一套脚本针对 **SeekDB**（OceanBase 兼容协议）和 **MySQL** 跑 sysbench OLTP 性能测试，通过 `--db seekdb|mysql` 一个参数切换。

包含 6 种 workload：`point_select / read_only / read_write / insert / update_non_index / write_only`。

---

## 目录结构

```
sysbench-bench/
├── README.md
├── .gitignore
└── scripts/
    ├── install.sh       # 从源码编译安装 sysbench 1.0.20
    ├── common.sh        # 公共参数解析 / sysbench argv 构造
    ├── prepare.sh       # 建表 + 灌数据（oltp_read_write prepare）
    ├── cleanup.sh       # 删表（oltp_read_write cleanup）
    └── run.sh           # 跑一个或全部 workload
```

`logs/` 由脚本自动创建，并在 `.gitignore` 中排除。

---

## 准备工作

### 1. 安装 sysbench（首次）

脚本会下载 sysbench 1.0.20 源码，编译并安装到 `/usr/sysbench`。

```bash
# RHEL/Anolis/CentOS 先装编译依赖
sudo yum install -y make automake libtool pkgconfig libaio-devel openssl-devel mysql-devel

# Debian/Ubuntu
# sudo apt install -y make automake libtool pkg-config libaio-dev libssl-dev libmysqlclient-dev

# 编译安装
sudo ./scripts/install.sh
```

完成后会自动 `cp -r /usr/sysbench/share/sysbench/* /usr/sysbench/bin/`，并打印 `sysbench --version` 验证。

环境变量可覆盖：

| 变量 | 含义 | 默认 |
|---|---|---|
| `VERSION` | sysbench 版本 | `1.0.20` |
| `PREFIX` | 安装前缀 | `/usr/sysbench` |
| `MYSQL_INCLUDES` | mysql 头文件目录 | `/usr/include/mysql/` |
| `MYSQL_LIBS` | mysql 库目录 | `/usr/lib64/mysql/` |

### 2. 目标库

- **SeekDB**：用户对目标 database 有读写 + DDL 权限即可。
- **MySQL**：保证存在 `sbtest`（或自定义）数据库；可以预先 `CREATE DATABASE sbtest;`。

---

## 公共参数

所有脚本都接受同一组参数：

| 参数 | 说明 | 默认 |
|---|---|---|
| `--db` | `seekdb` 或 `mysql` | `mysql` |
| `-h HOST` | 数据库地址 | `127.0.0.1` |
| `-P PORT` | 端口 | `3306` |
| `-u USER` | 用户名 | `root` |
| `-p PASS` | 密码（无密码省略） | 空 |
| `-D DBNAME` | 数据库名 | `sbtest` |
| `--tables N` | 表数量 | `30` |
| `--table-size N` | 每表行数 | `10000` |
| `--threads N` | run 阶段并发 | `200` |
| `--prepare-threads N` | prepare 阶段并发 | `16` |
| `--time N` | run 持续时间（秒） | `600` |
| `--report-interval N` | 实时统计间隔 | `10` |
| `--percentile N` | 延迟分位 | `99` |

`run.sh` 额外支持：

| 参数 | 说明 | 默认 |
|---|---|---|
| `--workload NAME` | 见下表 / `all` 跑全部 | `read_write` |

支持的 workload：

| workload | sysbench lua | 备注 |
|---|---|---|
| `point_select` | `oltp_point_select` | |
| `read_only` | `oltp_read_only` | |
| `read_write` | `oltp_read_write` | `--rand-seed=24433 --rand-type=uniform` |
| `insert` | `oltp_insert` | `--rand-seed=12104 --rand-type=uniform` |
| `update_non_index` | `oltp_update_non_index` | `--rand-seed=10515 --rand-type=uniform` |
| `write_only` | `oltp_write_only` | `--rand-seed=11972 --rand-type=uniform` |
| `all` | — | 顺序跑上面 6 种 |

固定 seed 是为了不同环境之间的结果可对比。

---

## 一次完整测试（SeekDB）

```bash
# 0. 安装 sysbench（只跑一次）
sudo ./scripts/install.sh

# 1. 灌数据
./scripts/prepare.sh --db seekdb \
    -h <host> -P 2881 -u root -p <pass> -D sbtest \
    --tables 30 --table-size 10000

# 2. 跑某一种 workload
./scripts/run.sh --db seekdb \
    -h <host> -P 2881 -u root -p <pass> -D sbtest \
    --workload read_write --threads 200 --time 600

# 3. 一把跑完 6 种
./scripts/run.sh --db seekdb \
    -h <host> -P 2881 -u root -p <pass> -D sbtest \
    --workload all --threads 200 --time 600

# 4. 清理
./scripts/cleanup.sh --db seekdb \
    -h <host> -P 2881 -u root -p <pass> -D sbtest
```

## 一次完整测试（MySQL）

```bash
./scripts/prepare.sh --db mysql -h <host> -P 3306 -u root -p <pass> -D sbtest
./scripts/run.sh     --db mysql -h <host> -P 3306 -u root -p <pass> -D sbtest --workload all
./scripts/cleanup.sh --db mysql -h <host> -P 3306 -u root -p <pass> -D sbtest
```

---

## 输出

`run.sh` 每跑一个 workload 在 `logs/` 下产生：

```
logs/sysbench_<db>_<workload>_<时间戳>.log
```

控制台同步打印 sysbench 的实时报告，并在每个 workload 结束后输出一行 summary：

```
[2026-05-29 14:00:00] summary: tps=12345.67 qps=246913.45 p99=12.34 ms
```

---

## 已知坑

- **`sysbench: command not found`**：`install.sh` 默认装到 `/usr/sysbench/bin/`，没加入 PATH。两种办法：
  ```bash
  export PATH=/usr/sysbench/bin:$PATH
  # 或者
  export SYSBENCH_BIN=/usr/sysbench/bin/sysbench
  ```
- **编译时报 `mysql.h not found`**：装 `mysql-devel`（RHEL）或 `libmysqlclient-dev`（Debian），或通过 `MYSQL_INCLUDES` / `MYSQL_LIBS` 指定路径。
- **MySQL 报权限错误**：sysbench prepare 会建表，要求账号有 CREATE / INSERT 等权限。

---

## License

脚本 MIT；sysbench 本身遵循其上游 GPLv2 license。
