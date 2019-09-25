#!/bin/bash 
kubectl patch sts myapp -p '{"spec":{"updateStrategy":{"rollingUpdate":{"partition":4}}}}'
