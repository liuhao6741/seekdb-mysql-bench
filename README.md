# seekdb-mysql-bench

A collection of comparative performance benchmark scripts for **SeekDB** (OceanBase-compatible protocol) and **MySQL**, covering both OLAP and OLTP workload types.

All scripts switch the target database via a single `--db seekdb|mysql` parameter, making side-by-side comparisons straightforward.

## Benchmarks

| Directory | Type | Description |
|---|---|---|
| [tpch/](./tpch/) | OLAP | 22 standard TPC-H queries, with DDL for both SeekDB and MySQL |
| [sysbench/](./sysbench/) | OLTP | 6 OLTP workloads: point_select / read_only / read_write / insert / update_non_index / write_only |

Each benchmark is self-contained and follows a consistent structure and parameter style:

```
<bench>/
├── README.md
├── .gitignore
└── scripts/
    ├── common.sh         # Shared argument parsing
    ├── prepare.sh        # Data / schema preparation
    ├── ...               # Phase scripts for each benchmark
    ├── run.sh            # Run the benchmark
    └── cleanup.sh        # Cleanup
```

See the README in each subdirectory for detailed usage and parameter descriptions.

## Deploying the Target Databases (if not already deployed)

Both databases run via Docker with `--network host`. Ports: MySQL `3306`, SeekDB `2881`. The root password is `password` for both.

### MySQL

```bash
# 1) Pull the image
docker pull mysql:9.7.0-lts

# 2) Start
docker run -d \
  --name mysql97 \
  --cpuset-cpus=0-15 \
  -e MYSQL_ROOT_PASSWORD=password \
  -e MYSQL_ROOT_HOST=% \
  -e MYSQL_DATABASE=sbtest \
  -v /data/mysql_9.7.0:/var/lib/mysql \
  --network host \
  mysql:9.7.0-lts \
  --innodb-buffer-pool-size=10G \
  --max-connections=2000 \
  --innodb-lock-wait-timeout=120
```

### SeekDB

```bash
# 1) Pull the image
docker pull quay.io/oceanbase/seekdb:latest

# 2) Start
docker run -d \
  --name seekdb \
  --cpuset-cpus=0-15 \
  -e MEMORY_LIMIT=10G \
  -e CPU_COUNT=0 \
  -e ROOT_PASSWORD=password \
  -e SEEKDB_DATABASE=sbtest \
  -v /data/seekdb_1.3.0:/var/lib/oceanbase \
  --network host \
  quay.io/oceanbase/seekdb:latest
```

## Quick Start

```bash
# TPC-H 1G against SeekDB
cd tpch
./scripts/prepare.sh -s 1
./scripts/create_schema.sh --db seekdb -h <host> -P <port> -u root -D tpch
./scripts/load.sh          --db seekdb -h <host> -P <port> -u root -D tpch -s 1
./scripts/post_load.sh     --db seekdb -h <host> -P <port> -u root -D tpch
./scripts/run.sh           --db seekdb -h <host> -P <port> -u root -D tpch -s 1

# sysbench OLTP against SeekDB
cd ../sysbench
sudo ./scripts/install.sh
./scripts/prepare.sh --db seekdb -h <host> -P <port> -u root -D sbtest
./scripts/run.sh     --db seekdb -h <host> -P <port> -u root -D sbtest --workload all
./scripts/cleanup.sh --db seekdb -h <host> -P <port> -u root -D sbtest
```

Replace `--db seekdb` with `--db mysql` in any command to run the same test against MySQL.

## License

Scripts are MIT-licensed.
- TPC-H queries follow the TPC specification; dbgen should comply with its upstream license.
- sysbench itself is licensed under its upstream GPLv2 license.
