#!/usr/bin/env bash

if [ "$PERSIST_MODE" = "@cassandra" ]
then
  cat <<EOF > ${HANLON_WEB_PATH}/config/cassandra_db.conf
hosts: $CASSANDRA_PORT_9042_TCP_ADDR
port: 9042
keyspace: 'project_hanlon'
repl_strategy: $REPL_STRATEGY
repl_factor: $REPL_FACTOR
EOF
  ./hanlon_init -j '{"persist_mode": "'$PERSIST_MODE'", "persist_options_file": "cassandra_db.conf", "hanlon_static_path": "'$HANLON_STATIC_PATH'", "hanlon_subnets": "'$HANLON_SUBNETS'", "hanlon_server": "'$DOCKER_HOST'"}'

else
  ./hanlon_init -j '{"hanlon_static_path": "'$HANLON_STATIC_PATH'", "hanlon_subnets": "'$HANLON_SUBNETS'", "hanlon_server": "'$DOCKER_HOST'", "persist_host": "'$MONGO_PORT_27017_TCP_ADDR'"}'
fi

cd ${HANLON_WEB_PATH}

PORT=`awk '/api_port/ {print $2}' config/hanlon_server.conf`
puma -p ${PORT} $@ 2>&1 | tee /tmp/puma.log
