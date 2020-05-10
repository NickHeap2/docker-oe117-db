#!/bin/sh
if [ "$1" != "" ]; then
  openedge_db="/var/lib/openedge/data/$OPENEDGE_DB"
  proutil -i -rx ${openedge_db} -C load /var/lib/openedge/data/init/$OPENEDGE_DB/$1.bd build indexes $2
else
  echo "Usage: load-table {tablename} {binary_options}"
fi
