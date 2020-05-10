#!/bin/sh
if [ "$1" != "" ]; then
  export display_banner=false
  openedge_db="/var/lib/openedge/data/$OPENEDGE_DB"
  mpro -i -rx -db ${openedge_db} -disabledeltrig -p /var/lib/openedge/base/procure.p -param "EMPTY_DATA,$1"
else
  echo "Usage: empty-table {tablename|all}"
fi
