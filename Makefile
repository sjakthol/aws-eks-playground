# Mapping from long region names to shorter ones that is to be
# used in the stack names
AWS_ap-northeast-1_PREFIX = an1
AWS_ap-northeast-2_PREFIX = an2
AWS_ap-south-1_PREFIX = as1
AWS_ap-southeast-1_PREFIX = as1
AWS_ap-southeast-2_PREFIX = as2
AWS_ca-central-1_PREFIX = cc1
AWS_eu-central-1_PREFIX = ec1
AWS_eu-west-1_PREFIX = ew1
AWS_eu-west-2_PREFIX = ew2
AWS_eu-west-3_PREFIX = ew3
AWS_sa-east-1_PREFIX = se1
AWS_us-east-1_PREFIX = ue1
AWS_us-east-2_PREFIX = ue2
AWS_us-west-1_PREFIX = uw1
AWS_us-west-2_PREFIX = uw2
AWS_eu-north-1_PREFIX = en1

# Some defaults
AWS ?= aws
AWS_REGION ?= eu-north-1
AWS_PROFILE ?= default

AWS_CMD := $(AWS) --profile $(AWS_PROFILE) --region $(AWS_REGION)

STACK_REGION_PREFIX := $(AWS_$(AWS_REGION)_PREFIX)
STACK_PREFIX := $(STACK_REGION_PREFIX)-eksplayground

TAGS ?= Deployment=$(STACK_PREFIX)

define stack_template =

deploy-$(basename $(notdir $(1))): $(1)
	$(AWS_CMD) cloudformation deploy \
		--stack-name $(STACK_PREFIX)-$(basename $(notdir $(1))) \
		--tags $(TAGS) \
		--parameter-overrides StackNamePrefix=$(STACK_PREFIX) $$(EXTRA_PARAMETERS) \
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
