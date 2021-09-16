# Manage tablespaces and partitions created by incremental partitioning
#
# Modified $Author: dheltzel $ 

CRED=${CRED:-/}
RUN_DDL=Y

TS_SUFFIX=`date '+%Y%m'`
usage() {
  echo "Usage: $0 [-d database name] [-s suffix for tablespaces]"
  echo "  -d database name - defaults to $ORACLE_SID"
  echo "  -s suffix for tablespaces - defaults to $TS_SUFFIX"
  exit 1
}

# Handle parameters
while getopts ":d:s:" opt; do
  case $opt in
    d)
      TWO_TASK=$OPTARG
      DB_NAME=$OPTARG
      ;;
    s)
      TS_SUFFIX=$OPTARG
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
BASE_NAME=ManageTS${DB_NAME}-`date "+%y%m%d%H%M"`
REPORT_NAME=${BASE_NAME}.lst
SQL_NAME=${BASE_NAME}.sql
CMD_OUTPUT_NAME=${BASE_NAME}.out
#echo "DB_NAME: ${DB_NAME}"
#echo "REPORT_NAME: ${REPORT_NAME}"
#echo "SQL_NAME: ${SQL_NAME}"

(sqlplus -s ${CRED} as sysdba <<! 
SET SERVEROUT ON SIZE UNLIMITED
SET FEED OFF
SET HEAD OFF
SET PAGES 0
SET LINES 200
SELECT 'create bigfile tablespace ETL_${TS_SUFFIX};' FROM dual
UNION ALL
SELECT 'create bigfile tablespace APP_${TS_SUFFIX};' FROM dual
MINUS
SELECT 'create bigfile tablespace '||tablespace_name||';' FROM dba_tablespaces;
-- change default tablespaces for partitioned tables (reference only,over-ridden by "store in" clause)
(SELECT 'alter table '||owner||'.'||table_name||' MODIFY DEFAULT ATTRIBUTES TABLESPACE ETL_${TS_SUFFIX};' FROM dba_tables WHERE partitioned = 'YES' AND owner IN ('DE','RE','VIZ')
MINUS
SELECT 'alter table '||owner||'.'||table_name||' MODIFY DEFAULT ATTRIBUTES TABLESPACE ETL_${TS_SUFFIX};' FROM dba_part_tables WHERE owner IN ('DE','RE','VIZ') AND def_tablespace_name IN ('ETL_${TS_SUFFIX}','SHORT_TERM'))
union all
(SELECT 'alter table '||owner||'.'||table_name||' MODIFY DEFAULT ATTRIBUTES TABLESPACE APP_${TS_SUFFIX};'
  FROM dba_tables WHERE partitioned = 'YES' AND owner IN ('BIZ','BOARDING','CCONNECT','ENT_SECURITY','FTSV1','FTSV2','HPP','KEYCLOAK2','LOOKUP','MEMS')
MINUS
SELECT 'alter table '||owner||'.'||table_name||' MODIFY DEFAULT ATTRIBUTES TABLESPACE APP_${TS_SUFFIX};'
  FROM dba_part_tables WHERE owner IN ('BIZ','BOARDING','CCONNECT','ENT_SECURITY','FTSV1','FTSV2','HPP','KEYCLOAK2','LOOKUP','MEMS') AND def_tablespace_name IN ('APP_${TS_SUFFIX}','SHORT_TERM'));

-- change "real" default tablespaces for partitioned tables
(SELECT 'alter table '||owner||'.'||table_name||' set store in (ETL_${TS_SUFFIX});' FROM dba_tables WHERE partitioned = 'YES' AND owner IN ('DE','RE','VIZ')
MINUS
SELECT 'alter table '||o.owner||'.'||o.object_name||' set store in (ETL_${TS_SUFFIX});' FROM sys.insert_tsn_list$ l JOIN sys.ts$ ts ON (ts.ts# = l.ts#) JOIN dba_objects o ON (o.object_id = l.bo#)
 WHERE ts.name IN ('ETL_${TS_SUFFIX}','SHORT_TERM') AND o.owner IN ('DE','RE','VIZ'))
union all
(SELECT 'alter table '||owner||'.'||table_name||' set store in (APP_${TS_SUFFIX});'
  FROM dba_tables WHERE partitioned = 'YES' AND owner IN ('BIZ','BOARDING','CCONNECT','ENT_SECURITY','FTSV1','FTSV2','HPP','KEYCLOAK2','LOOKUP','MEMS')
MINUS
SELECT 'alter table '||o.owner||'.'||o.object_name||' set store in (APP_${TS_SUFFIX});' FROM sys.insert_tsn_list$ l JOIN sys.ts$ ts ON (ts.ts# = l.ts#) JOIN dba_objects o ON (o.object_id = l.bo#)
 WHERE ts.name IN ('APP_${TS_SUFFIX}','SHORT_TERM') AND o.owner IN ('BIZ','BOARDING','CCONNECT','ENT_SECURITY','FTSV1','FTSV2','HPP','KEYCLOAK2','LOOKUP','MEMS'));
exit
!
) > ${SQL_NAME}

ls -l ${SQL_NAME}

SQL2_NAME=${BASE_NAME}-ind.sql
(sqlplus -s ${CRED} as sysdba <<! 
SET SERVEROUT ON SIZE UNLIMITED
SET FEED OFF
SET HEAD OFF
SET PAGES 0
SET LINES 200
-- change the indexes to the new partitions
SELECT 'alter index '||i.owner||'.'||i.index_name||' MODIFY DEFAULT ATTRIBUTES TABLESPACE '||t.def_tablespace_name||';'
  FROM dba_part_indexes i JOIN dba_part_tables t ON (i.owner = t.owner AND i.table_name = t.table_name)
 WHERE i.owner NOT LIKE 'SYS%' AND i.index_name NOT LIKE 'SYS%' AND i.def_tablespace_name <> t.def_tablespace_name ORDER BY 1;
exit
!
) > ${SQL2_NAME}

ls -l ${SQL2_NAME}
