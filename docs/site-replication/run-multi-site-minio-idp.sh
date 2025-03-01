#!/usr/bin/env bash

# shellcheck disable=SC2120
exit_1() {
    cleanup
    exit 1
}

cleanup() {
    echo "Cleaning up instances of MinIO"
    pkill minio
    pkill -9 minio
    rm -rf /tmp/minio-internal-idp{1,2,3}
}

cleanup

unset MINIO_KMS_KES_CERT_FILE
unset MINIO_KMS_KES_KEY_FILE
unset MINIO_KMS_KES_ENDPOINT
unset MINIO_KMS_KES_KEY_NAME

export MINIO_BROWSER=off
export MINIO_ROOT_USER="minio"
export MINIO_ROOT_PASSWORD="minio123"
export MINIO_KMS_AUTO_ENCRYPTION=off
export MINIO_PROMETHEUS_AUTH_TYPE=public
export MINIO_KMS_SECRET_KEY=my-minio-key:OSMM+vkKUTCvQs9YL/CVMIMt43HFhkUpqJxTmGl6rYw=

if [ ! -f ./mc ]; then
    wget -O mc https://dl.minio.io/client/mc/release/linux-amd64/mc \
        && chmod +x mc
fi

minio server --config-dir /tmp/minio-internal --address ":9001" /tmp/minio-internal-idp1/{1...4} >/tmp/minio1_1.log 2>&1 &
minio server --config-dir /tmp/minio-internal --address ":9002" /tmp/minio-internal-idp2/{1...4} >/tmp/minio2_1.log 2>&1 &
minio server --config-dir /tmp/minio-internal --address ":9003" /tmp/minio-internal-idp3/{1...4} >/tmp/minio3_1.log 2>&1 &

sleep 10

export MC_HOST_minio1=http://minio:minio123@localhost:9001
export MC_HOST_minio2=http://minio:minio123@localhost:9002
export MC_HOST_minio3=http://minio:minio123@localhost:9003

./mc admin replicate add minio1 minio2 minio3

./mc admin user add minio1 foobar foo12345
./mc admin policy set minio1 consoleAdmin user=foobar
sleep 5

./mc admin user info minio2 foobar
./mc admin user info minio3 foobar
./mc admin policy add minio1 rw ./docs/site-replication/rw.json

sleep 5
./mc admin policy info minio2 rw >/dev/null 2>&1
./mc admin policy info minio3 rw >/dev/null 2>&1

./mc admin policy remove minio3 rw

sleep 10
./mc admin policy info minio1 rw
if [ $? -eq 0 ]; then
    echo "expecting the command to fail, exiting.."
    exit_1;
fi

./mc admin policy info minio2 rw
if [ $? -eq 0 ]; then
    echo "expecting the command to fail, exiting.."
    exit_1;
fi

./mc admin user info minio1 foobar
if [ $? -ne 0 ]; then
    echo "policy mapping missing, exiting.."
    exit_1;
fi

./mc admin user info minio2 foobar
if [ $? -ne 0 ]; then
    echo "policy mapping missing, exiting.."
    exit_1;
fi

./mc admin user info minio3 foobar
if [ $? -ne 0 ]; then
    echo "policy mapping missing, exiting.."
    exit_1;
fi

./mc admin user svcacct add minio2 foobar --access-key testsvc --secret-key testsvc123
if [ $? -ne 0 ]; then
    echo "adding svc account failed, exiting.."
    exit_1;
fi

sleep 10

./mc admin user svcacct info minio1 testsvc
if [ $? -ne 0 ]; then
    echo "svc account not mirrored, exiting.."
    exit_1;
fi

./mc admin user svcacct info minio2 testsvc
if [ $? -ne 0 ]; then
    echo "svc account not mirrored, exiting.."
    exit_1;
fi

./mc admin user svcacct rm minio1 testsvc
if [ $? -ne 0 ]; then
    echo "removing svc account failed, exiting.."
    exit_1;
fi

sleep 10
./mc admin user svcacct info minio2 testsvc
if [ $? -eq 0 ]; then
    echo "svc account found after delete, exiting.."
    exit_1;
fi

./mc admin user svcacct info minio3 testsvc
if [ $? -eq 0 ]; then
    echo "svc account found after delete, exiting.."
    exit_1;
fi

./mc mb minio1/newbucket

sleep 5
./mc stat minio2/newbucket
if [ $? -ne 0 ]; then
    echo "expecting bucket to be present. exiting.."
    exit_1;
fi

./mc stat minio3/newbucket
if [ $? -ne 0 ]; then
    echo "expecting bucket to be present. exiting.."
    exit_1;
fi

./mc cp README.md minio2/newbucket/

sleep 5
./mc stat minio1/newbucket/README.md
if [ $? -ne 0 ]; then
    echo "expecting object to be present. exiting.."
    exit_1;
fi

./mc stat minio3/newbucket/README.md
if [ $? -ne 0 ]; then
    echo "expecting object to be present. exiting.."
    exit_1;
fi

./mc rm minio3/newbucket/README.md
sleep 5

./mc stat minio2/newbucket/README.md
if [ $? -eq 0 ]; then
    echo "expected file to be deleted, exiting.."
    exit_1;
fi

./mc stat minio1/newbucket/README.md
if [ $? -eq 0 ]; then
    echo "expected file to be deleted, exiting.."
    exit_1;
fi

./mc mb --with-lock minio3/newbucket-olock
sleep 5

enabled_minio2=$(./mc stat --json minio2/newbucket-olock| jq -r .metadata.ObjectLock.enabled)
if [ $? -ne 0 ]; then
    echo "expected bucket to be mirrored with object-lock but not present, exiting..."
    exit_1;
fi

if [ "${enabled_minio2}" != "Enabled" ]; then
    echo "expected bucket to be mirrored with object-lock enabled, exiting..."
    exit_1;
fi

enabled_minio1=$(./mc stat --json minio1/newbucket-olock| jq -r .metadata.ObjectLock.enabled)
if [ $? -ne 0 ]; then
    echo "expected bucket to be mirrored with object-lock but not present, exiting..."
    exit_1;
fi

if [ "${enabled_minio1}" != "Enabled" ]; then
    echo "expected bucket to be mirrored with object-lock enabled, exiting..."
    exit_1;
fi
