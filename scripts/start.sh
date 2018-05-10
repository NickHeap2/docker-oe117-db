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
trap 'signal_handler' SIGTERM SIGINT

# set vars
dbname="$OPENEDGE_DB"
openedge_db="/var/lib/openedge/data/$OPENEDGE_DB"
procure_error_log="/var/lib/openedge/data/init/${dbname}/errors/procure.e"

minport="$OPENEDGE_MINPORT"
maxport="$OPENEDGE_MAXPORT"
num_users="$OPENEDGE_NUM_USERS"
date_format="$OPENEDGE_DATE_FORMAT"
locks="$OPENEDGE_LOCKS"
buffers="$OPENEDGE_BUFFERS"
broker_port="$OPENEDGE_BROKER_PORT"
rebuild_database="$OPENEDGE_REBUILD"
db_from="$OPENEDGE_BASE"
is_utf8_db="$OPENEDGE_UTF8"

# should be a utf8 database?
if [ "$is_utf8_db" = true ]
then
  db_from="prolang/utf/${db_from}"
  binary_options="${binary_options} -cpinternal UTF-8 "
fi

# rebuild database?
if [ ! -z ${rebuild_database} ] && [ -f ${openedge_db}.db ]
then
  echo "$(date +%F_%T) Deleting existing database '${openedge_db}'"
  rm -f ${openedge_db}*.*
fi

# do we need to create a db?
if [ ! -f ${openedge_db}.db ]
then
  # make sure errors directory exists
  mkdir -p /var/lib/openedge/data/init/${dbname}/errors/
  # clean it before run
  rm -f /var/lib/openedge/data/init/${dbname}/errors/*\.e

  # touch ${procure_error_log}
  cd ${openedge_db%/*}
  if [ ! -f /var/lib/openedge/data/init/${dbname}/${dbname}.st ]
  then
    # create a new db from empty
    echo "$(date +%F_%T) Creating empty database '${openedge_db}' from /usr/dlc/${db_from}..." | tee -a ${procure_error_log}
    prodb ${openedge_db} /usr/dlc/${db_from}
  else
    # copy the .st to db dir
    cp /var/lib/openedge/data/init/${dbname}/${dbname}.st /var/lib/openedge/data/
    # create db structure file then copy from empty
    echo "$(date +%F_%T) Creating database structure for '${openedge_db}' from '${openedge_db}.st'..." | tee -a ${procure_error_log}
    prostrct create ${openedge_db} -blocksize 8192
    echo "$(date +%F_%T) Copying database into '${openedge_db}' from /usr/dlc/${db_from}..." | tee -a ${procure_error_log}
    procopy /usr/dlc/${db_from} ${openedge_db}
  fi
  # back to working dir
  cd $WRKDIR
  touch ${openedge_db}.lg

  # add a SYSPROGRESS user
  mpro -i -b -1 -db ${openedge_db} -p procure.p -param "ADD_USER,SYSPROGRESS,SYSPROGRESS,SYSPROGRESS" >> ${procure_error_log}

  # load any df's in the init folder
  for df in /var/lib/openedge/data/init/${dbname}/*\.df; do
    echo "$(date +%F_%T) Loading df '${df}'..." | tee -a ${procure_error_log}
    mpro -i -rx -b -1 -db ${openedge_db} -p procure.p -param "LOAD_SCHEMA,$df,NEW OBJECTS" >> ${procure_error_log}
  done

  # load sequence values from init/_seqvald.d
  if [ -f /var/lib/openedge/data/init/${dbname}/_seqvals.d ]
  then
    echo "$(date +%F_%T) Loading sequence current values from /var/lib/openedge/data/init/${dbname}/_seqvals.d..." | tee -a ${procure_error_log}
    mpro -i -rx -b -1 -db ${openedge_db} -p procure.p -param "LOAD_SEQUENCE_VALUES,_seqvals.d,/var/lib/openedge/data/init/${dbname}" >> ${procure_error_log}
  fi

  # load any binary dumps
  for bd in /var/lib/openedge/data/init/${dbname}/*\.bd; do
    idxbuild="true"
    echo "$(date +%F_%T) Loading binary dump file '${bd}'..." | tee -a ${procure_error_log}
    proutil -i ${openedge_db} -C load ${bd} ${binary_options} | tee -a ${procure_error_log}
  done
  if [ ! -z ${idxbuild} ]
  then
    echo "$(date +%F_%T) Rebuilding all indexes..." | tee -a ${procure_error_log}
    proutil -i ${openedge_db} -C idxbuild all -TB 64 -TM 32 -B 1000 -SG 64 ${binary_options} | tee -a ${procure_error_log}
  fi

  # load any data in the init folder
  for d in /var/lib/openedge/data/init/${dbname}/*\.d; do
    echo "$(date +%F_%T) Loading data from /var/lib/openedge/data/init/${dbname}/*.d..." | tee -a ${procure_error_log}
    mpro -i -b -1 -db ${openedge_db} -p procure.p -param "LOAD_DATA,ALL,/var/lib/openedge/data/init/${dbname}" >> ${procure_error_log}
    # all done in one go
    break
  done

  # move any error files into the errors directory
  for error in /var/lib/openedge/data/init/${dbname}/*\.e; do
    echo "!Errors during loading in file '${error}'!"
    mv -f ${error} /var/lib/openedge/data/init/${dbname}/errors/
  done

  echo "$(date +%F_%T) All loads completed."
else
  echo "$(date +%F_%T) Using existing database '${openedge_db}'."

  # do we need to clean up from a crash? (should do extra checks here) 
  if [ -f ${openedge_db}.lk ]
  then
    echo "$(date +%F_%T) Removing lock file from possible crash..."
    rm -f ${openedge_db}.lk
  fi

  # repair in case it isn't created by us (ignore error here)
  echo "$(date +%F_%T) Repairing db structure..."
  (cd /var/lib/openedge/data/; prostrct repair ${openedge_db}) || true

  # truncate the logfile (ignore error here)
  echo "$(date +%F_%T) Truncating log file"
  prolog ${openedge_db} -silent || true
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
# while true
# do
#   echo "$(date +%F_%T) Checking db status..."
#   proutil ${openedge_db} -C holder || dbstatus=$? && true
#   if [ ${dbstatus-0} -eq 16 ]
#   then
#     break
#   fi
#   sleep 1
# done

# get db server pid 
echo "$(date +%F_%T) Waiting for database to start..."

RETRIES=0
while true
do
  if [ "${RETRIES}" -gt 10 ]
  then
    break
  fi

  pid=`ps aux|grep '[_]mprosrv'|awk '{print $2}'`
  if [ ! -z "${pid}" ]
  then
    case "${pid}" in
      ''|*[!0-9]*) continue ;;
      *) break ;;
    esac
  fi
  sleep 1
  RETRIES=$((RETRIES+1))
done
# did we get the pid?
if [ -z "${pid}" ]
then
  echo "$(date +%F_%T) ERROR: Database process not found exiting."
  exit 1
fi

echo "$(date +%F_%T) Server running as pid: ${pid}"

# keep tailing log file until db server process exits
# load sequence values from init/_seqvald.d
if [ -f "${openedge_db}".lg ]
then
  tail --pid=${pid} -f "${openedge_db}".lg & wait ${!}
else
  tail -f /dev/null & wait ${!}
fi

echo "$(date +%F_%T) Exiting with error!"

# things didn't go well
exit 1
