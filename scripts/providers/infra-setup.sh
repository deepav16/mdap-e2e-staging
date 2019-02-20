#!/bin/bash

pod() {

echo $private_key > private.pem
chmod 400 private.pem

echo "*****************Checking the Cluster's Health********************"

echo "Checking for the number of nodes in ready state*******************************"
ready_nodes=$(ssh -i private.pem k8s@106.51.78.18 'kubectl get nodes | grep Ready | wc -l')

if [ "$ready_nodes" -eq 4 ]; then
echo "Number of nodes in ready state is $ready_nodes"
else
echo "All nodes are not ready"
exit;
fi

##clone e2e-openshift-repo
echo "cloneing e2e-openshift repo*************"
ssh -i private.pem k8s@106.51.78.18 'git clone https://$user:$pass@github.com/mayadata-io/e2e-openshift.git'

ssh -i private.pem k8s@106.51.78.18 'cd e2e-openshift; bash scripts/providers/infra-setup node'

}

node() {

######################
##   ENVIRONMENT    ##
######################

## TODO: Ideally, run_metadata should be passed as gitlab runner (CI runtime) ENV
present_dir=$(pwd)
echo $present_dir
#clone e2e-infrastructre to get the latest commits and run env-exporter script from env
git clone https://github.com/mayadata-io/e2e-infrastructure.git
cd e2e-infrastructure/env
##exporting jiva-controller-image as env##
export OPENEBS_IO_JIVA_CONTROLLER_IMAGE=$(eval python env_exporter.py -o jcontroller -fp ../baseline/baseline)
##exporting jiva-replica-image as env##
export OPENEBS_IO_JIVA_REPLICA_IMAGE=$(eval python env_exporter.py -o jreplica -fp ../baseline/baseline)
##exporting m-apiserver as env##
export MAYA_APISERVER_IMAGE=$(eval python env_exporter.py -o mapi -fp ../baseline/baseline)
##exporting maya-volume-exporter as env##
export OPENEBS_IO_VOLUME_MONITOR_IMAGE=$(eval python env_exporter.py -o iovolume -fp ../baseline/baseline)
##exporting istgt-image as env##
export OPENEBS_IO_CSTOR_VOLUME_MGMT_IMAGE=$(eval python env_exporter.py -o cvolmgmt -fp ../baseline/baseline)
##exporting zfs-image as env##
export OPENEBS_IO_CSTOR_POOL_MGMT_IMAGE=$(eval python env_exporter.py -o cpoolmgmt -fp ../baseline/baseline)
##
export OPENEBS_IO_CSTOR_POOL_IMAGE=$(eval python env_exporter.py -o cstorpool -fp ../baseline/baseline)
##
export OPENEBS_IO_CSTOR_TARGET_IMAGE=$(eval python env_exporter.py -o target -fp ../baseline/baseline)
##

cd $present_dir

echo "Generating test name***************************"
test_name=$(bash utils/generate_test_name testcase=openebsinstaller metadata="")
echo $test_name


## Clone the litmus repo, navigate to litmus root 

git clone https://github.com/openebs/litmus.git
cd litmus


############################
## LITMUS PRECONDITIONING ##
############################


#update openebs litmus job
wget https://raw.githubusercontent.com/openebs/e2e-infrastructure/master/env-update/env.py # script to update openebs_setup.yaml
python3 env.py -f providers/openebs/installers/operator/master/litmusbook/openebs_setup.yaml

echo "updated yaml"
cat providers/openebs/installers/operator/master/litmusbook/openebs_setup.yaml

#################
## RUNNER MAIN ##
#################

echo "Applying rbac.yml********************************"
kubectl apply -f ./hack/rbac.yaml

echo "Copying kube config for litmus"
cp ~/.kube/config admin.conf
kubectl create cm kubeconfig --from-file=admin.conf -n litmus

echo "Running litmus test for openebs deploy.."

run_test=providers/openebs/installers/operator/master/litmusbook/openebs_setup.yaml
bash ../scripts/utils/litmus_job_runner label='provider:openebs-setup' job=$run_test

echo "Dumping state of cluster post job run"; echo ""
bash ../scripts/utils/dump_cluster_state;


#################
## GET RESULT  ##
#################

## Check the test status & result from the litmus result custom resource
bash ../scripts/utils/get_litmus_result ${test_name}

}

if [ "$1" == "node" ];then
  node 
else
  pod
fi
