# Some defaults
AWS ?= aws
AWS_REGION ?= eu-north-1
AWS_PROFILE ?= default

AWS_CMD := $(AWS) --profile $(AWS_PROFILE) --region $(AWS_REGION)
AWS_ACCOUNT_ID ?= 000000000000

NAME := $(notdir $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST))))))
ECR_REPOSITORY := $(AWS_ACCOUNT_ID).dkr.ecr.$(AWS_REGION).amazonaws.com/eksplayground/$(NAME)

login:
	$(AWS_CMD) ecr get-login --no-include-email | bash

build:
	docker build -t $(NAME) .

tag: build
	docker tag $(NAME):latest $(ECR_REPOSITORY):latest

push: login tag
	docker push $(ECR_REPOSITORY):latest
