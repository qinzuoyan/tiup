#!/bin/bash

set -eu

name=test_cmd
topo=./topo/full_dm.yaml

ipprefix=${TIUP_TEST_IP_PREFIX:-"172.19.0"}
sed "s/__IPPREFIX__/$ipprefix/g" $topo.tpl > $topo

mkdir -p ~/.tiup/bin && cp -f ./root.json ~/.tiup/bin/

# tiup-dm check $topo -i ~/.ssh/id_rsa --enable-mem --enable-cpu --apply

# tiup-dm --yes check $topo -i ~/.ssh/id_rsa

tiup-dm --yes deploy $name $version $topo -i ~/.ssh/id_rsa

tiup-dm list | grep "$name"

# debug https://github.com/pingcap/tiup/issues/666
echo "debug audit:"
ls -l ~/.tiup/storage/dm/audit/*
head -1 ~/.tiup/storage/dm/audit/*
tiup-dm audit
echo "end debug audit"

tiup-dm audit | grep "deploy $name $version"

# Get the audit id can check it just runnable
id=`tiup-dm audit | grep "deploy $name $version" | awk '{print $1}'`
tiup-dm audit $id

# check the local config
tiup-dm exec $name -N $ipprefix.101 --command "grep magic-string-for-test /home/tidb/deploy/prometheus-9090/conf/dm_worker.rules.yml"
tiup-dm exec $name -N $ipprefix.101 --command "grep magic-string-for-test /home/tidb/deploy/grafana-3000/dashboards/dm.json"
tiup-dm exec $name -N $ipprefix.101 --command "grep magic-string-for-test /home/tidb/deploy/alertmanager-9093/conf/alertmanager.yml"

tiup-dm --yes start $name


# check the data dir of dm-master
tiup-dm exec $name -N $ipprefix.102 --command "grep /home/tidb/deploy/dm-master-8261/data /home/tidb/deploy/dm-master-8261/scripts/run_dm-master.sh"
tiup-dm exec $name -N $ipprefix.103 --command "grep /home/tidb/my_master_data /home/tidb/deploy/dm-master-8261/scripts/run_dm-master.sh"

tiup-dm --yes stop $name

tiup-dm --yes restart $name

tiup-dm display $name

total_sub_one=12

echo "start scale in dm-master"
tiup-dm --yes scale-in $name -N $ipprefix.101:8261
wait_instance_num_reach $name $total_sub_one false
echo "start scale out dm-master"

topo_master=./topo/full_scale_in_dm-master.yaml
sed "s/__IPPREFIX__/$ipprefix/g" $topo_master.tpl > $topo_master
tiup-dm --yes scale-out $name $topo_master

echo "start scale in dm-worker"
yes | tiup-dm scale-in $name -N $ipprefix.102:8262
wait_instance_num_reach $name $total_sub_one

echo "start scale out dm-worker"
topo_worker=./topo/full_scale_in_dm-worker.yaml
sed "s/__IPPREFIX__/$ipprefix/g" $topo_worker.tpl > $topo_worker
yes | tiup-dm scale-out $name $topo_worker

# test create a task and can replicate data
./script/task/run.sh

tiup-dm --yes destroy $name
