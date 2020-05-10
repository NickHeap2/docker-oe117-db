#!/bin/sh

# set option so that no matches doesn't match itself
shopt -s nullglob

dbname="$OPENEDGE_DB"
openedge_db="/var/lib/openedge/data/$OPENEDGE_DB"

# add a SYSPROGRESS user
for user in /var/lib/openedge/data/init/${dbname}/*\.user; do
  # read values from file
  add_username=`sed '1q;d' ${user}`
  add_password=`sed '2q;d' ${user}`
  echo "Adding user ${add_username}..."
  mpro -i -b -db ${openedge_db} -p procure.p -param "ADD_USER,${add_username},${add_username},${add_password}"
done
