#!/bin/sh
if [ "$1" != "" ]; then
  openedge_db="/var/lib/openedge/data/$OPENEDGE_DB"
  proutil -i -rx ${openedge_db} -C idxbuild table $1 -TB 64 -TM 32 -B 1000 -SG 64 ${binary_options}
else
  echo "Usage: reindex-table {tablename} {binary_options}"
fi
