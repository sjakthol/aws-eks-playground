# Some defaults
AWS ?= aws
AWS_REGION ?= eu-north-1
AWS_PROFILE ?= default

AWS_CMD := $(AWS) --profile $(AWS_PROFILE) --region $(AWS_REGION)
AWS_ACCOUNT_ID = $(eval AWS_ACCOUNT_ID := $(shell $(AWS_CMD) sts get-caller-identity --query Account --output text))$(AWS_ACCOUNT_ID)

NAME := $(notdir $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST))))))
ECR_REPOSITORY = $(AWS_ACCOUNT_ID).dkr.ecr.$(AWS_REGION).amazonaws.com/eksplayground/$(NAME)

login:
	$(AWS_CMD) ecr get-login-password | docker login --username AWS --password-stdin $(AWS_ACCOUNT_ID).dkr.ecr.$(AWS_REGION).amazonaws.com

build:
	docker build -t $(NAME) .

build-arm: login
	docker run --privileged linuxkit/binfmt:v0.8
	docker buildx create --use --name eksplayground --driver docker-container || :
	docker buildx build \
		--platform linux/amd64,linux/arm64 \
		--push \
		--tag $(ECR_REPOSITORY):latest \
		.

push: build login
	docker tag $(NAME):latest $(ECR_REPOSITORY):latest
	docker push $(ECR_REPOSITORY):latest
