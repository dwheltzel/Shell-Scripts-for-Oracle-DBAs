set pages 500
set lines 2000
set trimspool on
col NAME for a39
col VALUE for a18
col pga_target_for_estimate for 999,999
col pga_target_factor for a15
col bytes_processed for 999,999,999
col estd_extra_bytes_rw for 999,999,999
col estd_pga_cache_hit_percentage for a10
col spool_name for a30 new_value spool_name
SELECT NAME||'_PGA-stats_'||to_char(SYSDATE,'YYMMDDHH24MISS') spool_name from v$database;
spool &spool_name
-- PGA tuning
SELECT NAME,to_char(decode(unit,'bytes',VALUE/1024/1024,VALUE),'999,999,999.9') VALUE,decode(unit,'bytes','mbytes',unit) unit FROM v$pgastat;
SELECT trunc(pga_target_for_estimate/1024/1024) pga_target_for_estimate,to_char(pga_target_factor*100,'999.9')||'%' pga_target_factor,
  trunc(bytes_processed/1024/1024) bytes_processed,trunc(estd_extra_bytes_rw/1024/1024) estd_extra_bytes_rw,
  to_char(estd_pga_cache_hit_percentage,'999')||'%' estd_pga_cache_hit_percentage,estd_overalloc_count FROM v$pga_target_advice;
exit
