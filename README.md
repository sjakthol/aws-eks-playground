# aws-eks-playground

A collection of notes / configs / scripts / resources to try out Kubernetes in Amazon EKS.

General notes:
* Search and replace 000000000000 with you AWS account ID
* Search and replace eu-north-1 with the AWS region you want to use
* Search and replace en1 with the prefix for AWS region you want to use
* Makefile targets require [cfn-monitor](https://github.com/sjakthol/cfn-monitor) tool (install with `npm i -g cfn-monitor`)
* Setup requires VPC, subnet and NAT stacks from [sjakthol/aws-account-infra](https://github.com/sjakthol/aws-account-infra).

**Table of Contents**
1. [Deploy and configure Kubernetes cluster](#deploy-and-configure-kubernetes-cluster)
2. [Deploy kubernetes-dashboard](#deploy-kubernetes-dashboard)
3. [Deploy hello-world Pod](#deploy-hello-world-pod)
4. [Deploy hello-world Deployment](#deploy-hello-world-deployment)
5. [Enable Horizontal Pod Autoscaler (HPA) for the hello-world Deployment](#enable-horizontal-pod-autoscaler-hpa-for-the-hello-world-deployment)
6. [Cluster Autoscaler (CA)](#cluster-autoscaler-ca)
7. [IAM Roles for Service Accounts](#iam-roles-for-service-accounts)
8. [Spark on EKS](#spark-on-eks)
9. [Fargate](#fargate)
10. [ARM](#arm)
11. [Cleanup](#cleanup)
12. [Credits](#credits)

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
kubectl --namespace kubernetes-dashboard get deployments --watch -o wide

# Proxy the dashboard service to localhost
kubectl -n kubernetes-dashboard port-forward service/kubernetes-dashboard 8443:443 > /dev/null 2>&1 &
```

Dashboard accessible at https://localhost:8443/

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

# Check if it works
kubectl run -i --tty shell --image=amazonlinux:2 -- bash
curl -v hello-world:8080
```

Remove the resources
```
kubectl delete pod shell
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
node components/hello-world/scripts/generate-load.js -u http://<elb>:8080/hash?value=test -p 8 -d 600 -c 4
```

## Enable Horizontal Pod Autoscaler (HPA) for the hello-world Deployment

First, we need to install the Kubernetes Metrics Server for HPA to work:
```bash
kubectl apply -f config/metrics-server.yaml
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

Makefile creates an OIDC provider and a set of IAM roles that can be assigned to Kubernetes Service Accounts. To deploy a component that uses a sample role, run the following:
```bash
# Create service account that is assigned with the irsa-test role from the irsa-roles stack
kubectl apply -f components/irsa-test/deployment/serviceaccount.yaml

# Create pod that uses this service account
kubectl apply -f components/irsa-test/deployment/pod.yaml

# Log into the pod to see the role in action
kubectl exec -ti irsa-test-pod -- bash

# Install AWS CLI to test the role
pip install awscli
aws sts get-caller-identity
aws --region eu-north-1 eks list-clusters
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

Makefiles use Spark 3.1.1.

### PySpark on EKS
The `components/spark-pyspark/` folder has an example for how a PySpark
application can be executed on an EKS cluster. Use the following commands to
try it out:

```bash
# NOTE: Requires Spark Docker images from previous section.

# Build Docker image with the PySpark application embedded into it
(cd components/spark-pyspark && make build push)

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
# Deploy fluent-bit as a daemonset to every node
kubectl apply -f components/logging/deployment/
```

You can find pod container logs from CloudWatch Logs.

## Fargate

Amazon EKS can execute pods in AWS Fargate. `make deploy-simple` creates a Fargate profile for namespace `fargate` by default. Use the following commands to setup Fargate profile(s) for other namespaces:

```bash
# Execute kube-system pods in Fargate & move coredns there
make deploy-eks-fargate-kube-system

# Execute all pods from the 'default' namespace in Fargate
make deploy-eks-fargate-default
```

Once done, Amazon EKS will schedule pods in the given namespace(s)
to AWS Fargate instead of EC2 instances.

### Logging

Execute the following to enable FluentBit logging in Fargate:

```bash
kubectl apply -f components/logging-fargate/deployment/
```

Once done, logs from Fargate pods will appear to CloudWatch.

## ARM

**Important Notes**
* You'll need Docker with buildx plugin. If your docker does not have the buildx command, install it with [these instructions](https://github.com/docker/buildx/issues/132#issuecomment-636041307) (but download [latest version](https://github.com/docker/buildx/releases) instead).

EKS supports Graviton2 instances as compute. Execute the following to deploy ARM64 compute to your cluster:

```bash
make deploy-eks-nodegroup-arm
```

### Docker Images

You'll need to build multi-arch Docker images to run them on ARM64 architecture. Makefiles in this project contain targets for doing that. Here are some examples:

```bash
# hello-world
(cd components/hello-world/ && make build-arm)

# spark
(cd components/spark/ && make build-arm)

# Pyspark script
(cd components/spark-pyspark/ && make build-arm)

# JupyterLab container
(cd components/spark-jupyter/ && make build-arm)
```

These commands initialize binfmt support for ARM64 architecture, configure docker buildx with ARM support, builds the service image for both ARM64 and x86_64 architectures and pushes both images to ECR as a multi-arch image. See respective Makefiles for details on the commands we use.

Note: Building ARM images is very slow on non-ARM machines. They also download / upload much more data to / from ECR. You should use AWS Cloud9 with e.g. m5.xlarge instance for builds to complete in somewhat reasonable timeframe.

Once images are built as described above, they can be deployed to both x86_64 and ARM64 compute as detailed earlier in this document.

## Cleanup

Delete hello-world Deployment gracefully (to ensure ELB gets terminated):
```
kubectl delete -f components/hello-world/deployment/
```

You'll need to empty all S3 buckets and ECR Repositories before they can be deleted. You might also want to check that no ELBs were left running.

Delete stacks:
```bash
# Delete everything
make cleanup-simple

# If deployed (empty out the bucket first)
make delete-spark | cfn-monitor

# Delete ECR repositories (clean the repositories manually first)
make delete-ecr | cfn-monitor
```

## Credits

The contents of this repository have been scraped together from the following sources:
* AWS Auth Configmap: https://docs.aws.amazon.com/eks/latest/userguide/add-user-role.html (Modified MIT license)
* EKS template: Loosely based on eksctl (https://eksctl.io/ & Apache 2.0) and EKS Quickstart (https://github.com/aws-quickstart/quickstart-amazon-eks/blob/master/templates/amazon-eks-master.template.yaml & Apache 2.0).
* Kubernetes Cluster Autoscaler deployment: https://github.com/kubernetes/autoscaler/blob/master/cluster-autoscaler/cloudprovider/aws/examples/cluster-autoscaler-autodiscover.yaml (Apache 2.0)
* Kubernetes Dashboard deployment: https://github.com/kubernetes/dashboard/blob/v2.3.1/aio/deploy/recommended.yaml (Apache 2.0)
* Kubernetes Metrics Server deployment: https://github.com/kubernetes-sigs/metrics-server/releases (Apache 2.0)
* Nodegroup template: https://docs.aws.amazon.com/eks/latest/userguide/getting-started-console.html (Modified MIT license)
* Logging: https://github.com/aws-samples/amazon-ecs-fluent-bit-daemon-service (Apache License Version 2.0)
* Fargate Logging: https://docs.aws.amazon.com/eks/latest/userguide/fargate-logging.html (Modified MIT license)

Other configs based on examples available in Kubernetes Documentation and other random sources in the internet.