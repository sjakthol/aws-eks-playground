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

AWS_CMD := $(AWS) --region $(AWS_REGION)
AWS_ACCOUNT_ID = $(eval AWS_ACCOUNT_ID := $(shell $(AWS_CMD) sts get-caller-identity --query Account --output text))$(AWS_ACCOUNT_ID)

STACK_REGION_PREFIX := $(AWS_$(AWS_REGION)_PREFIX)
STACK_PREFIX := $(STACK_REGION_PREFIX)-eksplayground
