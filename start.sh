#!/bin/sh

set -e

signal_handler() {
    echo "Shutting down database..." 
    # call proshut
    proshut -by ${openedge_db}

    # graceful shutdown so exit with 0
    exit 0
}
# trap SIGTERM and call the handler to cleanup processes
trap 'kill ${!}; signal_handler' SIGTERM SIGINT

# set vars
openedge_db="/var/lib/openedge/data/$OPENEDGE_DB"
minport="$OPENEDGE_MINPORT"
maxport="$OPENEDGE_MAXPORT"
num_users="$OPENEDGE_NUM_USERS"
date_format="$OPENEDGE_DATE_FORMAT"
locks="$OPENEDGE_LOCKS"
buffers="$OPENEDGE_BUFFERS"
broker_port="$OPENEDGE_BROKER_PORT"

# do we need to create a db?
if [ ! -f ${openedge_db}.db ]
then
  # create a new db from empty8
  prodb ${openedge_db} /usr/dlc/empty8
  touch ${openedge_db}.lg
fi

# do we need to clean up from a crash? (should do extra checks here) 
if [ -f ${openedge_db}.lk ]
then
  rm ${openedge_db}.lk
fi

# truncate the logfile
echo "Truncating log file at $(date +%F_%T)"
prolog ${openedge_db} -silent

# set the server args
server_args="$openedge_db -N TCP -S $broker_port -minport $minport -maxport $maxport -n $num_users -d $date_format -L $locks -B $buffers"
echo "Starting database server at $(date +%F_%T)"
echo "using args=${server_args}"

# start the database server
proserve ${server_args} &
status=${?}
if [ ${status} -ne 0 ]
then
  echo "Failed to start database server: ${status}"
  exit ${status}
fi

# wait for db to be serving 
while true
do
  echo "Checking db status..."
  proutil ${openedge_db} -C holder || dbstatus=$? && true
  if [ ${dbstatus} -eq 16 ]
  then
    break
  fi
  sleep 1
done
# get db server pid 
pid=`ps aux|grep '[_]mpro'|awk '{print $2}'`
echo "Server running as pid: ${pid}"

# keep tailing log file until db server process exits
tail --pid=${pid} -f "$openedge_db".lg & wait ${!}

# things didn't go well
exit 1
