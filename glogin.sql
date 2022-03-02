--
-- Copyright (c) 1988, 2005, Oracle.  All Rights Reserved.
--
-- NAME
--   glogin.sql
--
-- DESCRIPTION
--   SQL*Plus global login "site profile" file
--
--   Add any SQL*Plus commands here that are to be executed when a
--   user starts SQL*Plus, or uses the SQL*Plus CONNECT command.
--
-- USAGE
--   This script is automatically run
--
col TABLE_NAME  format a30
col COLUMN_NAME format a30
set verify off
set term off
col con_name new_value _container_name noprint
select sys_context('userenv', 'con_name') as con_name
from dual;
set sqlprompt "_user'@'_connect_identifier':'_container_name'> '"
set verify on 
set term on
