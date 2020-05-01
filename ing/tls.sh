#!/bin/bash

openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout tls.key -out tls.crt -subj "/CN=grpc.cyf.com/O=grpc.cyf.com"

kubectl create secret tls grpc-secret --key tls.key --cert tls.crt
