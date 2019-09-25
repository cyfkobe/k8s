#!/bin/bash
(umask 077; openssl genrsa -out dashboard.key 2048)
openssl req -new -key dashboard.key -out dashboard.csr -subj "/O=cyf/CN=dashboard"
openssl x509 -req -in dashboard.csr -CA ca.crt -CAkey ca.key -CAcreateserial -out dashboard.crt -days 365

