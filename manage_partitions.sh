# Manage partitions created by incremental partitioning
#
# Modified $Author: dheltzel $ 

export ORACLE_BASE=/u01/app/oracle
export ORACLE_HOME=/u01/app/oracle/product/12.1.0.2/DbHome_2

CRED=${CRED:-/}
export PATH=$PATH:$ORACLE_HOME/bin

usage() {
  echo "Usage: $0 [-d database name] [-p]"
  echo "  -d database name - defaults to $ORACLE_SID"
  echo "  -p - purge old partitions"
  exit 1
}

# Handle parameters
while getopts ":d:p" opt; do
  case $opt in
    d)
      DB_NAME=$OPTARG
      ;;
    p)
      PURGE_OLD=Y
      ;;
    \?)
      echo "Invalid option: -$OPTARG" >&2
      usage
      ;;
    :)
      echo "Option -$OPTARG requires an argument." >&2
      usage
      ;;
  esac
done

DB_NAME=${DB_NAME:-${ORACLE_SID}}
export ORACLE_SID=${DB_NAME}
BASE_NAME=ManagePartitions_${DB_NAME}-`date "+%y%m%d%H%M"`
REPORT_NAME=${BASE_NAME}.lst
SQL_NAME=${BASE_NAME}.sql
DROP_SQL_NAME=${BASE_NAME}-drop.sql
CMD_OUTPUT_NAME=${BASE_NAME}.out
#echo "ORACLE_SID: ${ORACLE_SID}"
#echo "DB_NAME: ${DB_NAME}"
#echo "REPORT_NAME: ${REPORT_NAME}"
#echo "SQL_NAME: ${SQL_NAME}"

sqlplus -s ${CRED} as sysdba <<! >${SQL_NAME}
SET SERVEROUT ON SIZE UNLIMITED
SET FEED OFF
SET HEAD OFF
SET LINES 200
ALTER SESSION SET DDL_LOCK_TIMEOUT=300

DECLARE
  c_month VARCHAR2(10);
  c_high_value VARCHAR2(300);
  i_high_value INTEGER;
  c_new_name   VARCHAR2(300);
  v_suffix     VARCHAR2(50);
  d_high_value DATE;
BEGIN
  -- tables that are partitioned by day
  FOR r IN (select table_owner,table_name,partition_name,high_value,trim( '_' from substr(table_name, 0, 18)) stub_name from dba_tab_partitions
             WHERE partition_name LIKE 'SYS%' AND table_name in ('MERCHANT_ALERTS','AUTH_LOG','NOTIF_SERV_SENT_EMAIL','MTS_EVENT_LOG','APP_AUDIT_AUX','SENT_EMAIL_QUEUE') AND table_owner IN ('PAYPANEL','CCONNECT','NOTIFICATION','BIZ','ENT_COMMON','FTSV1'))
  LOOP
    BEGIN
    c_high_value := substr(r.high_value, 11, 10);
    d_high_value := to_date(c_high_value, 'YYYY-MM-DD') - 1;
    c_new_name := r.stub_name||'_'||to_char(d_high_value, 'YYYY_MMDD');
    if (r.partition_name <> c_new_name) then
      --dbms_output.put_line('alter table '||r.table_owner||'.'||r.table_name||' rename partition '||r.partition_name||' to '||r.stub_name||'_'||to_char(d_high_value, 'YYYY_MMDD')||';');
      execute immediate 'alter table '||r.table_owner||'.'||r.table_name||' rename partition '||r.partition_name||' to '||r.stub_name||'_'||to_char(d_high_value, 'YYYY_MMDD');
    end if;
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
  END LOOP;

  -- tables that are partitioned by a 3 digit number
  FOR r IN (select table_owner,table_name,partition_name,high_value,trim( '_' from substr(table_name, 0, 18)) stub_name from dba_tab_partitions
             WHERE partition_name LIKE 'SYS%' AND table_name in ('RESIDUAL_DETAIL','RESIDUAL_DETAIL_AGENT') AND table_owner IN ('RE'))
  LOOP
    BEGIN
    c_high_value := substr(r.high_value, 1, 3);
    i_high_value := to_number(c_high_value, '999') - 1;
    c_new_name := r.stub_name||'_'||to_char(i_high_value,'FM999');
    if (r.partition_name <> c_new_name) then
      --dbms_output.put_line('alter table '||r.table_owner||'.'||r.table_name||' rename partition '||r.partition_name||' to '||c_new_name||';');
      execute immediate 'alter table '||r.table_owner||'.'||r.table_name||' rename partition '||r.partition_name||' to '||c_new_name;
    end if;
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
  END LOOP;

  -- tables that are partitioned by a number
  FOR r IN (select table_owner,table_name,partition_name,high_value,trim( '_' from substr(table_name, 0, 18)) stub_name from dba_tab_partitions
             WHERE partition_name LIKE 'SYS%' AND (table_owner, table_name) in (SELECT owner, table_name FROM dba_part_tables WHERE INTERVAL = '10000'))
--table_name in ('SRC_TSYS_TRANSACTIONS','STG_OMAHA_TRANS_MD028','SRC_OMAHA','SRC_NORTH_DFM','STG_NORTH_LOC_TRAILER','STG_NORTH_LOC_HEADER','TAR_AUTHORIZATIONS','TAR_DEPOSIT_ADJUSTMENT') AND table_owner IN ('DE'))
  LOOP
    BEGIN
    c_high_value := trim(r.high_value);
    i_high_value := to_number(c_high_value, '99999999999') - 1;
    c_new_name := r.stub_name||'_'||to_char(i_high_value, 'FM99999999999');
    --c_new_name := r.stub_name||'_'||c_high_value;
    if (r.partition_name <> c_new_name) then
      --dbms_output.put_line('alter table '||r.table_owner||'.'||r.table_name||' rename partition '||r.partition_name||' to '||c_new_name||';');
      execute immediate 'alter table '||r.table_owner||'.'||r.table_name||' rename partition '||r.partition_name||' to '||c_new_name;
    end if;
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
  END LOOP;

  -- tables that are partitioned by month (integer format column)
  FOR r IN (select table_owner,table_name,partition_name,high_value,trim( '_' from substr(table_name, 0, 18)) stub_name from dba_tab_partitions
             WHERE partition_name LIKE 'SYS%' AND table_owner IN ('BIZ','CCONNECT') AND table_name IN ('AUTH_HISTORY','MERCHANT_IC_PLAN_STAT'))
  LOOP
    BEGIN
    c_month := substr(r.high_value, 5, 2);
    if (c_month > 12) then
      c_high_value := substr(r.high_value, 1, 4)||'12';
      d_high_value := to_date(c_high_value, 'YYYYMM');
    else
      c_high_value := substr(r.high_value, 1, 8);
      d_high_value := to_date(c_high_value, 'YYYYMMDD') - 1;
    end if;
    c_new_name := r.stub_name||'_'||to_char(d_high_value, 'YYYY_MM');
    if (r.partition_name <> c_new_name) then
      --dbms_output.put_line('alter table '||r.table_owner||'.'||r.table_name||' rename partition '||r.partition_name||' to '||r.stub_name||'_'||to_char(d_high_value, 'YYYY_MM')||';');
      execute immediate 'alter table '||r.table_owner||'.'||r.table_name||' rename partition '||r.partition_name||' to '||r.stub_name||'_'||to_char(d_high_value, 'YYYY_MM');
    end if;
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
  END LOOP;

  -- tables that are partitioned by month (date format column)
  FOR r IN (select table_owner,table_name,partition_name,high_value,trim( '_' from substr(replace(table_name, 'TAR_', ''), 0, 18)) stub_name from dba_tab_partitions
             WHERE  partition_name LIKE 'SYS%' AND table_name NOT IN ('SRC_TSYS_TRANSACTIONS','STG_OMAHA_TRANS_MD028','SRC_OMAHA','MERCHANT_ALERTS','AUTH_LOG','RESIDUAL_DETAIL','RESIDUAL_DETAIL_AGENT','SRC_NORTH_DFM','AUTH_HISTORY')
             AND table_owner NOT LIKE 'APEX%' AND table_owner NOT IN (SELECT owner FROM dba_logstdby_skip WHERE statement_opt = 'INTERNAL SCHEMA'))
  LOOP
    BEGIN
    c_high_value := substr(r.high_value, 11, 10);
    d_high_value := to_date(c_high_value, 'YYYY-MM-DD') - 1;
    c_new_name := r.stub_name||'_'||to_char(d_high_value, 'YYYY_MM');
    if (r.partition_name <> c_new_name) then
      --dbms_output.put_line('alter table '||r.table_owner||'.'||r.table_name||' rename partition '||r.partition_name||' to '||r.stub_name||'_'||to_char(d_high_value, 'YYYY_MM')||';');
      execute immediate 'alter table '||r.table_owner||'.'||r.table_name||' rename partition '||r.partition_name||' to '||r.stub_name||'_'||to_char(d_high_value, 'YYYY_MM');
    end if;
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
  END LOOP;
END;
/

-- Rename index partitions
SELECT 'ALTER INDEX '||ip.index_owner||'.'||ip.index_name||' RENAME PARTITION '||ip.partition_name||' TO '||p.partition_name||';'
  FROM dba_ind_partitions ip
  JOIN dba_part_indexes pi ON (pi.owner=ip.index_owner AND pi.index_name=ip.index_name)
  JOIN dba_tab_partitions p ON (p.table_owner=pi.owner AND p.table_name=pi.table_name AND p.partition_position=ip.partition_position)
 WHERE ip.partition_name <> p.partition_name AND ip.partition_name NOT LIKE 'SYS_IL%'
   AND table_owner NOT IN (SELECT owner FROM dba_logstdby_skip WHERE statement_opt = 'INTERNAL SCHEMA')
 ORDER BY p.table_owner,p.table_name,p.partition_position,ip.index_name;

-- Move index partitions to be with their data segment (DE only at this time)
SELECT 'alter index '||i.index_owner||'.'||i.index_name||' rebuild partition '||i.partition_name||' tablespace '||t.tablespace_name||' online;'
  FROM dba_tab_partitions t JOIN dba_ind_partitions i ON (i.index_owner = t.table_owner AND i.partition_name = t.partition_name)
 WHERE t.tablespace_name <> i.tablespace_name AND t.table_owner IN ('DE') ORDER BY 1;

exit
q
!

drop_old_partitions () {
sqlplus -s ${CRED} as sysdba <<! >${DROP_SQL_NAME}
SET SERVEROUT ON SIZE UNLIMITED
SET FEED OFF
SET HEAD OFF
SET LINES 200
ALTER SESSION SET DDL_LOCK_TIMEOUT=300

SELECT 'alter table PAYPANEL.MERCHANT_ALERTS drop partition '||partition_name||' update global indexes;'
  FROM dba_tab_partitions p WHERE table_owner = 'PAYPANEL' AND table_name = 'MERCHANT_ALERTS' AND partition_name < (SELECT 'MERCHANT_ALERTS_'||to_char(SYSDATE - 30,'YYYY_MMDD') FROM dual);
SELECT 'alter table CCONNECT.AUTH_LOG drop partition '||partition_name||' update global indexes;'
  FROM dba_tab_partitions p WHERE table_owner = 'CCONNECT' AND table_name = 'AUTH_LOG' AND partition_name < (SELECT 'AUTH_LOG_'||to_char(SYSDATE - 30,'YYYY_MMDD') FROM dual);
SELECT 'alter table DE.SRC_NORTH_DFM drop partition '||subobject_name||' update global indexes;',created,last_ddl_time FROM dba_objects
 WHERE owner = 'DE' AND object_name = 'SRC_NORTH_DFM' AND object_type = 'TABLE PARTITION' AND subobject_name NOT LIKE '%BASE' AND created < SYSDATE - 31;
SELECT 'alter table BIZ.STG_MERCH_TRAN drop partition '||partition_name||' update global indexes;'
  FROM dba_tab_partitions p WHERE table_owner = 'BIZ' AND table_name = 'STG_MERCH_TRAN' AND partition_name < (SELECT 'STG_MERCH_TRAN_'||to_char(SYSDATE - 90,'YYYY_MM') FROM dual);
SELECT 'alter table NOTIFICATION.NOTIF_SERV_SENT_EMAIL drop partition '||partition_name||' update global indexes;'
  FROM dba_tab_partitions p WHERE table_owner = 'NOTIFICATION' AND table_name = 'NOTIF_SERV_SENT_EMAIL' AND partition_name < (SELECT 'NOTIF_SERV_SENT_EM_'||to_char(SYSDATE - 30,'YYYY_MMDD') FROM dual);
SELECT 'alter table BIZ.MTS_EVENT_LOG drop partition '||partition_name||' update global indexes;'
  FROM dba_tab_partitions p WHERE table_owner = 'BIZ' AND table_name = 'MTS_EVENT_LOG' AND partition_name < (SELECT 'MTS_EVENT_LOG_'||to_char(SYSDATE - 30,'YYYY_MMDD') FROM dual);
SELECT 'alter table ENT_COMMON.APP_AUDIT_AUX drop partition '||partition_name||' update global indexes;'
  FROM dba_tab_partitions p WHERE table_owner = 'ENT_COMMON' AND table_name = 'APP_AUDIT_AUX' AND partition_name < (SELECT 'APP_AUDIT_AUX_'||to_char(SYSDATE - 59,'YYYY_MMDD') FROM dual);

exit
!
}

if [ -s ${SQL_NAME} ] ; then
  cat ${SQL_NAME}
  sqlplus -s ${CRED} as sysdba <<! >${CMD_OUTPUT_NAME}
ALTER SESSION SET DDL_LOCK_TIMEOUT=300
@${SQL_NAME}
exit
!
else
  rm ${SQL_NAME}
fi

# Purge old partitions if -p was specified
# explicitly runs dbms_part.cleanup_gidx to force the coalese cleanup to happen now
if [ -n "${PURGE_OLD}" ] ; then
  drop_old_partitions
  if [ -s ${DROP_SQL_NAME} ] ; then
    cat ${DROP_SQL_NAME}
    sqlplus -s ${CRED} as sysdba <<! >>${CMD_OUTPUT_NAME}
ALTER SESSION SET DDL_LOCK_TIMEOUT=300
@${DROP_SQL_NAME}
exec dbms_part.cleanup_gidx
exit
!
  else
    rm ${DROP_SQL_NAME}
  fi
fi

