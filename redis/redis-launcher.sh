#!/bin/bash

echo "Starting redis launcher"
echo "Setting labels"
label-updater.sh &

echo "Selecting proper service to execute"
# Define config file locations
SENTINEL_CONF=/etc/redis/sentinel.conf
MASTER_CONF=/etc/redis/master.conf
SLAVE_CONF=/etc/redis/slave.conf

# Adapt to dynamically named env vars
ENV_VAR_PREFIX=`echo $REDIS_CHART_PREFIX|awk '{print toupper($0)}'|sed 's/-/_/g'`
PORTVAR="${ENV_VAR_PREFIX}MASTER_SVC_SERVICE_PORT"
HOSTVAR="${ENV_VAR_PREFIX}MASTER_SVC_SERVICE_HOST"
MASTER_LB_PORT="${!PORTVAR}"
MASTER_LB_HOST="${!HOSTVAR}"

# Launch master when `MASTER` environment variable is set
function launchmaster() {
  # If we know we're a master, update the labels right away
  kubectl label --overwrite pod $HOSTNAME redis-role="master"
  echo "Using config file $MASTER_CONF"
  if [[ ! -e /redis-master-data ]]; then
    echo "Redis master data doesn't exist, data won't be persistent!"
    mkdir /redis-master-data
  fi
  redis-server $MASTER_CONF --protected-mode no $@
}

# Launch sentinel when `SENTINEL` environment variable is set
function launchsentinel() {
  # If we know we're a sentinel, update the labels right away
  kubectl label --overwrite pod $HOSTNAME redis-role="sentinel"  
  echo "Using config file $SENTINEL_CONF"

  while true; do
    # The sentinels must wait for a load-balanced master to appear then ask it for its actual IP.
    MASTER_IP=$(kubectl get pod -o jsonpath='{range .items[*]}{.metadata.name} {..podIP}{"\n"}{end}' -l redis-role=master|grep $REDIS_CHART_PREFIX|awk '{print $2}'|xargs)
    echo "Current master is $MASTER_IP"

    if [[ -z ${MASTER_IP} ]]; then
      continue
    fi

    timeout -t 3 redis-cli -h ${MASTER_IP} -p ${MASTER_LB_PORT} INFO
    if [[ "$?" == "0" ]]; then
      break
    fi
    echo "Connecting to master failed.  Waiting..."
    sleep 10
  done

  echo "sentinel monitor mymaster ${MASTER_IP} ${MASTER_LB_PORT} 2" > ${SENTINEL_CONF}
  echo "sentinel down-after-milliseconds mymaster 15000" >> ${SENTINEL_CONF}
  echo "sentinel failover-timeout mymaster 30000" >> ${SENTINEL_CONF}
  echo "sentinel parallel-syncs mymaster 10" >> ${SENTINEL_CONF}
  echo "bind 0.0.0.0" >> ${SENTINEL_CONF}
  echo "sentinel client-reconfig-script mymaster /usr/local/bin/promote.sh" >> ${SENTINEL_CONF}

  redis-sentinel ${SENTINEL_CONF} --protected-mode no $@
}

# Launch slave when `SLAVE` environment variable is set
function launchslave() {
  kubectl label --overwrite pod $HOSTNAME redis-role="slave"
  echo "Using config file $SLAVE_CONF"
  if [[ ! -e /redis-master-data ]]; then
    echo "Redis master data doesn't exist, data won't be persistent!"
    mkdir /redis-master-data
  fi

  i=0
  while true; do
    master=${MASTER_LB_HOST}
    timeout -t 3 redis-cli -h ${master} -p ${MASTER_LB_PORT} INFO
    if [[ "$?" == "0" ]]; then
      break
    fi
    i=$((i+1))
    if [[ "$i" -gt "30" ]]; then
      echo "Exiting after too many attempts"
      exit 1
    fi
    echo "Connecting to master failed.  Waiting..."
    sleep 1
  done
  sed -i "s/%master-ip%/${MASTER_LB_HOST}/" $SLAVE_CONF
  sed -i "s/%master-port%/${MASTER_LB_PORT}/" $SLAVE_CONF
  redis-server $SLAVE_CONF --protected-mode no $@
}

#Check if MASTER environment variable is set
if [[ "${MASTER}" == "true" ]]; then
  echo "Launching Redis in Master mode"
  launchmaster
  exit 0
fi

# Check if SENTINEL environment variable is set
if [[ "${SENTINEL}" == "true" ]]; then
  echo "Launching Redis Sentinel"
  launchsentinel
  echo "Launcsentinel action completed"
  exit 0
fi

# Determine whether this should be a master or slave instance
echo "Looking for pods running as master"
MASTERS=`kubectl get pod -o jsonpath='{range .items[*]}{.metadata.name} {..podIP}{"\n"}{end}' -l redis-role=master|grep $REDIS_CHART_PREFIX`
if [[ "$MASTERS" == "" ]]; then
  echo "No masters found: \"$MASTERS\" Electing first master..."
  SLAVE1=`kubectl get pod -o jsonpath='{range .items[*]}{.metadata.creationTimestamp} {.metadata.name}{"\n"}{end}' -l redis-node=true|sort|awk '{print $2}'|grep $REDIS_CHART_PREFIX|head -n1`
  if [[ "$SLAVE1" == "$HOSTNAME" ]]; then
    echo "Taking master role"
    launchmaster
  else
    echo "Electing $SLAVE1 master"
    launchslave
  fi
else
  echo "Found $MASTERS"
  echo "Launching Redis in Slave mode"
  launchslave
fi

echo "Launching Redis in Slave mode"
launchslave
echo "Launchslave action completed"
