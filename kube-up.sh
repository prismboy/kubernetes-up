#!/bin/bash

# Fail on all errors
set -e

IMG_K8SETCD=gcr.io/google_containers/etcd:2.0.12
IMG_HYPERKUBE=gcr.io/google_containers/hyperkube:v1.0.1
IMG_SKYETCD=quay.io/coreos/etcd:v2.0.12
IMG_KUBE2SKY=gcr.io/google_containers/kube2sky:1.9
IMG_SKYDNS=gcr.io/google_containers/skydns:2015-03-11-001

if [ $NO_PULL ]
then
  echo "Skipping image pull"
else
  echo "Pulling images..."
  echo
  docker pull $IMG_K8SETCD
  echo
  docker pull $IMG_HYPERKUBE
  echo
  docker pull $IMG_SKYETCD
  echo
  docker pull $IMG_KUBE2SKY
  echo
  docker pull $IMG_SKYDNS
fi

echo
echo -n "Starting etcd    "
docker run --net=host -d \
  $IMG_K8SETCD \
  /usr/local/bin/etcd \
  --addr=127.0.0.1:4001 \
  --bind-addr=0.0.0.0:4001 \
  --data-dir=/var/etcd/data >/dev/null
echo -e "\e[32mOK\e[39m"

echo -n "Starting k8s     "
docker run \
    --volume=/:/rootfs:ro \
    --volume=/sys:/sys:ro \
    --volume=/dev:/dev \
    --volume=/var/lib/docker/:/var/lib/docker:ro \
    --volume=/var/lib/kubelet/:/var/lib/kubelet:rw \
    --volume=/var/run:/var/run:rw \
    --volume=$(pwd)/master.json:/etc/kubernetes/manifests/master.json \
    --net=host \
    --privileged=true \
    -d \
    $IMG_HYPERKUBE \
    /hyperkube kubelet \
    --containerized \
    --address="0.0.0.0" \
    --hostname-override="127.0.0.1" \
    --api-servers=http://localhost:8080 \
    --config=/etc/kubernetes/manifests \
    --cluster_dns=10.0.0.10 \
    --cluster_domain=kubernetes.local \
    >/dev/null
echo -e "\e[32mOK\e[39m"

echo -n "Starting proxy   "
docker run \
  -d \
  --net=host \
  --privileged \
  $IMG_HYPERKUBE \
  /hyperkube proxy --master=http://127.0.0.1:8080 --v=2 \
  >/dev/null
echo -e "\e[32mOK\e[39m"

echo -n "Waiting for API  "
while [ 1 ]
do
  sleep 1
  if curl -m1 http://127.0.0.1:8080/api/v1/namespaces/default/pods >/dev/null 2>&1
  then
    break
  fi
done
echo -e "\e[32mOK\e[39m"

echo -n "Starting skydns  "
./kubectl create -f kube-dns.rc.yaml >/dev/null
./kubectl create -f kube-dns.service.yaml >/dev/null
echo -e "\e[32mOK\e[39m"

echo -n "Verifying skydns "
while [ 1 ]
do
  sleep 1
  if nslookup google.com 10.0.0.10 >/dev/null 2>&1
  then
    break
  fi
done
echo -e "\e[32mOK\e[39m"
