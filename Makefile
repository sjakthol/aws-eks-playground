include ./utils/common.mk

TAGS ?= Deployment=$(STACK_PREFIX)

define stack_template =

deploy-$(basename $(notdir $(1))): $(1)
	$(AWS_CMD) cloudformation deploy \
		--stack-name $(STACK_PREFIX)-$(basename $(notdir $(1))) \
		--tags $(TAGS) \
		--parameter-overrides StackNamePrefix=$(STACK_PREFIX) $$(EXTRA_PARAMETERS) \
		--no-fail-on-empty-changeset \
		--capabilities CAPABILITY_NAMED_IAM \
		--template-file $(1)

delete-$(basename $(notdir $(1))): $(1)
	$(AWS_CMD) cloudformation delete-stack \
		--stack-name $(STACK_PREFIX)-$(basename $(notdir $(1)))

endef

$(foreach template, $(wildcard stacks/*.yaml), $(eval $(call stack_template,$(template))))

# Target for creating OIDC provider for IAM Roles for Service Accounts (IRSA) setup
OIDC_ISSUER_URL=$(shell $(AWS_CMD) eks describe-cluster --name $(STACK_PREFIX)-eks-cluster --query cluster.identity.oidc.issuer --output text)
OIDC_ISSUER_THUMBPRINT=$(shell ./scripts/root_ca_thumbprint.sh $(OIDC_ISSUER_URL))
OIDC_PROVIDER_ID=$(shell echo $(OIDC_ISSUER_URL) | sed "s|https://||")
create-oidc-provider:
	$(AWS_CMD) iam create-open-id-connect-provider --url $(OIDC_ISSUER_URL) --thumbprint-list $(OIDC_ISSUER_THUMBPRINT) --client-id-list sts.amazonaws.com

delete-oidc-provider:
	for arn in $(shell $(AWS_CMD) iam list-open-id-connect-providers --query 'OpenIDConnectProviderList[*].Arn' --output text | grep $(OIDC_PROVIDER_ID)); do \
		$(AWS_CMD) iam delete-open-id-connect-provider --open-id-connect-provider-arn $$arn; \
	done

deploy-pod-iam: EXTRA_PARAMETERS="OIDCProviderId=$(OIDC_PROVIDER_ID)"

PRIVATE_SUBNET_01 = $(eval PRIVATE_SUBNET_01 := $(shell $(AWS_CMD) cloudformation describe-stacks --stack-name $(STACK_PREFIX)-vpc --query 'Stacks[0].Outputs[?OutputKey==`PrivateSubnet01`].OutputValue' --output text))$(PRIVATE_SUBNET_01)
PRIVATE_SUBNET_02 = $(eval PRIVATE_SUBNET_02 := $(shell $(AWS_CMD) cloudformation describe-stacks --stack-name $(STACK_PREFIX)-vpc --query 'Stacks[0].Outputs[?OutputKey==`PrivateSubnet02`].OutputValue' --output text))$(PRIVATE_SUBNET_02)

deploy-fargate-profile-default:
	$(AWS_CMD) eks create-fargate-profile \
		--fargate-profile-name fargate-ns-default \
		--cluster-name $(STACK_PREFIX)-eks-cluster \
		--subnets $(PRIVATE_SUBNET_01) $(PRIVATE_SUBNET_02) \
		--pod-execution-role arn:aws:iam::$(AWS_ACCOUNT_ID):role/$(STACK_PREFIX)-eks-fargate-pod-execution-role \
		--selectors namespace=default \
		--tags Name=$(STACK_PREFIX)-eks-fargate-ns-default,Deployment=$(STACK_PREFIX)

deploy-fargate-profile-kube-system:
	$(AWS_CMD) eks create-fargate-profile \
		--fargate-profile-name fargate-ns-kube-system \
		--cluster-name $(STACK_PREFIX)-eks-cluster \
		--subnets $(PRIVATE_SUBNET_01) $(PRIVATE_SUBNET_02) \
		--pod-execution-role arn:aws:iam::$(AWS_ACCOUNT_ID):role/$(STACK_PREFIX)-eks-fargate-pod-execution-role \
		--selectors namespace=kube-system \
		--tags Name=$(STACK_PREFIX)-eks-fargate-ns-kube-system,Deployment=$(STACK_PREFIX)

	# Allow coredns to be scheduled into Fargate
	kubectl patch deployment coredns -n kube-system --type json \
		-p='[{"op": "remove", "path": "/spec/template/metadata/annotations/eks.amazonaws.com~1compute-type"}]'

WORKER_ROLE_ARN ?= $(shell $(AWS_CMD) cloudformation list-exports --query 'Exports[?Name==`$(STACK_PREFIX)-base-iam-WorkerNodeInstanceRoleArn`].Value' --output text)

deploy-simple:
	# Deploy infra resources
	$(MAKE) -j deploy-base-ecr deploy-base-iam deploy-base-sg | cfn-monitor

	# Create the EKS control plane for the cluster
	$(MAKE) deploy-eks | cfn-monitor

	# Configure kubectl with credentials needed to access the cluster
	$(AWS_CMD) eks update-kubeconfig --name $(STACK_PREFIX)-eks-cluster

	# Configure Kubernetes to let worker nodes attach to the cluster
	sed -i "s|WORKER_ROLE_ARN|$(WORKER_ROLE_ARN)|g" config/aws-auth-cm.yaml
	kubectl apply -f config/aws-auth-cm.yaml

	# Create OIDC Profiler for IAM Roles for Service Accounts
	$(MAKE) create-oidc-provider

	# Create roles for IAM Roles for Service Accounts (Pods)
	$(MAKE) deploy-pod-iam | cfn-monitor

	# Create Data Plane (Worker Nodes)
	$(MAKE) deploy-nodegroup | cfn-monitor

cleanup-simple:
	$(MAKE) delete-oidc-provider
	$(MAKE) -j delete-pod-iam delete-nodegroup delete-logging delete-spark | cfn-monitor
	$(MAKE) delete-eks | cfn-monitor
	$(MAKE) -j delete-base-sg delete-base-iam delete-base-ecr | cfn-monitor
