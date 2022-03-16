. ora_funcs.sh
echo test_connect $1
if test_connect $1 ; then
 echo "true"
else
 echo "false"
fi
echo is_standby $1
if is_standby $1 ; then
 echo "true"
else
 echo "false"
fi
echo is_clonedb $1
if is_clonedb $1 ; then
 echo "true"
else
 echo "false"
fi
echo dbname $1
if dbname $1 ; then
 echo "true"
else
 echo "false"
fi
echo pdb_exists $1
if pdb_exists $1 ; then
 echo "true"
else
 echo "false"
fi
echo is_pdb_open $1
if is_pdb_open $1 ; then
 echo "true"
else
 echo "false"
fi
