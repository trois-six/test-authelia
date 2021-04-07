#!/bin/bash

#
# Variables
#

readonly CUR_DIR="$( cd "$( dirname "$0" )" && pwd )"

#
# Cleanup
#

k3d cluster delete authelia >/dev/null 2>&1

#
# Create k8s cluster
#

k3d cluster create --k3s-server-arg "--no-deploy=traefik" \
    --port 80:80@loadbalancer --port 443:443@loadbalancer \
    --port 9000:9000@loadbalancer --port 9443:9443@loadbalancer \
    --port 10000:10000@loadbalancer --port 10443:10443@loadbalancer \
    authelia >/dev/null 2>&1
kubectl config use-context k3d-authelia >/dev/null 2>&1
if [ $(kubectl config current-context) != k3d-authelia ]; then echo "k3d cluster not ready"; exit; fi

#
# Create ingress controllers
#

kubectl apply -f "${CUR_DIR}/k8s/traefik"
kubectl -n traefik wait --for condition=available --timeout=600s deployment/traefik

kubectl apply -f "${CUR_DIR}/k8s/ingress-nginx"
kubectl -n ingress-nginx wait --for condition=available --timeout=600s deployment/ingress-nginx-controller

docker image inspect localhost/haproxy-ingress:latest >/dev/null 2>&1
if [ $? -eq 1 ]; then
    git clone https://github.com/jcmoraisjr/haproxy-ingress.git
    cd haproxy-ingress
    make
    make image
    cd ..
    rm -rf "${CUR_DIR}/haproxy-ingress"
fi
k3d image import localhost/haproxy-ingress:latest -c authelia

kubectl apply -f "${CUR_DIR}/k8s/haproxy-ingress"
kubectl -n haproxy-ingress wait --for condition=available --timeout=600s deployment/haproxy-ingress

#
# Create whoami app
#

kubectl apply -f "${CUR_DIR}/k8s/whoami" --wait

#
# Deploy authelia
#

kubectl apply -f "${CUR_DIR}/k8s/authelia" --wait

#
# Display beautiful messages
#

echo "Traefik: http://traefik.traefik.me"
echo "Traefik secured by authelia: https://traefik-secured.traefik.me"
echo "Nginx (kubernetes/ingress-nginx): http://nginx.traefik.me:9000"
echo "Nginx k8s secured by authelia: https://nginx-secured.traefik.me:9443"
echo "HAProxy ingress (jcmoraisjr/haproxy-ingress): http://haproxy.traefik.me:10000"
echo "HAProxy secured by authelia: https://haproxy-secured.traefik.me:10443" # need v0.13
echo "Get Emails from authelia: http://mail.traefik.me"