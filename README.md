# aws-eks-playground

A collection of notes / configs / scripts / resources to try out Kubernetes in Amazon EKS.

General notes:
* Search and replace 000000000000 with you AWS account ID
* Search and replace eu-north-1 with the AWS region you want to use
* Search and replace en1 with the prefix for AWS region you want to use
* Makefile targets require [cfn-monitor](https://github.com/sjakthol/cfn-monitor) tool (install with `npm i -g cfn-monitor`)

**Table of Contents**
1. [Deploy and configure Kubernetes cluster](#deploy-and-configure-kubernetes-cluster)
2. [Deploy kubernetes-dashboard](#deploy-kubernetes-dashboard)
3. [Deploy hello-world Pod](#deploy-hello-world-pod)
4. [Deploy hello-world Deployment](#deploy-hello-world-deployment)
5. [Enable Horizontal Pod Autoscaler (HPA) for the hello-world Deployment](#enable-horizontal-pod-autoscaler-hpa-for-the-hello-world-deployment)
6. [Cluster Autoscaler (CA)](#cluster-autoscaler-ca)
7. [IAM Roles for Service Accounts](#iam-roles-for-service-accounts)
8. [Spark on EKS](#spark-on-eks)
9. [Cleanup](#cleanup)
10. [Credits](#credits)

## Deploy and configure Kubernetes cluster

Execute the following commands to get a working EKS cluster:

```bash
export AWS_REGION=eu-north-1
export AWS_PROFILE=admin # need to be able to do lots of actions including setting up IAM roles

# Deploy all stacks required for this setup (ECR, VPC, EKS, Node Groups)
make deploy-simple

# Wait for node(s) to be READY
kubectl get nodes --watch -o wide
```

See the Makefile for details on the steps it takes to get a working Kubernetes cluster.

## Deploy kubernetes-dashboard

Deploy Kubernetes dashboard as follows:

```bash
# Deploy
kubectl apply -f config/kubernetes-dashboard.yaml
kubectl --namespace kube-system get deployments --watch -o wide

# Proxy the UI to localhost
kubectl proxy >/dev/null 2>&1 &
```

Dashboard accessible at http://localhost:8001/api/v1/namespaces/kube-system/services/https:kubernetes-dashboard:/proxy/

Use token authentication with a token from
```bash
aws eks get-token --cluster-name en1-eksplayground-eks-cluster
```

## Deploy hello-world Pod

The hello-world Pod is a single web service that responds to HTTP requests. Let's build and push it to ECR first:

```bash
(cd components/hello-world/ && make push)
```

Then, let's deploy container as a Pod and see if we can connect to it from within the K8S cluster:
```bash
# Deploy
kubectl apply -f components/hello-world/deployment/pod.yaml
kubectl get pods -o wide --watch

# Check if it works <ip> from output of get pods above
kubectl run -i --tty shell --image=amazonlinux:2 -- bash
curl -v <ip>:8080
```

Remove the resources
```
kubectl delete -l run=shell deployments
kubectl delete -f components/hello-world/deployment/pod.yaml
```

## Deploy hello-world Deployment

Next, we can deploy the hello-world container as a Deployment that is exposed to the public internet via a LoadBalancer service (internet-facing ELB in AWS).

```bash
# Deploy
kubectl apply -f components/hello-world/deployment/deployment.yaml

# See how it goes
kubectl get deployments --watch -o wide
kubectl get svc # to find ELB address

# Test the ELB (takes a few minutes to be available)
curl elb:8080/

# Put some load on the system
parallel --jobs 16 --progress -n0 time curl -sS <elb>:8080/hash?value=test ::: {0..10000}
node components/hello-world/scripts/generate-load.js -u http://<elb>:8080/hash?value=test -p 4 -d 60
```

## Enable Horizontal Pod Autoscaler (HPA) for the hello-world Deployment

First, we need to install the Kubernetes for HPA to work:
```bash
kubectl apply -f config/metrics-server/
kubectl --namespace kube-system get deployments --watch
```

Then, let's enable horizontal auto-scaling for the hello-world service:
```bash
# Deploy
kubectl apply -f components/hello-world/deployment/deployment-hpa.yaml

# Monitor HPA activity
kubectl get hpa --watch -o wide
kubectl get deployments --watch -o wide

# Put some load on the service
parallel --jobs 16 --progress -n0 time curl -sS elb:8080/hash?value=test ::: {0..10000}
node components/hello-world/scripts/generate-load.js --url elb:8080/hash?value=test --duration 900 --connections 16
```

## Cluster Autoscaler (CA)

HPA cannot scale the deployment past the resources in the nodegroup. To scale the workers, we need to enable Cluster Autoscaler (CA) component:

```bash
# Deploy
kubectl apply -f config/cluster_autoscaler.yaml
kubectl --namespace kube-system get deployments --watch -o wide
```

Then, we can continue putting some load on the service and watch both HPA and CA scale the deployment and the nodegroup up:
```bash
# Put some load on the service
parallel --jobs 16 --progress -n0 time curl -sS elb:8080/hash?value=test ::: {0..10000} # or
node components/hello-world/scripts/generate-load.js --url elb:8080/hash?value=test --duration 900 --connections 16

# Monitor HPA activity
kubectl get hpa --watch -o wide
kubectl get deployments --watch -o wide

# Monitor new nodes coming up
kubectl get nodes --watch -o wide
```

## IAM Roles for Service Accounts
IAM Roles for Service Accounts (IRSA) give pods a dedicated IAM role to operate on AWS APIs. See https://aws.amazon.com/blogs/opensource/introducing-fine-grained-iam-roles-service-accounts/ for details.

Use the following commands to setup IRSA:
```bash
# Create OpenID Connect Provider to the IAM service for the EKS OIDC
make create-oidc-provider

# Create IRSA capable IAM roles
make deploy-irsa-roles
```

To deploy a component that uses a sample role, run the following:
```bash
# Create service account that is assigned with the irsa-test role from the irsa-roles stack
kubectl apply -f components/irsa-test/deployment/serviceaccount.yaml

# Create pod that uses this service account
kubectl apply -f components/irsa-test/deployment/pod.yaml

# Log into the pod to see the role in action
kubectl exec -ti irsa-test-pod bash

# Install AWS CLI to test the role
pip install awscli
aws sts get-caller-identity
aws eks list-clusters
```

## Spark on EKS
Apache Spark supports Kubernetes as scheduling backend for Spark application. Use the following commands to run Spark on EKS:

```bash
# Build Docker image(s) for Spark, PySpark and SparkR.
(cd components/spark && make build)

# Setup service account for Spark
kubectl apply -f components/spark/deployment/serviceaccount.yaml

# Submit example application (SparkPi included in the default Docker image)
(cd components/spark && make submit)
```

### PySpark on EKS
The `components/spark-pyspark/` folder has an example for how a PySpark
application can be executed on an EKS cluster. Use the following commands to
try it out:

```bash
# NOTE: Requires Spark Docker images from previous section.

# Build Docker image with the PySpark application embedded into it
(cd components/spark-pyspark && make build)

# Submit the application to EKS
(cd components/spark-pyspark && make submit)

```

### JupyterLab with PySpark on EKS
The `components/spark-jupyter/` folder has a setup that allows you to run PySpark
code via JupyterLab interface on the EKS cluster (JupyterLab runs as pod, PySpark
driver runs inside JupyterLab pod, PySpark executors run as separate Pods).

Use the following commands to start JupyterLab with PySpark code running on
EKS:

```bash

# Prerequisites: Spark images and service account have been created.

# Deploy required resources
make deploy-spark | cfn-monitor

# Build the JupyterLab image
(cd components/spark-jupyter/ && make push)

# Start JupyterLab instance as pod (edit executor counts & sizes in the pod config
# as required)
kubectl apply -f components/spark-jupyter/deployment/pod.yaml

# Forward JupyterLab and Spark UI ports
kubectl port-forward jupyter 8888 4040 >/dev/null 2>&1 &

# Find JupyterLab secret link (choose one with 127.0.0.1 as the IP)
kubectl logs jupyter

# Open the link in your browser, start writing Spark code
```

## Logging with Fluent Bit
The `components/logging/` contains a Fluent Bit setup for forwarding logs
from pods to CloudWatch Logs. The included configuration enriches each log
line with Kubernetes metadata and outputs the logs in JSON format. Use the
following commands to setup Fluent Bit logging:

```bash
# Deploy AWS resources
make deploy-logging | cfn-monitor

# Deploy fluent-bit as a daemonset to every node
kubectl apply -f components/logging/deployment/
```

You can find pod container logs from CloudWatch Logs.

## Cleanup

Delete hello-world Deployment gracefully (to ensure ELB gets terminated):
```
kubectl delete -f components/hello-world/deployment/
```

Delete irsa-test resources & OIDC provider for IRSA (if deployed)
```
kubectl delete -f components/irsa-test/deployment/
make delete-oidc-provider
```

Delete stacks:
```bash
# Delete stacks that do not hold any state / data
make cleanup-simple

# If deployed (empty out the bucket first)
make delete-spark | cfn-monitor

# Delete ECR repositories (clean the repositories manually first)
make delete-ecr | cfn-monitor
```

* Note: You might want to check that no ELBs were left running

## Credits

The contents of this repository have been scraped together from the following sources:
* AWS Auth Configmap: https://docs.aws.amazon.com/eks/latest/userguide/add-user-role.html (Modified MIT license)
* EKS template: Loosely based on eksctl (https://eksctl.io/ & Apache 2.0) and EKS Quickstart (https://github.com/aws-quickstart/quickstart-amazon-eks/blob/master/templates/amazon-eks-master.template.yaml & Apache 2.0).
* Kubernetes Cluster Autoscaler deployment: https://github.com/kubernetes/autoscaler/blob/master/cluster-autoscaler/cloudprovider/aws/examples/cluster-autoscaler-one-asg.yaml (Apache 2.0)
* Kubernetes Dashboard deployment: https://github.com/kubernetes/dashboard/blob/v1.10.0/src/deploy/recommended/kubernetes-dashboard.yaml (Apache 2.0)
* Kubernetes Metrics Server deployment: https://github.com/kubernetes-incubator/metrics-server/tree/master/deploy/1.8%2B (Apache 2.0)
* Nodegroup template: https://docs.aws.amazon.com/eks/latest/userguide/getting-started-console.html (Modified MIT license)
* VPC template: https://docs.aws.amazon.com/eks/latest/userguide/getting-started-console.html (Modified MIT license)
* Logging: https://github.com/aws-samples/amazon-ecs-fluent-bit-daemon-service (Apache License Version 2.0)

Other configs based on examples available in Kubernetes Documentation and other random sources in the internet.