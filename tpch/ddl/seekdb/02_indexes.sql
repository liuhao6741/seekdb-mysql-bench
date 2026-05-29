    create index I_L_ORDERKEY on lineitem(l_orderkey) local;
    create index I_L_SHIPDATE on lineitem(l_shipdate) local;
    create index I_O_ORDERDATE on orders(o_orderdate) local;
