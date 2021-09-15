#!/bin/bash
#Description: This script is a wrapper that utilizes Oracle Database Flashback Log features for portal releases
#Requirements: The script should be run as software owner on the oracle db server. RAC is assumed.
#Input: Update the dblist parameter below to specify list of databases for flashback ops. 
#       Value is single space separated list of db names(not instance name).
#
# Modified $Author: dheltzel $ 
# Date $Date: 2014-02-04 20:33:07 +0000 (Tue, 04 Feb 2014) $

#Estimate fra storage room required to retain flashback and archivelogs for $numdays days
numdays=8
#Check the awr for $trenddays no. of days to figure out approx transaction activity per day
trenddays=7

#Databases for flashback operations
dblist="stvpn2 stedw stp03 staglk"
#sqlplus commands for each database
sqlpluscmd="sqlplus -SL / as sysdba"

usage() {
  echo "Usage: $0 [size|on|rollback|off|savestate|reset|check]"
  echo "  size - get size estimate for FRA"
  echo "  on - sets a guaranteed restore point"
  echo "  rollback - rollback to restore point"
  echo "  off - remotes the guaranteed restore point"
  echo "  savestate - capture db logical state"
  echo "  reset - drop any existing restore point and set a new one"
  echo "  check - report on the restore point status"
  exit 1
}

checkflashbackenabled(){
  #Not implemented
  q="select flashback_on from v\$database";
}

checkflashbacksizing(){
  echo "1. Estimated Flashback logs size for $numdays days"
  numdays=$1
  trenddays=$2
  $3 $4 $5 $6 $7 <<EOF
set heading off feedback off pages 0
select round(avg(v1.csredo-v2.csredo))*$numdays||' MB' avgredosizemb
from
(
select btime,round(sum(credo)/1024/1024) csredo
from(
  select trunc(a.begin_interval_time) btime,max(b.value) credo
  from dba_hist_sysstat b, dba_hist_snapshot a
  where a.snap_id=b.snap_id and a.instance_number=b.instance_number
        and a.begin_interval_time>sysdate-$trenddays and b.stat_name='redo size'
  group by trunc(a.begin_interval_time), a.instance_number)
group by btime ) v1,
(
select btime,round(sum(credo)/1024/1024) csredo
from(
  select trunc(a.begin_interval_time) btime,max(b.value) credo
  from dba_hist_sysstat b, dba_hist_snapshot a
  where a.snap_id=b.snap_id and a.instance_number=b.instance_number
        and a.begin_interval_time>sysdate-$trenddays and b.stat_name='redo size'
  group by trunc(a.begin_interval_time), a.instance_number)
group by btime ) v2
where v1.btime=v2.btime+1;
exit
EOF
}

checkflashbackfreespacerequirement(){
  echo "2. Estimated amount of free space required in FRA for $numdays days"
  numdays=$1
  trenddays=$2
  $3 $4 $5  $6 $7 <<EOF
set heading off feedback off pages 0
select round(avg(v1.csredo-v2.csredo))*$numdays*2||' MB' avgredosizemb
from
(
select btime,round(sum(credo)/1024/1024) csredo
from(
  select trunc(a.begin_interval_time) btime,max(b.value) credo
  from dba_hist_sysstat b, dba_hist_snapshot a
  where a.snap_id=b.snap_id and a.instance_number=b.instance_number
    and a.begin_interval_time>sysdate-$trenddays and b.stat_name='redo size'
  group by trunc(a.begin_interval_time), a.instance_number)
group by btime ) v1,
(
select btime,round(sum(credo)/1024/1024) csredo
from(
  select trunc(a.begin_interval_time) btime,max(b.value) credo
  from dba_hist_sysstat b, dba_hist_snapshot a
  where a.snap_id=b.snap_id and a.instance_number=b.instance_number
    and a.begin_interval_time>sysdate-$trenddays and b.stat_name='redo size'
  group by trunc(a.begin_interval_time), a.instance_number)
group by btime ) v2
where v1.btime=v2.btime+1;
exit
EOF
}

checkfrafreespace(){
  echo "3. Check current free space in FRA"
  $1 $2 $3 $4 $5 <<EOF
set heading off feedback off pagesize 0
select  round((100-usedspace)*frasize/1024/1024/100)||' MB' flashbackfreespaceMB
from
(select round(sum(PERCENT_SPACE_USED)-sum(percent_space_reclaimable)) usedspace from v\$recovery_area_usage),
(select value frasize from v\$parameter where name='db_recovery_file_dest_size');
exit
EOF
}

enableflashback(){
 $1 $2 $3 $4 $5 <<EOF
create restore point before_changes guarantee flashback database;
exit
EOF
}

stopflashback(){
 $1 $2 $3 $4 $5 <<EOF
drop restore point before_changes;
exit
EOF
}

reset_restorepoint(){
 $1 $2 $3 $4 $5 <<EOF
drop restore point before_changes;
create restore point before_changes guarantee flashback database;
exit
EOF
}

checkrestorepoint(){
 $1 $2 $3 $4 $5 <<EOF
SET PAGES 0
SELECT sys_context('USERENV', 'DB_NAME')||': Restore point '||name||' set at '||time FROM v\$restore_point;
exit
EOF
}

spoollogicalstate(){
 echo "Saving report.."
 $1 $2 $3 $4 $5 <<EOF
set termout on heading off feedback off
select 'dbflashback_'||name||'_'||to_char(sysdate,'yyyymmddhh24miss')||'.txt' reportname1
from v\$database;
exit
EOF

 $1 $2 $3 $4 $5 <<EOF 1> /dev/null
set termout off
col reportname1 new_value reportname
select 'dbflashback_'||name||'_'||to_char(sysdate,'yyyymmddhh24miss')||'.txt' reportname1
from v\$database;
spool &reportname

set lines 200 pages 0 trimspool on
prompt Object counts
select count(1) from dba_objects;
prompt Invalid objects(object_name,owner,object_type)
col object_name for a30
select object_name,owner,object_type from dba_objects where status!='VALID' order by owner,object_name,object_type;
prompt Errors(owner,name,text)
col text for a100
select owner,name,text from dba_errors order by owner,name;
prompt Sequences(owner,name,lastnumber)
select sequence_owner,sequence_name,last_number from dba_sequences where sequence_owner not in ('SYS','SYSTEM','DBSNMP') order by 1,2;
col username for a15
col module for a30
col machine for a30
prompt Connections(user,module,machine)
select username,substr(module||':'||program,1,30) module,machine from gv\$session where type='USER' order by username,module;
spool off
exit
EOF
}

flashbackdb(){
 db=$(dbname $1 $2 $3 $4 $5)
 $1 $2 $3 $4 $5 <<EOF
 prompt Disable job queue..
 alter system set job_queue_processes=0 scope=both sid='*';
 prompt Stop shared servers..
 alter system set shared_servers=0 scope=memory sid='*';
EOF
 echo "Stopping db.. " $db
 srvctl stop database -d $db -o immediate
 $1 $2 $3 $4 $5 <<EOF
 startup mount
 flashback database to restore point before_changes; 
 alter database open resetlogs;
 shutdown immediate
EOF
 echo "Starting db.. " $db
 srvctl start database -d $db 
 $1 $2 $3 $4 $5 <<EOF
 prompt Enable job queue..
 alter system set job_queue_processes=10 scope=both sid='*';
EOF
}

# Get sizing requirements for FRA
getsizing(){
checkflashbacksizing $1 $2 $3 $4 $5 $6 $7
checkflashbackfreespacerequirement $1 $2 $3 $4 $5 $6 $7
checkfrafreespace $3 $4 $5 $6 $7
}

dbname(){
 $1 $2 $3 $4 $5 <<EOF
set heading off feedback off pagesize 0
select name from v\$database;
exit
EOF
}

case $1 in
size)
  for i in $dblist; do
    oid=$(ps -ef|grep pmon|grep $i|grep -v grep|cut -d'_' -f3)
    export ORACLE_SID=$oid
    if [ -n "$ORACLE_SID" ]; then 
      echo "---------------------------------------------"
      dbname $sqlpluscmd
      getsizing $numdays $trenddays $sqlpluscmd
    else
      echo "DB $i not running"  
    fi
  done
  ;;
on)
  echo "Turn on flashback"
  for i in $dblist; do
    oid=$(ps -ef|grep pmon|grep $i|grep -v grep|cut -d'_' -f3)
    export ORACLE_SID=$oid
    if [ -n "$ORACLE_SID" ]; then 
      echo "---------------------------------------------"
      dbname $sqlpluscmd
      enableflashback $sqlpluscmd
    else
      echo "DB $i not running"  
    fi
  done
  ;;
off)
  echo "Turn off flashback"
  for i in $dblist; do
    oid=$(ps -ef|grep pmon|grep $i|grep -v grep|cut -d'_' -f3)
    export ORACLE_SID=$oid
    if [ -n "$ORACLE_SID" ]; then 
      echo "---------------------------------------------"
      dbname $sqlpluscmd
      stopflashback $sqlpluscmd
    else
      echo "DB $i not running"
    fi
  done
  ;;
savestate)
  echo "Spooling out db state"
  for i in $dblist; do
    oid=$(ps -ef|grep pmon|grep $i|grep -v grep|cut -d'_' -f3)
    export ORACLE_SID=$oid
    if [ -n "$ORACLE_SID" ]; then
      echo "---------------------------------------------"
      dbname $sqlpluscmd
      spoollogicalstate $sqlpluscmd
    else
      echo "DB $i is not running"
    fi 
  done  
  ;;
rollback)
  echo "Do rollback to restore point"
  for i in $dblist; do
    oid=$(ps -ef|grep pmon|grep $i|grep -v grep|cut -d'_' -f3)
    export ORACLE_SID=$oid
    if [ -n "$ORACLE_SID" ]; then 
      echo "---------------------------------------------"
      dbname $sqlpluscmd
      flashbackdb $sqlpluscmd
    else
      echo "DB $i not running"
    fi
  done
  ;;
reset)
  echo "Reset the restore point"
  for i in $dblist; do
    oid=$(ps -ef|grep pmon|grep $i|grep -v grep|cut -d'_' -f3)
    export ORACLE_SID=$oid
    if [ -n "$ORACLE_SID" ]; then 
      echo "---------------------------------------------"
      dbname $sqlpluscmd
      reset_restorepoint $sqlpluscmd
    else
      echo "DB $i not running"
    fi
  done
  ;;
check)
  echo "Report on the restore points"
  for i in $dblist; do
    oid=$(ps -ef|grep pmon|grep $i|grep -v grep|cut -d'_' -f3)
    export ORACLE_SID=$oid
    if [ -n "$ORACLE_SID" ]; then 
      checkrestorepoint $sqlpluscmd
    else
      echo "DB $i not running"
    fi
  done
  ;;
*)
  usage
  ;;
esac

