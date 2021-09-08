set pages 0
set lines 200
set feed off
set head off
SELECT cmd FROM
(SELECT 'alter index '||owner||'.'||index_name||' rebuild nologging online;' cmd,i.uniqueness
  FROM dba_indexes i WHERE status = 'UNUSABLE'
   AND index_name NOT IN ('IDX_SCHED_A_TYPE','IDX_RESIDUAL_DETAIL2_MID','IDX_RESIDUAL_DETAIL_FEE_CODE','INDEX19','IDX_RDA_MID',
        'IDX_RDA_RDID','IDX_RDA_AGENT_ID','IDX_RDA_SALES_CODE')
UNION
SELECT 'alter index '||p.index_owner||'.'||p.index_name||' rebuild partition '||p.partition_name||' nologging online;',i.uniqueness
  FROM dba_ind_partitions p JOIN dba_indexes i ON (i.owner = p.index_owner AND i.index_name = p.index_name) WHERE p.status = 'UNUSABLE')
 ORDER BY uniqueness DESC;

