# sysbench-bench

A set of scripts to run sysbench OLTP performance tests against **SeekDB** (OceanBase-compatible protocol) and **MySQL**, switching between the two via a single `--db seekdb|mysql` parameter.

6 workloads are included: `point_select / read_only / read_write / insert / update_non_index / write_only`.

---

## Directory Structure

```
sysbench-bench/
├── README.md
├── .gitignore
└── scripts/
    ├── install.sh       # Build and install sysbench 1.0.20 from source
    ├── common.sh        # Shared argument parsing / sysbench argv construction
    ├── prepare.sh       # Create tables + load data (oltp_read_write prepare)
    ├── cleanup.sh       # Drop tables (oltp_read_write cleanup)
    └── run.sh           # Run one or all workloads
```

`logs/` is created automatically by the scripts and excluded via `.gitignore`.

---

## Preparation

### 1. Install sysbench (first time only)

The script downloads the sysbench 1.0.20 source, compiles it, and installs to `/usr/sysbench`.

```bash
# RHEL/Anolis/CentOS — install build dependencies first
sudo yum install -y make automake libtool pkgconfig libaio-devel openssl-devel mysql-devel

# Debian/Ubuntu
# sudo apt install -y make automake libtool pkg-config libaio-dev libssl-dev libmysqlclient-dev

# Build and install
sudo ./scripts/install.sh
```

When finished, the script runs `cp -r /usr/sysbench/share/sysbench/* /usr/sysbench/bin/` and prints `sysbench --version` for verification.

Environment variable overrides:

| Variable | Meaning | Default |
|---|---|---|
| `VERSION` | sysbench version | `1.0.20` |
| `PREFIX` | Installation prefix | `/usr/sysbench` |
| `MYSQL_INCLUDES` | MySQL header directory | `/usr/include/mysql/` |
| `MYSQL_LIBS` | MySQL library directory | `/usr/lib64/mysql/` |

### 2. Target Database

- **SeekDB**: The user needs read/write + DDL privileges on the target database.
- **MySQL**: Ensure the `sbtest` (or custom) database exists; you can `CREATE DATABASE sbtest;` beforehand.

---

## Common Parameters

All scripts accept the same set of parameters:

| Parameter | Description | Default |
|---|---|---|
| `--db` | `seekdb` or `mysql` | `mysql` |
| `-h HOST` | Database host | `127.0.0.1` |
| `-P PORT` | Port | `3306` |
| `-u USER` | Username | `root` |
| `-p PASS` | Password (omit if none) | empty |
| `-D DBNAME` | Database name | `sbtest` |
| `--tables N` | Number of tables | `30` |
| `--table-size N` | Rows per table | `10000` |
| `--threads N` | Concurrency during run phase | `200` |
| `--prepare-threads N` | Concurrency during prepare phase | `16` |
| `--time N` | Run duration (seconds) | `600` |
| `--report-interval N` | Real-time statistics interval | `10` |
| `--percentile N` | Latency percentile | `99` |

`run.sh` additionally supports:

| Parameter | Description | Default |
|---|---|---|
| `--workload NAME` | See table below / `all` to run all | `read_write` |

Supported workloads:

| workload | sysbench lua | Notes |
|---|---|---|
| `point_select` | `oltp_point_select` | |
| `read_only` | `oltp_read_only` | |
| `read_write` | `oltp_read_write` | `--rand-seed=24433 --rand-type=uniform` |
| `insert` | `oltp_insert` | `--rand-seed=12104 --rand-type=uniform` |
| `update_non_index` | `oltp_update_non_index` | `--rand-seed=10515 --rand-type=uniform` |
| `write_only` | `oltp_write_only` | `--rand-seed=11972 --rand-type=uniform` |
| `all` | — | Runs the 6 workloads above sequentially |

Fixed seeds are used to make results comparable across environments.

---

## Full Test Run (SeekDB)

```bash
# 0. Install sysbench (once)
sudo ./scripts/install.sh

# 1. Load data
./scripts/prepare.sh --db seekdb \
    -h <host> -P 2881 -u root -p <pass> -D sbtest \
    --tables 30 --table-size 10000

# 2. Run a single workload
./scripts/run.sh --db seekdb \
    -h <host> -P 2881 -u root -p <pass> -D sbtest \
    --workload read_write --threads 200 --time 600

# 3. Run all 6 workloads in one shot
./scripts/run.sh --db seekdb \
    -h <host> -P 2881 -u root -p <pass> -D sbtest \
    --workload all --threads 200 --time 600

# 4. Cleanup
./scripts/cleanup.sh --db seekdb \
    -h <host> -P 2881 -u root -p <pass> -D sbtest
```

## Full Test Run (MySQL)

```bash
./scripts/prepare.sh --db mysql -h <host> -P 3306 -u root -p <pass> -D sbtest
./scripts/run.sh     --db mysql -h <host> -P 3306 -u root -p <pass> -D sbtest --workload all
./scripts/cleanup.sh --db mysql -h <host> -P 3306 -u root -p <pass> -D sbtest
```

---

## Output

`run.sh` produces one log file per workload under `logs/`:

```
logs/sysbench_<db>_<workload>_<timestamp>.log
```

The console also prints sysbench's real-time report, and a one-line summary after each workload completes:

```
[2026-05-29 14:00:00] summary: tps=12345.67 qps=246913.45 p99=12.34 ms
```

---

## Known Issues

- **`sysbench: command not found`**: `install.sh` installs to `/usr/sysbench/bin/` by default, which is not on PATH. Two workarounds:
  ```bash
  export PATH=/usr/sysbench/bin:$PATH
  # or
  export SYSBENCH_BIN=/usr/sysbench/bin/sysbench
  ```
- **`mysql.h not found` during build**: Install `mysql-devel` (RHEL) or `libmysqlclient-dev` (Debian), or specify paths via `MYSQL_INCLUDES` / `MYSQL_LIBS`.
- **MySQL permission errors**: sysbench prepare creates tables and requires CREATE / INSERT privileges on the account.

---

## License

Scripts are MIT-licensed; sysbench itself follows its upstream GPLv2 license.
