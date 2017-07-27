#!/bin/bash
set -e

NAME=${NAME:-cockroachdb}

replicas=$(kubectl get statefulset/${NAME} -o template --template '{{.spec.replicas}}')
middle=$((${replicas}/2))

IRC_USER=${IRC_USER:-'kubernetes-sig-apps-test-hook-bot'}
IRC_CHANNEL=${IRC_CHANNEL:-'#kubernetes-hooks'}
IRC_SERVER=${IRC_SERVER:-'irc.freenode.net'}
IRC_SERVER_PORT=${IRC_SERVER_PORT:-'6667'}
function runHook() {
    echo $1
    echo -e "USER ${IRC_USER} ${IRC_USER}-1 ${IRC_USER}-2 ${IRC_USER}-3\nNICK ${IRC_USER}\nJOIN ${IRC_CHANNEL}\nPRIVMSG ${IRC_CHANNEL} :$1\nQUIT\n" | nc ${IRC_SERVER} ${IRC_SERVER_PORT} 2>/dev/null 1>&2
}

function setPartition () {
    kubectl patch statefulset/${NAME} -p '{"spec": {"updateStrategy": {"rollingUpdate": {"partition": '$1'}}}}'
}

function waitForPartition() {
    echo 'Waiting for partition #'$1'...'
    targetedUpdatedReplicas=$((${replicas} - $1))
    for i in {0..300}; do
        generation=$(kubectl get statefulset/${NAME} -o template --template '{{.metadata.generation}}')
        observedGeneration=$(kubectl get statefulset/${NAME} -o template --template '{{.status.observedGeneration}}')
        if [[ "${observedGeneration}" != "${generation}" ]]; then
            echo "Waiting for controller to pick up changes"
            sleep 1
            continue
        fi

        updatedReplicas=$(kubectl get statefulset/${NAME} -o template --template '{{.status.updatedReplicas}}')
        currentRevision=$(kubectl get statefulset/${NAME} -o template --template '{{.status.currentRevision}}')
        updateRevision=$(kubectl get statefulset/${NAME} -o template --template '{{.status.updateRevision}}')
        if [[ "${updatedReplicas}" == "<no value>" && "${updateRevision}" == "${currentRevision}" ]]; then
            updatedReplicas=${replicas}
        fi
        if [[ "${updatedReplicas}" == "${targetedUpdatedReplicas}" ]]; then
            break
        fi
        sleep 1
    done
    
    if [[ "${updatedReplicas}" != "${targetedUpdatedReplicas}" ]]; then
        echo 'TIMEOUT waiting for partition #'$1'!'
        exit 1
    fi
    sleep 10 # a bit of help to account for the init pod
    echo 'Finished waiting for partition #'$1'.'
    echo "(updatedReplicas: ${updatedReplicas})"
}

if [ -z ${ATTEMPT+x} ]; then 
    ATTEMPT=$(kubectl get statefulset/cockroachdb -o template --template '{{index .spec.template.metadata.annotations "demo-attempt"}}')
    ATTEMPT=$((ATTEMPT+1))
fi

echo "Attempt: #$ATTEMPT"
# We need to set partition to current number of replicas first
# for this rollout to be using auto-pausing
# (Normally this would be done in admission control for every change.)
setPartition ${replicas}

# Do the actual change to trigger the rolling-update
kubectl patch statefulset/${NAME} -p '{"spec": {"template": {"metadata": {"annotations": {"demo-attempt": "'${ATTEMPT}'"}}}}}'

# Run pre-hook
runHook "Pre-hook: Starting rolling update of statefulset/${NAME}"

# Move to the first point after middle
setPartition ${middle}
# Wait for it to reach middle
waitForPartition ${middle}

# Run mid-hook
runHook "Mid-hook: rolling update of statefulset/${NAME} reached half of updated replicas."

# Set it to finish
setPartition 0

# Wait for it to finish
waitForPartition 0 

# Run post hook
runHook "Post-hook: Rolling update of statefulset/${NAME} is finished."


