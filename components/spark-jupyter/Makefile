# Some defaults
AWS ?= aws
AWS_REGION ?= eu-north-1
AWS_PROFILE ?= default

AWS_CMD := $(AWS) --profile $(AWS_PROFILE) --region $(AWS_REGION)
AWS_ACCOUNT_ID = $(eval AWS_ACCOUNT_ID := $(shell $(AWS_CMD) sts get-caller-identity --query Account --output text))$(AWS_ACCOUNT_ID)

NAME := jupyter
ECR_REPOSITORY = $(AWS_ACCOUNT_ID).dkr.ecr.$(AWS_REGION).amazonaws.com/spark/spark-py

login:
	$(AWS_CMD) ecr get-login --no-include-email | bash

build:
	docker build -t $(NAME) .

push: build login
	docker tag $(NAME):latest $(ECR_REPOSITORY):jupyter-latest
	docker push $(ECR_REPOSITORY):jupyter-latest
