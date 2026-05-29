-- TPC-H schema for vanilla MySQL (no partitioning / tablegroups).
-- Keep DDL minimal so it works on MySQL 5.7 / 8.x.

CREATE TABLE lineitem (
    l_orderkey      bigint        NOT NULL,
    l_partkey       bigint        NOT NULL,
    l_suppkey       int           NOT NULL,
    l_linenumber    int           NOT NULL,
    l_quantity      decimal(12,2) NOT NULL,
    l_extendedprice decimal(12,2) NOT NULL,
    l_discount      decimal(12,2) NOT NULL,
    l_tax           decimal(12,2) NOT NULL,
    l_returnflag    char(1)       DEFAULT NULL,
    l_linestatus    char(1)       DEFAULT NULL,
    l_shipdate      date          NOT NULL,
    l_commitdate    date          DEFAULT NULL,
    l_receiptdate   date          DEFAULT NULL,
    l_shipinstruct  char(25)      DEFAULT NULL,
    l_shipmode      char(10)      DEFAULT NULL,
    l_comment       varchar(44)   DEFAULT NULL,
    PRIMARY KEY (l_orderkey, l_linenumber)
);

CREATE TABLE orders (
    o_orderkey      bigint        NOT NULL,
    o_custkey       bigint        NOT NULL,
    o_orderstatus   char(1)       DEFAULT NULL,
    o_totalprice    decimal(12,2) DEFAULT NULL,
    o_orderdate     date          NOT NULL,
    o_orderpriority char(15)      DEFAULT NULL,
    o_clerk         char(15)      DEFAULT NULL,
    o_shippriority  int           DEFAULT NULL,
    o_comment       varchar(79)   DEFAULT NULL,
    PRIMARY KEY (o_orderkey)
);

CREATE TABLE partsupp (
    ps_partkey    bigint        NOT NULL,
    ps_suppkey    int           NOT NULL,
    ps_availqty   int           DEFAULT NULL,
    ps_supplycost decimal(12,2) DEFAULT NULL,
    ps_comment    varchar(199)  DEFAULT NULL,
    PRIMARY KEY (ps_partkey, ps_suppkey)
);

CREATE TABLE part (
    p_partkey     bigint        NOT NULL,
    p_name        varchar(55)   DEFAULT NULL,
    p_mfgr        char(25)      DEFAULT NULL,
    p_brand       char(10)      DEFAULT NULL,
    p_type        varchar(25)   DEFAULT NULL,
    p_size        int           DEFAULT NULL,
    p_container   char(10)      DEFAULT NULL,
    p_retailprice decimal(12,2) DEFAULT NULL,
    p_comment     varchar(23)   DEFAULT NULL,
    PRIMARY KEY (p_partkey)
);

CREATE TABLE customer (
    c_custkey    bigint        NOT NULL,
    c_name       varchar(25)   DEFAULT NULL,
    c_address    varchar(40)   DEFAULT NULL,
    c_nationkey  int           DEFAULT NULL,
    c_phone      char(15)      DEFAULT NULL,
    c_acctbal    decimal(12,2) DEFAULT NULL,
    c_mktsegment char(10)      DEFAULT NULL,
    c_comment    varchar(117)  DEFAULT NULL,
    PRIMARY KEY (c_custkey)
);

CREATE TABLE supplier (
    s_suppkey   int           NOT NULL,
    s_name      char(25)      DEFAULT NULL,
    s_address   varchar(40)   DEFAULT NULL,
    s_nationkey int           DEFAULT NULL,
    s_phone     char(15)      DEFAULT NULL,
    s_acctbal   decimal(12,2) DEFAULT NULL,
    s_comment   varchar(101)  DEFAULT NULL,
    PRIMARY KEY (s_suppkey)
);

CREATE TABLE nation (
    n_nationkey int          NOT NULL,
    n_name      char(25)     DEFAULT NULL,
    n_regionkey int          DEFAULT NULL,
    n_comment   varchar(152) DEFAULT NULL,
    PRIMARY KEY (n_nationkey)
);

CREATE TABLE region (
    r_regionkey int          NOT NULL,
    r_name      char(25)     DEFAULT NULL,
    r_comment   varchar(152) DEFAULT NULL,
    PRIMARY KEY (r_regionkey)
);
