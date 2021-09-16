# Manage partitions created by incremental partitioning
#
# Modified $Author: dheltzel $ 
. /home/oracle/bin/ora_funcs.sh
#ORACLE_SID=FTSPRDEXA2
ORACLE_BASE=/u01/app/oracle
ORACLE_HOME=${ORACLE_BASE}/product/12.1.0.2/DbHome_2
PATH=$PATH:$ORACLE_HOME/bin

CRED=${CRED:-/}
if [ -r SetEnv.sh ] ; then
. ./SetEnv.sh
fi

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
LOG_DIR=/cloudfs/logs
LOG_FILE=${LOG_DIR}/manage_partitions-${ORACLE_SID}.`date '+%y%m'`
if test -t 1; then
    echo "Results in $LOG_FILE"
fi
exec >> $LOG_FILE 2>&1
echo "Starting `date`"
oe ${ORACLE_SID}

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
             WHERE partition_name LIKE 'SYS%' AND table_name in ('LOG','QUEUE') AND table_owner IN ('SCOTT'))
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
             WHERE partition_name LIKE 'SYS%' AND table_name in ('DETAIL') AND table_owner IN ('SCOTT'))
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
--table_name in ('TRANSACTIONS','ADJUSTMENT') AND table_owner IN ('SCOTT'))
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
             WHERE partition_name LIKE 'SYS%' AND table_owner IN ('SCOTT') AND table_name IN ('HISTORY'))
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
             WHERE  partition_name LIKE 'SYS%' AND table_name NOT IN ('TRANSACTIONS','HISTORY')
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
  (sqlplus -s ${CRED} as sysdba <<! 
SET SERVEROUT ON SIZE UNLIMITED
SET FEED OFF
SET HEAD OFF
SET LINES 200
ALTER SESSION SET DDL_LOCK_TIMEOUT=300
-- 30 day retention

SELECT 'alter table SCOTT.LOG drop partition '||partition_name||' update global indexes;' FROM dba_tab_partitions p WHERE table_owner = 'SCOTT' AND table_name = 'LOG' AND partition_name < (SELECT 'LOG_'||to_char(SYSDATE - 31,'YYYY_MMDD') FROM dual);

-- 60 day retention
SELECT 'alter table SCOTT.EMAIL_QUEUE drop partition '||partition_name||' update global indexes;' FROM dba_tab_partitions p WHERE table_owner = 'SCOTT' AND table_name = 'EMAIL_QUEUE' AND partition_name < (SELECT 'EMAIL_QUEUE_'||to_char(SYSDATE - 62,'YYYY_MMDD') FROM dual);

-- 120 day retention
SELECT 'alter table SCOTT.REQUEST_LOG drop partition '||partition_name||' update global indexes;' FROM dba_tab_partitions p WHERE table_owner = 'SCOTT' AND table_name = 'REQUEST_LOG' AND partition_name < (SELECT 'REQUEST_LOG_'||to_char(SYSDATE - 120,'YYYY_MMDD') FROM dual);

-- 365 day retention
SELECT 'alter table SCOTT.HISTORY drop partition '||partition_name||' update global indexes;' FROM dba_tab_partitions p WHERE table_owner = 'SCOTT' AND table_name = 'HISTORY' AND partition_name < (SELECT 'HISTORY_'||to_char(SYSDATE - 365,'YYYY_MM') FROM dual);

exit
!
) > ${DROP_SQL_NAME}
}

if [ -s ${SQL_NAME} ] ; then
  cat ${SQL_NAME}
  (sqlplus -s ${CRED} as sysdba <<! 
ALTER SESSION SET DDL_LOCK_TIMEOUT=300
@${SQL_NAME}
exit
!
) >${CMD_OUTPUT_NAME}
else
  rm ${SQL_NAME}
fi

# Purge old partitions if -p was specified
# explicitly runs dbms_part.cleanup_gidx to force the coalese cleanup to happen now
if [ -n "${PURGE_OLD}" ] ; then
  drop_old_partitions
  if [ -s ${DROP_SQL_NAME} ] ; then
    cat ${DROP_SQL_NAME}
    (sqlplus -s ${CRED} as sysdba <<!
ALTER SESSION SET DDL_LOCK_TIMEOUT=300
@${DROP_SQL_NAME}
exec dbms_part.cleanup_gidx
exit
!
) >>${CMD_OUTPUT_NAME}
  else
    rm ${DROP_SQL_NAME}
  fi
fi

