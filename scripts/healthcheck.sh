#!/bin/sh
openedge_db="/var/lib/openedge/data/$OPENEDGE_DB"

proutil "$openedge_db".db -C busy
if [ $? -eq 6 ]
then
  exit 0
fi
if [ $? -eq 0 ]
  exit 1
fi
exit $?