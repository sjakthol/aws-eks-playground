include ./utils/common.mk

TAGS ?= Deployment=$(STACK_PREFIX)

# Generic deployment and teardown targets
deploy-%:
	$(AWS_CMD) cloudformation deploy \
		--stack-name $(STACK_PREFIX)-$*$(STACK_SUFFIX) \
		--tags $(TAGS) \
		--parameter-overrides StackNamePrefix=$(STACK_PREFIX) $(EXTRA_PARAMETERS) \
		--no-fail-on-empty-changeset \
		--capabilities CAPABILITY_NAMED_IAM \
		--template-file stacks/$*.yaml \

delete-%:
	$(AWS_CMD) cloudformation delete-stack \
		--stack-name $(STACK_PREFIX)-$*$(STACK_SUFFIX)

# Concrete deploy and delete targets for autocompletion
$(addprefix deploy-,$(basename $(notdir $(wildcard stacks/*.yaml)))):
$(addprefix delete-,$(basename $(notdir $(wildcard stacks/*.yaml)))):

# Target for creating OIDC provider for IAM Roles for Service Accounts (IRSA) setup
OIDC_ISSUER_URL=$(shell $(AWS_CMD) eks describe-cluster --name $(STACK_PREFIX)-eks-cluster --query cluster.identity.oidc.issuer --output text)
OIDC_ISSUER_THUMBPRINT=$(shell ./scripts/root_ca_thumbprint.sh $(OIDC_ISSUER_URL))
deploy-pod-iam: EXTRA_PARAMETERS=OIDCIssuerUrl=$(OIDC_ISSUER_URL) OIDCIssuerThumbprint=$(OIDC_ISSUER_THUMBPRINT)

deploy-eks-fargate-default deploy-eks-fargate-kube-system:
deploy-eks-fargate-%:
	$(MAKE) deploy-eks-fargate EXTRA_PARAMETERS="Namespace=$*" STACK_SUFFIX="-$*"

delete-eks-fargate-default delete-eks-fargate-kube-system:
delete-eks-fargate-%:
	$(MAKE) delete-eks-fargate STACK_SUFFIX="-$*"

WORKER_ROLE_ARN ?= $(shell $(AWS_CMD) cloudformation list-exports --query 'Exports[?Name==`$(STACK_PREFIX)-base-iam-WorkerNodeInstanceRoleArn`].Value' --output text)

deploy-simple:
	# Deploy infra resources
	$(MAKE) -j deploy-base-ecr deploy-base-iam deploy-base-sg deploy-base-logging | cfn-monitor

	# Create the EKS control plane for the cluster
	$(MAKE) deploy-eks | cfn-monitor

	# Configure kubectl with credentials needed to access the cluster
	$(AWS_CMD) eks update-kubeconfig --name $(STACK_PREFIX)-eks-cluster

	# Configure Kubernetes to let worker nodes attach to the cluster
	sed -i "s|WORKER_ROLE_ARN|$(WORKER_ROLE_ARN)|g" config/aws-auth-cm.yaml
	kubectl apply -f config/aws-auth-cm.yaml

	# Create roles for IAM Roles for Service Accounts (Pods)
	$(MAKE) deploy-pod-iam | cfn-monitor

	# Create Data Plane (Worker Nodes)
	$(MAKE) deploy-eks-nodegroup deploy-eks-fargate | cfn-monitor

cleanup-simple:
	$(MAKE) delete-eks-fargate | cfn-monitor
	$(MAKE) delete-eks-fargate-default | cfn-monitor
	$(MAKE) delete-eks-fargate-kube-system | cfn-monitor
	$(MAKE) -j delete-pod-iam delete-eks-nodegroup delete-eks-nodegroup-arm delete-logging delete-spark | cfn-monitor
	$(MAKE) delete-eks | cfn-monitor
	$(MAKE) -j delete-base-sg delete-base-iam delete-base-ecr delete-base-logging | cfn-monitor
