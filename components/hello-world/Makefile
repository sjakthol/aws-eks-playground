NAME := $(notdir $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST))))))
ECR_REPOSITORY = $(AWS_ACCOUNT_ID).dkr.ecr.$(AWS_REGION).amazonaws.com/eksplayground/$(NAME)

include ../../utils/common.mk

build:
	docker build --pull -t $(NAME) .

build-arm:
	docker run --privileged tonistiigi/binfmt --install all
	docker buildx create --use --name eksplayground --driver docker-container || :
	docker buildx build \
		--platform linux/amd64,linux/arm64 \
		--push \
		--tag $(ECR_REPOSITORY):latest \
		.

push: build
	docker tag $(NAME):latest $(ECR_REPOSITORY):latest
	docker push $(ECR_REPOSITORY):latest
