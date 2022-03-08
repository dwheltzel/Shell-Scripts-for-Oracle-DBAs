# LOBcheck.sh - Shows the amount of wasted space in the largest n lobs in a schema or entire database
# 
# Author: Dennis Heltzel 03/8/2022

usage() {
  echo "Usage: $0 [-d database] [-s schema] [-n number of LOB's]"
  echo "  -d database name - defaults to ${DBNAME}"
  echo "  -s schema - name of the schema, defaults to all non-system schemas"
  echo "  -n number of LOB's to look at - checks the top n LOB's, defaults to ${LOBCNT}"
  exit 1
}

LOBCNT=10
DBNAME=${ORACLE_PDB_SID:-${ORACLE_SID}}
SCHEMA="ALL_SCHEMAS"
CONN_STR='sqlplus -s / as sysdba'
RUNDIR=`dirname "${BASH_SOURCE[0]}"`
. ${RUNDIR}/ora_funcs.sh

# Handle parameters
while getopts ":d:s:n:" opt; do
  case $opt in
    d)
      DBNAME=$OPTARG
      ;;
    s)
      SCHEMA=$OPTARG
      ;;
    n)
      LOBCNT=$OPTARG
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

WORK_DIR=${WORK_DIR:-`pwd`}
ORACLE_PDB_SID=${DBNAME}
echo "DBNAME=${DBNAME}:ORACLE_SID=${ORACLE_SID}:ORACLE_PDB_SID=${ORACLE_PDB_SID}"
LOB_LIST=${WORK_DIR}/LOB-${SCHEMA}.list

tty -s && echo "Generating list of LOB's from ${SCHEMA} in ${ORACLE_PDB_SID}: ${LOB_LIST}"
(${CONN_STR} <<!
set pages 0
set feed off
set head off
set lines 280
select * from (select l.owner||'.'||l.table_name "Table",l.column_name,round(sum(bytes)/1024/1024) MB --,count(*)
  from dba_lobs l join dba_segments s on (s.segment_name = l.segment_name)
 where s.segment_type like 'LOB%' and l.owner like 'AGI%'
 group by l.owner, l.table_name,l.column_name
 order by 3 desc) where rownum < ${LOBCNT} + 1;
exit
!
) > ${LOB_LIST}


