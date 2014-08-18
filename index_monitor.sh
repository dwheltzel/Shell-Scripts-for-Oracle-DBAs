# index_monitor.sh - Manages Oracle built in index monitoring
#
# written by Dennis Heltzel

EXEC_CMD="sqlplus -s / as sysdba"
CMD_FILE=index_monitor-${ORACLE_SID}.sql
:> $CMD_FILE

usage() {
  echo "Usage: $0 [-r] [-n] [-v]"
  echo "  -r - only report on unused indexes, no changes are made"
  echo "  -n - new indexes, monitor any indexes that have never been monitored"
  echo "  -v - create the view (only needed on the first run)"
  exit 1
}

install_view() {
  sqlplus -s / as sysdba <<!
CREATE VIEW sys.v\$all_object_usage (owner, index_name, table_name, monitoring, used, start_monitoring, end_monitoring )
AS
SELECT do.owner, io.name, t.name, DECODE (BITAND (i.flags, 65536), 0, 'NO', 'YES'),
DECODE (BITAND (ou.flags, 1), 0, 'NO', 'YES'), ou.start_monitoring, ou.end_monitoring
FROM sys.obj\$ io, sys.obj\$ t, sys.ind\$ i, sys.object_usage ou, dba_objects do
WHERE i.obj# = ou.obj# AND io.obj# = ou.obj# AND t.obj# = i.bo# AND ou.obj# = do.object_id;
EXIT
!
}

# Start monitoring any new indexes
turn_on_monitoring() {
  (sqlplus -s / as sysdba <<!
set lines 100
set pages 0
set feed off
PROMPT set pages 0
PROMPT set echo on
SELECT 'alter index '||owner||'."'||index_name||'" monitoring usage;' "Monitoring changes" FROM dba_indexes
 WHERE index_type IN ('NORMAL', 'BITMAP') AND uniqueness = 'NONUNIQUE'
   AND owner NOT LIKE '%SYS%' AND owner NOT LIKE 'APEX%' AND owner NOT IN ('OUTLN', 'PUBLIC', 'DBSNMP', 'XDB', 'ORDDATA')
   AND (owner, index_name) NOT IN (SELECT owner, index_name FROM sys.v\$all_object_usage)
MINUS
SELECT 'alter index '||index_owner||'."'||index_name||'" monitoring usage;' FROM dba_ind_columns c
 WHERE (c.table_owner, c.table_name, c.column_name, c.column_position) IN
   (SELECT c.owner, c.table_name, cc.column_name, cc.position
     FROM dba_constraints  c, dba_constraints  r, dba_cons_columns cc, dba_cons_columns rc
     WHERE c.constraint_type = 'R' AND c.r_owner = r.owner AND c.r_constraint_name = r.constraint_name
       AND c.constraint_name = cc.constraint_name AND c.owner = cc.owner AND r.constraint_name = rc.constraint_name
       AND r.owner = rc.owner AND cc.position = rc.position
       AND c.owner NOT LIKE '%SYS%' AND c.owner NOT LIKE 'APEX%' AND c.owner NOT IN ('OUTLN', 'PUBLIC', 'DBSNMP', 'XDB', 'ORDDATA'));
prompt exit
EXIT
!
)
}

# Turn off monitoring of used indexes
turn_off_monitoring() {
  (sqlplus -s / as sysdba <<!
set lines 100
set pages 0
set feed off
PROMPT set pages 0
PROMPT set echo on
select 'alter index ' || owner || '."' || index_name || '" nomonitoring usage;' from sys.v\$all_object_usage where used = 'YES' and monitoring = 'YES';
prompt exit
EXIT
!
)
}

# Unused Index Report
report() {
  export REP_NAME=unused_indexes.lst
  tty -s && echo "Unused index report: ${REP_NAME}"
  (sqlplus -s / as sysdba <<!
set lines 200
set pages 0
select owner || '.' || index_name || ' on ' || table_name || ' not used since ' || to_char(trunc(to_date(start_monitoring,'MM-DD-YYYY HH24:MI:SS')),'MM/DD/YY')
  from sys.v\$all_object_usage
 where used = 'NO' and monitoring = 'YES' order by trunc(to_date(start_monitoring,'MM-DD-YYYY HH24:MI:SS')), owner, table_name, index_name;
EXIT
!
) > ${REP_NAME}
}

# Handle parameters
while getopts ":rnv" opt; do
  case $opt in
    r)
      EXEC_CMD="true"
      ;;
    n)
      # only run this if requested, it is slow
      turn_on_monitoring > $CMD_FILE
      ;;
    v)
      install_view
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

# always run this
turn_off_monitoring >> $CMD_FILE

LNCNT=`wc -l $CMD_FILE|cut -f1 -d" "`
if [ "$LNCNT" -gt 3 ] ; then
  more $CMD_FILE
  $EXEC_CMD @$CMD_FILE
  echo " "
fi

# always run the report
report
