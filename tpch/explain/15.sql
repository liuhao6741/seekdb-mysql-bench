CREATE VIEW revenue0
(supplier_no, total_revenue)
AS
  SELECT /*+ parallel(90) */  l_suppkey,
         SUM(l_extendedprice * ( 1 - l_discount ))
  FROM   lineitem
  WHERE  l_shipdate >= DATE '1997-07-01'
         AND l_shipdate < DATE '1997-07-01' + interval '3' month
  GROUP  BY l_suppkey;

explain select /*+ TPCH_Q15 parallel(90) */
        s_suppkey,
        s_name,
        s_address,
        s_phone,
        total_revenue
from
        supplier,
        revenue0
where
        s_suppkey = supplier_no
        and total_revenue = (
                select
                        max(total_revenue)
                from
                        revenue0
        )
order by
        s_suppkey;

drop view revenue0;
