#!/bin/bash

# Define help function
function help {
  echo "Usage: $0 [OPTIONS]"
  echo ""
  echo "OPTIONS:"
  echo "  -h, --help              Show this help message and exit"
  echo "  -r, --rds-host          RDS host"
  echo "  -p, --rds-port          RDS port"
  echo "  -d, --rds-dbname        RDS database name"
  echo "  -u, --rds-user          RDS user"
  echo "  -w, --rds-password      RDS password"
  echo "  -c, --local-container   Local Docker container name"
  echo "  -l, --local-port        Local Docker container port"
  echo "  -n, --local-dbname      Local database name"
  echo "  -s, --local-user        Local database user"
  echo "  -t, --local-password    Local database password"
  echo ""
  exit 0
}

# Parse command line options
while [[ $# -gt 0 ]]; do
  key="$1"
  case $key in
    -h|--help)
      help
      shift
      ;;
    -r|--rds-host)
      RDS_HOST="$2"
      shift
      shift
      ;;
    -p|--rds-port)
      RDS_PORT="$2"
      shift
      shift
      ;;
    -d|--rds-dbname)
      RDS_DBNAME="$2"
      shift
      shift
      ;;
    -u|--rds-user)
      RDS_USER="$2"
      shift
      shift
      ;;
    -w|--rds-password)
      RDS_PASSWORD="$2"
      shift
      shift
      ;;
    -c|--local-container)
      LOCAL_CONTAINER="$2"
      shift
      shift
      ;;
    -l|--local-port)
      LOCAL_PORT="$2"
      shift
      shift
      ;;
    -n|--local-dbname)
      LOCAL_DBNAME="$2"
      shift
      shift
      ;;
    -s|--local-user)
      LOCAL_USER="$2"
      shift
      shift
      ;;
    -t|--local-password)
      LOCAL_PASSWORD="$2"
      shift
      shift
      ;;
    *)
      echo "Unknown option: $1"
      help
      exit 1
      ;;
  esac
done

# Prompt for variable values if not provided
if [[ -z $RDS_HOST ]]; then
  read -p "Enter RDS host: " RDS_HOST
fi

if [[ -z $RDS_PORT ]]; then
  read -p "Enter RDS port: " RDS_PORT
fi

if [[ -z $RDS_DBNAME ]]; then
  read -p "Enter RDS database name: " RDS_DBNAME
fi

if [[ -z $RDS_USER ]]; then
  read -p "Enter RDS user: " RDS_USER
fi

if [[ -z $RDS_PASSWORD ]]; then
  read -p "Enter RDS password: " -s RDS_PASSWORD
  echo ""
fi

if [[ -z $LOCAL_CONTAINER ]]; then
  read -p "Enter local Docker container name: " LOCAL_CONTAINER
fi

if [[ -z $LOCAL_PORT ]]; then
  read -p "Enter local Docker container port: " LOCAL_PORT
fi

if [[ -z $LOCAL_DBNAME ]]; then
  read -p "Enter local database name: " LOCAL_DBNAME
fi

if [[ -z $LOCAL_USER ]]; then
  read -p "Enter local username : " LOCAL_USER
fi

if [[ -z $LOCAL_PASSWORD ]]; then
  read -p "Enter local database password: " -s LOCAL_PASSWORD 
fi

# Display entered variables
echo ""
echo "RDS host: $RDS_HOST"
echo "RDS port: $RDS_PORT"
echo "RDS database name: $RDS_DBNAME"
echo "RDS user: $RDS_USER"
echo "Local container name: $LOCAL_CONTAINER"
echo "Local database port: $LOCAL_PORT"
echo "Local database name: $LOCAL_DBNAME"
echo "Local database user: $LOCAL_USER"

read -p "Are you sure you want to delete the local database '$LOCAL_DBNAME'? This action cannot be undone. (y/n) " -n 1 -r
echo ""

if [[ ! $REPLY =~ ^[Yy]$ ]]
then
    echo "Aborting."
    exit 1
fi

# Dump the current version of the local database
docker exec -e PGPASSWORD=$LOCAL_PASSWORD $LOCAL_CONTAINER pg_dump -U $LOCAL_USER -d $LOCAL_DBNAME -p $LOCAL_PORT -F c -b -v -f /tmp/old_db.dump || { echo "Error: Failed to dump the local database. Aborting."; exit 1; }
docker cp $LOCAL_CONTAINER:/tmp/old_db.dump old_db.dump

# Terminate all connections to the local database
docker exec -it $LOCAL_CONTAINER psql -U $LOCAL_USER -c "SELECT pg_terminate_backend(pg_stat_activity.pid) FROM pg_stat_activity WHERE pg_stat_activity.datname = '$LOCAL_DBNAME' AND pid <> pg_backend_pid();"

# Drop the local database if it exists
docker exec -it $LOCAL_CONTAINER psql -U $LOCAL_USER -c "DROP DATABASE IF EXISTS $LOCAL_DBNAME;"

# Create a new local database
docker exec -it $LOCAL_CONTAINER psql -U $LOCAL_USER -c "CREATE DATABASE $LOCAL_DBNAME;"

# Dump the RDS database and send the output to a file on the local machine
if ! docker exec -e PGPASSWORD=$RDS_PASSWORD $LOCAL_CONTAINER sh -c "pg_dump -h $RDS_HOST -p $RDS_PORT -U $RDS_USER --dbname=$RDS_DBNAME --schema=public -w -Fc -v -f /tmp/dumpfile.dump"; then
    echo "Error: Failed to dump the RDS database. Restoring the local database."
    docker exec -it $LOCAL_CONTAINER psql -U $LOCAL_USER -c "SELECT pg_terminate_backend(pg_stat_activity.pid) FROM pg_stat_activity WHERE pg_stat_activity.datname = '$LOCAL_DBNAME' AND pid <> pg_backend_pid();"
    docker exec -it $LOCAL_CONTAINER psql -U $LOCAL_USER -c "DROP DATABASE IF EXISTS $LOCAL_DBNAME;"
    docker exec -it $LOCAL_CONTAINER psql -U $LOCAL_USER -c "CREATE DATABASE $LOCAL_DBNAME;"
    docker exec -e PGPASSWORD=$LOCAL_PASSWORD $LOCAL_CONTAINER pg_restore -U $LOCAL_USER -d $LOCAL_DBNAME -p $LOCAL_PORT -v /tmp/old_db.dump
    exit 1
fi

docker cp $LOCAL_CONTAINER:/tmp/dumpfile.dump dumpfile.dump

# Restore the dumped data to the local database running in the Docker container
if docker exec -i "$LOCAL_CONTAINER" pg_restore -d "$LOCAL_DBNAME" -U "$LOCAL_USER" -w -v --schema=public /tmp/dumpfile.dump 2>&1 | tee /dev/tty | grep -q 'warning: errors ignored on restore'; then
    echo "Successfully restored the dumped data."
else
    echo "Error: Failed to restore the dumped data with non-zero status. Rolling back to the old database."
    docker exec -i $LOCAL_CONTAINER psql -U $LOCAL_USER -c "SELECT pg_terminate_backend(pg_stat_activity.pid) FROM pg_stat_activity WHERE pg_stat_activity.datname = '$LOCAL_DBNAME' AND pid <> pg_backend_pid();"
    docker exec -i $LOCAL_CONTAINER psql -U $LOCAL_USER -c "DROP DATABASE IF EXISTS $LOCAL_DBNAME;"
    docker exec -i $LOCAL_CONTAINER psql -U $LOCAL_USER -c "CREATE DATABASE $LOCAL_DBNAME;"
    docker exec -e PGPASSWORD=$LOCAL_PASSWORD $LOCAL_CONTAINER pg_restore -U $LOCAL_USER -d $LOCAL_DBNAME -p $LOCAL_PORT -v /tmp/old_db.dump || { echo "Error: Failed to restore the old database. Aborting."; exit 1; }
fi

# Delete the local dump file
rm -f dumpfile.dump

# Delete the old local dump file
rm -f old_db.dump
