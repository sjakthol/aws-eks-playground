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

render-irsa-roles:
	# Put the OIDC Provider ID to the AssumeRolePolicyDocument condition key that
	# limits the service accounts who are allowed to assume a given role.
	sed -i "s|oidc.\+:sub|$(OIDC_PROVIDER_ID):sub|g" stacks/irsa-roles.yaml

deploy-irsa-roles: render-irsa-roles
deploy-irsa-roles: EXTRA_PARAMETERS="OIDCProviderId=$(OIDC_PROVIDER_ID)"

deploy-simple:
	# Create ECR repositories for storing container images this guide requires.
	$(MAKE) deploy-ecr | cfn-monitor

	# Create a VPC with two public and two private subnets (with NAT) for the EKS control plane and worker nodes.
	$(MAKE) deploy-vpc | cfn-monitor

	# Create the EKS control plane for the cluster
	$(MAKE) deploy-eks | cfn-monitor

	# Configure kubectl with credentials needed to access the cluster
	$(AWS_CMD) eks update-kubeconfig --name $(STACK_PREFIX)-eks-cluster

	# Configure Kubernetes to let worker nodes attach to the cluster
	kubectl apply -f config/aws-auth-cm.yaml

	# Create common resources for worker nodes (IAM Roles, SGs)
	$(MAKE) deploy-nodegroup-common | cfn-monitor

	# Create ASGs for worker nodes
	$(MAKE) deploy-nodegroup | cfn-monitor

cleanup-simple:
	$(MAKE) delete-irsa-roles | cfn-monitor
	$(MAKE) delete-nodegroup | cfn-monitor
	$(MAKE) delete-nodegroup-common | cfn-monitor
	$(MAKE) delete-logging | cfn-monitor
	$(MAKE) delete-eks | cfn-monitor
	$(MAKE) delete-vpc | cfn-monitor
