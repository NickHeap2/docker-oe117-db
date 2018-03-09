#!/bin/sh

set -e

# set option so that no matches doesn't match itself
shopt -s nullglob

signal_handler() {
    echo "$(date +%F_%T) Shutting down database..." 
    # call proshut
    proshut -by ${openedge_db}

    # graceful shutdown so exit with 0
    exit 0
}
# trap SIGTERM and call the handler to cleanup processes
trap 'kill ${!}; signal_handler' SIGTERM SIGINT

# set vars
openedge_db="/var/lib/openedge/data/$OPENEDGE_DB"
procure_error_log="/var/lib/openedge/data/init/errors/procure.e"

minport="$OPENEDGE_MINPORT"
maxport="$OPENEDGE_MAXPORT"
num_users="$OPENEDGE_NUM_USERS"
date_format="$OPENEDGE_DATE_FORMAT"
locks="$OPENEDGE_LOCKS"
buffers="$OPENEDGE_BUFFERS"
broker_port="$OPENEDGE_BROKER_PORT"
rebuild_database="$OPENEDGE_REBUILD"
db_from="$OPENEDGE_BASE"

# rebuild database?
if [ ! -z ${rebuild_database} ]
then
  echo "$(date +%F_%T) Deleting existing database '${openedge_db}'"
  rm -f ${openedge_db}*.*
fi

# do we need to create a db?
if [ ! -f ${openedge_db}.db ]
then
  # make sure errors directory exists
  mkdir -p /var/lib/openedge/data/init/errors/
  # clean it before run
  rm -f /var/lib/openedge/data/init/errors/*.e

  # create a new db from empty8
  echo "$(date +%F_%T) Creating empty database '${openedge_db}' from /usr/dlc/${db_from}..." | tee ${procure_error_log}
  prodb ${openedge_db} /usr/dlc/${db_from}
  touch ${openedge_db}.lg

  # add a SYSPROGRESS user
  pro -b -1 -db ${openedge_db} -p procure.p -param "ADD_USER,SYSPROGRESS,SYSPROGRESS,SYSPROGRESS" >> ${procure_error_log}

  # load any df's in the init folder
  for df in /var/lib/openedge/data/init/*.df; do
    echo "$(date +%F_%T) Loading df '${df}'..." | tee -a ${procure_error_log}
    pro -rx -b -1 -db ${openedge_db} -p procure.p -param "LOAD_SCHEMA,$df,NEW OBJECTS" >> ${procure_error_log}
  done

  # load sequence values from init/_seqvald.d
  if [ -f /var/lib/openedge/data/init/_seqvals.d ]
  then
    echo "$(date +%F_%T) Loading sequence current values from /var/lib/openedge/data/init/_seqvals.d..." | tee -a ${procure_error_log}
    pro -rx -b -1 -db ${openedge_db} -p procure.p -param "LOAD_SEQUENCE_VALUES,_seqvals.d,/var/lib/openedge/data/init" >> ${procure_error_log}
  fi

  # load any data in the init folder
  echo "$(date +%F_%T) Loading data from /var/lib/openedge/data/init/*.d..." | tee -a ${procure_error_log}
  pro -b -1 -db ${openedge_db} -p procure.p -param "LOAD_DATA,ALL,/var/lib/openedge/data/init" >> ${procure_error_log}

  # move any error files into the errors directory
  for error in /var/lib/openedge/data/init/*.e; do
    echo "!Errors during loading in file '${error}'!"
    mv -f ${error} /var/lib/openedge/data/init/errors/
  done

  echo "$(date +%F_%T) All loads completed."
else
  echo "$(date +%F_%T) Using existing database '${openedge_db}'."

  # do we need to clean up from a crash? (should do extra checks here) 
  if [ -f ${openedge_db}.lk ]
  then
    echo "$(date +%F_%T) Removing lock file from possible crash..."
    rm ${openedge_db}.lk
  fi

  # truncate the logfile
  echo "$(date +%F_%T) Truncating log file"
  prolog ${openedge_db} -silent
fi

# set the server args
server_args="$openedge_db -N TCP -S $broker_port -minport $minport -maxport $maxport -n $num_users -d $date_format -L $locks -B $buffers"
echo "$(date +%F_%T) Starting database server"
echo "$(date +%F_%T) using args=${server_args}"

# start the database server
proserve ${server_args} &
status=${?}
if [ ${status} -ne 0 ]
then
  echo "$(date +%F_%T) Failed to start database server: ${status}"
  exit ${status}
fi

# wait for db to be serving 
while true
do
  echo "$(date +%F_%T) Checking db status..."
  proutil ${openedge_db} -C holder || dbstatus=$? && true
  if [ ${dbstatus} -eq 16 ]
  then
    break
  fi
  sleep 1
done
# get db server pid 
pid=`ps aux|grep '[_]mpro'|awk '{print $2}'`
echo "$(date +%F_%T) Server running as pid: ${pid}"

# keep tailing log file until db server process exits
tail --pid=${pid} -f "$openedge_db".lg & wait ${!}

echo "$(date +%F_%T) Exiting with error!"

# things didn't go well
exit 1
