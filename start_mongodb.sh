#! /bin/sh
MONGO_PATH=./mongodb
MONGO_LOGS=$MONGO_PATH/logs
MONGO_DATA=$MONGO_PATH/data

cd `dirname $0`

mkdir -p $MONGO_PATH
mkdir -p $MONGO_DATA
touch $MONGO_LOGS

mongod --slowms=10 --bind_ip 127.0.0.1  --port 27016 --logpath $MONGO_LOGS --logappend --dbpath $MONGO_DATA --directoryperdb 2>&1 &
