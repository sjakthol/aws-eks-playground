# aws-eks-playground

A collection of notes / configs / scripts / resources to try out Kubernetes in Amazon EKS.

General notes:
* Search and replace 00000000000 with you AWS account ID
* Search and replace eu-north-1 with the AWS region you want to use
* Search and replace en1 with the prefix for AWS region you want to use

**Table of Contents**
1. [Deploy and configure Kubernetes cluster](#deploy-and-configure-kubernetes-cluster)
2. [Deploy kubernetes-dashboard](#deploy-kubernetes-dashboard)
3. [Deploy hello-world Pod](#deploy-hello-world-pod)
4. [Deploy hello-world Deployment](#deploy-hello-world-deployment)
5. [Enable Horizontal Pod Autoscaler (HPA) for the hello-world Deployment](#enable-horizontal-pod-autoscaler-hpa-for-the-hello-world-deployment)
6. [Cluster Autoscaler (CA)](#cluster-autoscaler-ca)
7. [IAM Roles for Service Accounts](#iam-roles-for-service-accounts)
8. [Cleanup](#cleanup)
9. [Credits](#credits)

## Deploy and configure Kubernetes cluster

1. Deploy CloudFormation stacks (VPC, EKS control plane, worker nodegroup and ECR repositories for test images)
```bash
export AWS_REGION=eu-north-1
export AWS_PROFILE=admin # need to be able to do lots of actions including setting up IAM roles
(make -j deploy-ecr deploy-vpc | cfn-monitor) && (make deploy-eks | cfn-monitor) && (make deploy-nodegroup | cfn-monitor)
```

2. Update kubeconfig for the new cluster
```bash
aws --region eu-north-1 eks update-kubeconfig --name en1-eksplayground-eks-cluster
```

3. Apply AWS auth configmap to let worker nodes attach to the cluster
```bash
# Deploy
kubectl apply -f config/aws-auth-cm.yaml

# Wait for node(s) to be READY
kubectl get nodes --watch -o wide
```

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
node components/hello-world/scripts/generate-load.js http://<elb>:8080/hash?value=test
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

Delete stacks in reverse order:
```bash
(make delete-nodegroup | cfn-monitor) && (make delete-eks | cfn-monitor) && (make delete-vpc | cfn-monitor) && (make delete-ecr | cfn-monitor)
```

* Note: ECR fails to delete if you don't remove all the images from the repositories before deleting the stack.
* Note 2: You might want to check that no ELBs were left running

## Credits

The contents of this repository have been scraped together from the following sources:
* AWS Auth Configmap: https://docs.aws.amazon.com/eks/latest/userguide/add-user-role.html (Modified MIT license)
* EKS template: Loosely based on eksctl (https://eksctl.io/ & Apache 2.0) and EKS Quickstart (https://github.com/aws-quickstart/quickstart-amazon-eks/blob/master/templates/amazon-eks-master.template.yaml & Apache 2.0).
* Kubernetes Cluster Autoscaler deployment: https://github.com/kubernetes/autoscaler/blob/master/cluster-autoscaler/cloudprovider/aws/examples/cluster-autoscaler-one-asg.yaml (Apache 2.0)
* Kubernetes Dashboard deployment: https://github.com/kubernetes/dashboard/blob/v1.10.0/src/deploy/recommended/kubernetes-dashboard.yaml (Apache 2.0)
* Kubernetes Metrics Server deployment: https://github.com/kubernetes-incubator/metrics-server/tree/master/deploy/1.8%2B ()
* Nodegroup template: https://docs.aws.amazon.com/eks/latest/userguide/getting-started-console.html (Modified MIT license)
* VPC template: https://docs.aws.amazon.com/eks/latest/userguide/getting-started-console.html (Modified MIT license)

Other configs based on examples available in Kubernetes Documentation and other random sources in the internet.