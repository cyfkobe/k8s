#!/bin/bash

openssl req -x509 -nodes -days 3650 -newkey rsa:2048 -keyout sslforingress.key -out sslforingress.pem -subj "/CN=grpc.cyf.com"
kubectl create secret tls ingressdemo-secret  --cert sslforingress.pem --key sslforingress.key

