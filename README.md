# statefulset-autopausing-hooks
Simple example of using StatefulSet auto-pausing to drive {pre,mid,post} hook


# Run the demo on top of Kubernetes
## Bring up the cluster
```bash
${GOPATH}/src/k8s.io/kubernetes/hack/local-up-cluster.sh
```

## Deploy DNS
```bash
kubectl create -fkubedns-{svc,controller}.yaml
```

## Deploy CockroachDB (our testing statefulset)
```bash
kubectl create -f cockroachdb-statefulset.yaml
```

## Run the rolling update with hooks
```bash
./drive-deployment.sh
```
