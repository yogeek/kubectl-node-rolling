# kubectl-node-rolling

`kubectl-node-rolling` is a [kubectl plugin](https://kubernetes.io/docs/tasks/extend-kubectl/kubectl-plugins/) that sequentially and gracefully performs a shutdown of Nodes within a Kubernetes cluster.

This plugin was adapted from [kubectl-node-restart](https://github.com/MnrGreg/kubectl-node-restart) plugin.

**Goal** : In a context where nodes are managed by cloud auto-scaling group, restarting nodes is not sufficient to do a rolling-upgrade.
When creating a K8S cluster based on immutable AMIs for example, we would like to be able to update the nodes when the AMI has been changed in the ASG Launch Template. To do this, nodes have to be terminated to be replaced by a newer node by the ASG.
As this plugin shutdowns a node at a time, this node is (after a "healthcheck" delay) seen by the ASG as "Unhealthy", so the ASG terminates the node and starts a new one based on the last Launch Template. Once the node is ready in K8S, it continues with the next node. 

## Installation

### Installing manually

```bash
curl -L https://raw.githubusercontent.com/yogeek/kubectl-node-rolling/master/node-rolling.sh -o kubectl-node_rolling
chmod +x kubectl-node_rolling
sudo mv ./kubectl-node_rolling /usr/local/bin/kubectl-node_rolling
```

### Installing with krew (NOT AVAILABLE YET)

- install `krew` using instructions [here](https://github.com/kubernetes-sigs/krew#installation)
- run `kubectl krew update`
- run `kubectl krew install node-rolling`

## Usage

- perform rolling shutdown of all nodes in a cluster

```bash
    kubectl node-rolling all
```

- shutdown only specific nodes selected through labels

```bash
    # Only master nodes
    kubectl node-rolling --selector node-role.kubernetes.io/master

    # Only worker nodes
    kubectl node-rolling --selector node-role.kubernetes.io/node=node
```

- perform a dry-run

```bash
    kubectl node-rolling all --dry-run
```

- rolling node(s) without first draining

```bash
    kubectl node-rolling all --force
```

- add a delay of 120seconds between node rollings

```bash
    kubectl node-rolling all --sleep 120
```
