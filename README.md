# seekdb-mysql-bench

针对 **SeekDB**（OceanBase 兼容协议）和 **MySQL** 的对比性能测试脚本集合，覆盖 OLAP 与 OLTP 两类典型负载。

所有脚本通过 `--db seekdb|mysql` 一个参数切换被测对象，方便横向对比。

## Benchmarks

| 目录 | 类型 | 内容 |
|---|---|---|
| [tpch/](./tpch/) | OLAP | 22 条标准 TPC-H 查询，含 SeekDB 和 MySQL 两套 DDL |
| [sysbench/](./sysbench/) | OLTP | 6 种 OLTP workload：point_select / read_only / read_write / insert / update_non_index / write_only |

各 benchmark 是独立的，结构、参数风格保持一致：

```
<bench>/
├── README.md
├── .gitignore
└── scripts/
    ├── common.sh         # 公共参数解析
    ├── prepare.sh        # 数据/Schema 准备
    ├── ...               # 各 bench 自己的阶段脚本
    ├── run.sh            # 跑测试
    └── cleanup.sh        # 清理
```

详细用法和参数说明见各子目录的 README。

## 快速开始

```bash
# TPC-H 1G 跑 SeekDB
cd tpch
./scripts/prepare.sh -s 1
./scripts/create_schema.sh --db seekdb -h <host> -P <port> -u root -D tpch
./scripts/load.sh          --db seekdb -h <host> -P <port> -u root -D tpch -s 1
./scripts/post_load.sh     --db seekdb -h <host> -P <port> -u root -D tpch
./scripts/run.sh           --db seekdb -h <host> -P <port> -u root -D tpch -s 1

# sysbench OLTP 跑 SeekDB
cd ../sysbench
sudo ./scripts/install.sh
./scripts/prepare.sh --db seekdb -h <host> -P <port> -u root -D sbtest
./scripts/run.sh     --db seekdb -h <host> -P <port> -u root -D sbtest --workload all
./scripts/cleanup.sh --db seekdb -h <host> -P <port> -u root -D sbtest
```

把任意命令里的 `--db seekdb` 换成 `--db mysql` 即可对 MySQL 做相同测试。

## License

脚本部分 MIT。
- TPC-H 查询沿用 TPC 规范，dbgen 请遵循其上游许可。
- sysbench 本身遵循其上游 GPLv2 许可。
