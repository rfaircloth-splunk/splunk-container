#!/bin/bash
set -e
SPLUNK_HOME=/opt/splunk
APPS_ROLE_BASE=$SPLUNK_HOME/etc/apps/100_cluster
MASTER_APPS_ROLE_BASE=$SPLUNK_HOME/etc/master-apps/100_cluster


echo "$(date) : Restoring ownership on etc and var"
sudo chown splunk:splunk $SPLUNK_HOME
sudo chown -R splunk:splunk $SPLUNK_HOME/etc
sudo chown -R splunk:splunk $SPLUNK_HOME/var

mkdir /opt/splunk/var || true

echo "$(date) : Restoring default etc"
ls /opt/splunk/splunk_etc.tar.gz
tar -I pigz -xf /opt/splunk/splunk_etc.tar.gz -C /

echo "$(date) : Creating base app $APPS_ROLE_BASE"

mkdir $APPS_ROLE_BASE || true
mkdir $APPS_ROLE_BASE/default || true
mkdir $APPS_ROLE_BASE/local || true

mkdir $APPS_ROLE_BASE/metadata || true

echo "$(date) : Configure instance as $SPLUNK_ROLE"


if [ "$SPLUNK_ROLE" != "INDEXER" ]
then
    crudini --set $APPS_ROLE_BASE/local/outputs.conf tcpout defaultGroup primary
    crudini --set $APPS_ROLE_BASE/local/outputs.conf tcpout compressed false
    crudini --set $APPS_ROLE_BASE/local/outputs.conf tcpout:primary server $SPLUNK_OUTPUT_S2S_URI
    crudini --set $APPS_ROLE_BASE/local/outputs.conf tcpout:primary useSSL true
    crudini --set $APPS_ROLE_BASE/local/web.conf settings enableSplunkWebSSL true

fi

SPLUNK_CLUSTER_MODE=searchhead

if [ "$SPLUNK_ROLE" == "INDEXER" ]
then
    crudini --set $APPS_ROLE_BASE/local/web.conf settings startwebserver 0
    SPLUNK_CLUSTER_MODE=slave
    crudini --set $APPS_ROLE_BASE/local/server.conf clustering pass4SymmKey $SPLUNK_SERVER_CLUSTER_PASS4SYMMKEY
    crudini --set $APPS_ROLE_BASE/local/server.conf clustering master_uri $SPLUNK_SERVER_CLUSTER_URI

    crudini --set $APPS_ROLE_BASE/local/server.conf replication_port-ssl://4001 disabled false
    crudini --set $APPS_ROLE_BASE/local/server.conf replication_port-ssl://4001 serverCert $SPLUNK_HOME/etc/auth/protected.pem
    crudini --set $APPS_ROLE_BASE/local/server.conf replication_port-ssl://4001 password password

elif [ "$SPLUNK_ROLE" == "MASTER" ]
then
    SPLUNK_CLUSTER_MODE=master
    crudini --set $APPS_ROLE_BASE/local/server.conf clustering pass4SymmKey $SPLUNK_SERVER_CLUSTER_PASS4SYMMKEY
    crudini --set $APPS_ROLE_BASE/local/server.conf clustering rolling_restart searchable
    crudini --set $APPS_ROLE_BASE/local/server.conf clustering searchable_rebalance true
    crudini --set $APPS_ROLE_BASE/local/server.conf clustering replication_factor 2
    crudini --set $APPS_ROLE_BASE/local/server.conf clustering search_factor 2
    crudini --set $APPS_ROLE_BASE/local/server.conf clustering restart_timeout 180
    crudini --set $APPS_ROLE_BASE/local/server.conf clustering quiet_period 180
    crudini --set $APPS_ROLE_BASE/local/server.conf clustering percent_peers_to_restart 80
    crudini --set $APPS_ROLE_BASE/local/server.conf clustering max_peers_to_download_bundle 10

    mkdir -p $MASTER_APPS_ROLE_BASE/local || true
    FILE=$MASTER_APPS_ROLE_BASE/local/indexes.conf
    if [ ! -f "$FILE" ]; then
        echo [default] > $FILE
        echo repFactor = auto >>$FILE
        echo maxWarmDBCount = 9999 >>$FILE
        echo journalCompression = zstd >>$FILE
        echo tsidxWritingLevel = 3 >>$FILE
        echo maxTotalDataSizeMB = 4294967295 >>$FILE
        echo maxHotSpanSecs = 86400 >>$FILE
        echo maxHotIdleSecs = 20000 >>$FILE
        echo maxHotBuckets = 10 >>$FILE
        echo quarantinePastSecs = 604800 >>$FILE
        echo [_telemetry] >>$FILE
        echo remotePath = >>$FILE
        echo [_introspection] >>$FILE
        echo remotePath = >>$FILE


    fi
    crudini --set $MASTER_APPS_ROLE_BASE/local/indexes.conf volume:remote_store path $SPLUNK_SMARTSTORE_URI
    crudini --set $MASTER_APPS_ROLE_BASE/local/indexes.conf volume:remote_store storageType remote

    crudini --set $MASTER_APPS_ROLE_BASE/local/indexes.conf default remotePath volume:remote_store/\$_index_name
    crudini --set $MASTER_APPS_ROLE_BASE/local/indexes.conf _telemetry repFactor 0
    crudini --set $MASTER_APPS_ROLE_BASE/local/indexes.conf _introspection  repFactor 0

    crudini --set $MASTER_APPS_ROLE_BASE/local/inputs.conf splunktcp-ssl:9997 connection_host ip
    crudini --set $MASTER_APPS_ROLE_BASE/local/inputs.conf splunktcp-ssl:9997 compressed false
    crudini --set $MASTER_APPS_ROLE_BASE/local/inputs.conf splunktcp-ssl:9997 disabled false
    crudini --set $MASTER_APPS_ROLE_BASE/local/inputs.conf SSL serverCert $SPLUNK_HOME/etc/auth/protected.pem
    crudini --set $MASTER_APPS_ROLE_BASE/local/inputs.conf SSL sslPassword password


    crudini --set $MASTER_APPS_ROLE_BASE/local/inputs.conf http disabled 0
    crudini --set $MASTER_APPS_ROLE_BASE/local/inputs.conf http sourcetype hec:unknown
    crudini --set $MASTER_APPS_ROLE_BASE/local/inputs.conf http dedicatedIoThreads 4
    crudini --set $MASTER_APPS_ROLE_BASE/local/inputs.conf http serverCert $SPLUNK_HOME/etc/auth/protected.pem
    crudini --set $MASTER_APPS_ROLE_BASE/local/inputs.conf http sslPassword password

    crudini --set $MASTER_APPS_ROLE_BASE/local/inputs.conf http://primary token ${SPLUNK_SERVER_HEC_TOKEN_PRIMARY}
    crudini --set $MASTER_APPS_ROLE_BASE/local/inputs.conf http://primary queueSize 10MB
    crudini --set $MASTER_APPS_ROLE_BASE/local/inputs.conf http://primary connection_host proxied_ip

elif [ $SPLUNK_ROLE == "LICENSE" ]
then
    crudini --set $APPS_ROLE_BASE/local/server.conf clustering pass4SymmKey $SPLUNK_SERVER_CLUSTER_PASS4SYMMKEY
    crudini --set $APPS_ROLE_BASE/local/server.conf clustering master_uri $SPLUNK_SERVER_CLUSTER_URI

elif [ $SPLUNK_ROLE == "CONSOLE" ]
then
    crudini --set $APPS_ROLE_BASE/local/server.conf clustering pass4SymmKey $SPLUNK_SERVER_CLUSTER_PASS4SYMMKEY
    crudini --set $APPS_ROLE_BASE/local/server.conf clustering master_uri $SPLUNK_SERVER_CLUSTER_URI

elif [ $SPLUNK_ROLE == "SEARCHHEAD" ]
then
    crudini --set $APPS_ROLE_BASE/local/server.conf clustering pass4SymmKey $SPLUNK_SERVER_CLUSTER_PASS4SYMMKEY
    crudini --set $APPS_ROLE_BASE/local/server.conf clustering master_uri $SPLUNK_SERVER_CLUSTER_URI

elif [ $SPLUNK_ROLE == "SHCMEMBER" ]
then
    crudini --set $APPS_ROLE_BASE/local/server.conf clustering pass4SymmKey $SPLUNK_SERVER_CLUSTER_PASS4SYMMKEY
    crudini --set $APPS_ROLE_BASE/local/server.conf clustering master_uri $SPLUNK_SERVER_CLUSTER_URI

fi

crudini --set $APPS_ROLE_BASE/local/server.conf general hostnameOption fullyqualifiedname
crudini --set $APPS_ROLE_BASE/local/server.conf general pass4SymmKey $SPLUNK_SERVER_GENERAL_PASS4SYMMKEY
crudini --set $APPS_ROLE_BASE/local/server.conf applicationsManagement allowInternetAccess false
crudini --set $APPS_ROLE_BASE/local/server.conf clustering mode $SPLUNK_CLUSTER_MODE
crudini --set $APPS_ROLE_BASE/local/server.conf clustering cluster_label $SPLUNK_SERVER_CLUSTER_LABEL

crudini --set $APPS_ROLE_BASE/local/server.conf sslConfig enableSplunkdSSL true
crudini --set $APPS_ROLE_BASE/local/server.conf sslConfig enableSplunkdSSL true
crudini --set $APPS_ROLE_BASE/local/server.conf sslConfig useClientSSLCompression true

crudini --set $APPS_ROLE_BASE/local/server.conf sslConfig sslRootCAPath $SPLUNK_HOME/etc/auth/cabundle.pem
crudini --set $APPS_ROLE_BASE/local/server.conf sslConfig serverCert $SPLUNK_HOME/etc/auth/protected.pem
crudini --set $APPS_ROLE_BASE/local/server.conf sslConfig sslPassword password

crudini --set $SPLUNK_HOME/etc/system/local/user-seed.conf user_info USERNAME admin
crudini --set $SPLUNK_HOME/etc/system/local/user-seed.conf user_info PASSWORD $SPLUNK_PASSWORD


crudini --set $APPS_ROLE_BASE/local/web.conf settings privKeyPath $SPLUNK_HOME/etc/auth/web.key
crudini --set $APPS_ROLE_BASE/local/web.conf settings serverCert $SPLUNK_HOME/etc/auth/web.crt


echo "$(date) : Updating trust list"
sudo cp /opt/splunk/certmanager/ca.crt /usr/share/pki/ca-trust-source/anchors/certmanager.pem
sudo update-ca-trust

echo "$(date) : Setting up Splunkd cert and key"
openssl rsa -des -in /opt/splunk/certmanager/tls.key -out /tmp/private.key -passout pass:password
cat /opt/splunk/certmanager/tls.crt >/opt/splunk/etc/auth/protected.pem
cat /tmp/private.key >>/opt/splunk/etc/auth/protected.pem
cat /etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem >$SPLUNK_HOME/etc/auth/cabundle.pem

echo "$(date) : Setting up web cert and key"
cat /opt/splunk/certmanager/tls.key >$SPLUNK_HOME/etc/auth/web.key
cat /opt/splunk/certmanager/tls.crt >$SPLUNK_HOME/etc/auth/web.crt

echo "$(date) : Starting Splunk"

#if [ "$SPLUNK_ROLE" == "INDEXER" ]
#then
#    exec /opt/splunk/bin/splunk start splunkd --nodaemon --no-prompt --answer-yes $SPLUNK_START_ARGS
#else
    exec /opt/splunk/bin/splunk start --nodaemon --no-prompt --answer-yes $SPLUNK_START_ARGS
#fi
