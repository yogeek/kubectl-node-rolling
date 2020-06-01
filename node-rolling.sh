#!/bin/bash

image='alpine:3.9'
nodesleep=20        #Time delay between node rolling - give pods time to start up
force=false
dryrun=false
blue='\033[0;34m'
nocolor='\033[0m'

function print_usage() {
  echo "Usage: kubectl node-rolling [<options>]"
  echo ""
  echo "all                                 Shutdown all nodes within the cluster"
  echo ""
  echo "-l|--selector key=value             Selector (label query) to target specific nodes"
  echo ""
  echo "-f|--force                          Shutdown node(s) without first draining"
  echo ""
  echo "-d|--dry-run                        Just print what to do; don't actually do it"
  echo ""
  echo "-s|--sleep                          Sleep delay between shutdowning Nodes (default 20s)"
  echo ""
  echo "-h|--help                           Print usage and exit"
}

while [[ $# -gt 0 ]]
do
  key="$1"

  case $key in
    all)
    allnodes=true
    shift
    ;;
    -l|--selector)
    selector="$2"
    shift
    shift
    ;;
    -f|--force)
    force=true
    shift
    ;;
    -d|--dry-run)
    dryrun=true
    shift
    ;;
    -s|--sleep)
    nodesleep="$2"
    shift
    shift
    ;;
    -h|--help)
    print_usage
    exit 0
    ;;
    *)
    print_usage
    exit 1
    ;;
  esac
done

function wait_for_job_completion() {
  pod=$1
  i=0
  while [[ $i -lt 30 ]]; do
    status=$(kubectl get job $pod -n kube-system -o "jsonpath={.status.succeeded}" 2>/dev/null)
    if [[ $status -gt 0 ]]; then
      echo "Replacement complete after $((i*10)) seconds"
      break;
    else
      i=$(($i+1))
      sleep 10s
      echo "$node - $((i*10)) seconds"
    fi
  done
  if [[ $i == 30 ]]; then
    echo "Error: Replacement job did not complete within 5 minutes"
    exit 1
  fi
}

# Wait for nodes status to be equal to the status passed in parameter
function wait_for_all_kubelet_status() {
  desired_status=$1
  i=0
  while [[ $i -lt 30 ]]; do
    # Look at the kubelet status of all worker nodes and wait until it is equal to the desired_status
    current_status=$(kubectl get node --selector='!node-role.kubernetes.io/master' -o "jsonpath={.items[*].status.conditions[?(.reason==\"KubeletReady\")].type}" 2>/dev/null)
    if [[ "$current_status" == "$desired_status" ]]; then
      echo "All Kubelet Ready after $((i*10)) seconds"
      break;
    else
      i=$(($i+1))
      sleep 10s
      echo "All Kubelet still NotReady - waited $((i*10)) seconds"
    fi
  done
  if [[ $i == 30 ]]; then
    echo "Error: Did not reach all KubeletReady state within 5 minutes"
    exit 1
  fi
}

function wait_for_status() {
  others=$1
  terminating_node=$(kubectl get nodes --selector "kubernetes.io/hostname notin ($others)" -o "jsonpath={.items[0].metadata.name}")
  i=0
  echo "Waiting for <$terminating_node> replacement to be ready..."
  while [[ $i -lt 60 ]]; do
    new_node=$(kubectl get nodes --selector "kubernetes.io/hostname notin ($others)" -o "jsonpath={.items[0].metadata.name}" 2>/dev/null)
    [[ "$?" != "0" ]] && new_node=""
    status=$(kubectl get node --selector "kubernetes.io/hostname notin ($others)" -o "jsonpath={.items[0].status.conditions[?(.reason==\"KubeletReady\")].type}" 2>/dev/null)
    
    # echo
    # echo "old node = $terminating_node"
    # echo "new node = $new_node"
    # echo 

    if [[ "$new_node" == "$terminating_node" ]]; then
      i=$(($i+1))
      sleep 10s
      echo "$terminating_node has not been terminated by the ASG yet - waited $((i*10)) seconds"
    elif [[ "$new_node" == "" ]]; then
      i=$(($i+1))
      sleep 10s
      echo "Terminated node has not been replaced by the ASG yet - waited $((i*10)) seconds"
    elif [[ "$status" != "Ready" ]]; then
      i=$(($i+1))
      sleep 10s
      echo "$new_node NotReady - waited $((i*10)) seconds"
    else
      echo "KubeletReady after $((i*10)) seconds"
      break;
    fi
  done
  if [[ $i == 60 ]]; then
    echo "Error: Did not reach KubeletReady state within 10 minute"
    exit 1
  fi
}

if [ "$allnodes" == "true" ] && [ ! -z "$selector" ]; then
  echo "'all' and '--selector' ('-l') options are incompatible. Please choose one or the other."
  exit 1
fi

if [ "$allnodes" == "true" ]; then
  nodes=$(kubectl get nodes -o jsonpath='{.items[*].metadata.name}')
  # Get current status (will be compared to the final status to check if the cluster is back to normal)
  # current_status=$(kubectl get nodes --selector='!node-role.kubernetes.io/master' -o "jsonpath={.items[*].status.conditions[?(.reason==\"KubeletReady\")].type}" 2>/dev/null)
  echo -e "${blue}Targeting nodes:${nocolor}"
  for node in $nodes; do
    echo " $node"
  done
elif [ ! -z "$selector" ]; then
  nodes=$(kubectl get nodes --selector=$selector -o jsonpath={.items[*].metadata.name})
  # Get current status (will be compared to the final status to check if the cluster is back to normal)
  # current_status=$(kubectl get nodes --selector=$selector -o "jsonpath={.items[*].status.conditions[?(.reason==\"KubeletReady\")].type}" 2>/dev/null)
  echo -e "${blue}Targeting nodes:${nocolor}"
  for node in $nodes; do
    echo " $node"
  done
else
  print_usage
fi

for node in $nodes; do

  # Get all nodes except the current one as a comma-separated list (compatible with kubectl "notin" selector operator)
  others=$(kubectl get nodes --selector "kubernetes.io/hostname notin ($node)" -o "jsonpath={.items[*].metadata.name}" | sed 's/ /,/g')
  # This list will allow us to retrieve the future node name by exclusion selector in the wait_for_status function 
  # new_node=$(kubectl get nodes --selector "kubernetes.io/hostname notin ($others)" -o "jsonpath={.items[*].metadata.name}"

  if $force; then
    echo -e "\nWARNING: --force specified, restarting node $node without draining first"
    if $dryrun; then
      echo "kubectl cordon $node"
    else
      kubectl cordon "$node"
    fi
  else
    echo -e "\n${blue}Draining node $node...${nocolor}"
    if $dryrun; then
      echo "kubectl drain $node --ignore-daemonsets --delete-local-data"
    else
      kubectl drain "$node" --ignore-daemonsets --delete-local-data
    fi
  fi
  
  echo -e "${blue}Initiating node rolling job on $node...${nocolor}"
  pod="node-rolling-$(env LC_CTYPE=C tr -dc a-z0-9 < /dev/urandom | head -c 5)"
  if $dryrun; then
    echo "kubectl create job $pod"
  else
cat <<EOT | kubectl apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: $pod
  namespace: kube-system
spec:
  backoffLimit: 3
  ttlSecondsAfterFinished: 30
  template:
    spec:
      nodeName: $node
      hostPID: true
      tolerations:
      - effect: NoSchedule
        operator: Exists
      containers:
      - name: $pod
        image: $image
        command: [ "nsenter", "--target", "1", "--mount", "--uts", "--ipc", "--pid", "--", "bash", "-c" ]
        args: [ "shutdown && exit 0" ]
        securityContext:
          privileged: true
      restartPolicy: Never
EOT
  fi

  echo -e "${blue}Waiting for replace job to complete on node $node...${nocolor}"
  if ! $dryrun; then
    wait_for_job_completion $pod
    new_node="empty"
    wait_for_status $others
    # wait_for_all_status $current_status
  else
    echo "..."
  fi

  echo -e "${blue}New node $new_node is Ready ! ${nocolor}"
  echo
  
  if ! $dryrun; then
    kubectl get nodes --selector "kubernetes.io/hostname=$new_node"
    kubectl delete job $pod -n kube-system
    sleep $nodesleep
  else
    echo "kubectl delete job $pod -n kube-system"
    echo "sleep $nodesleep"
  fi
done