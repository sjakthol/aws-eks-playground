include ../../utils/common.mk

NAME := jupyter
ECR_REPOSITORY = $(AWS_ACCOUNT_ID).dkr.ecr.$(AWS_REGION).amazonaws.com/spark/spark-py

SPARK_VERSION ?= 3.0.1

build:
	docker build --build-arg AWS_ACCOUNT_ID=$(AWS_ACCOUNT_ID) --build-arg SPARK_VERSION=$(SPARK_VERSION) -t $(NAME) .

push: build login
	docker tag $(NAME):latest $(ECR_REPOSITORY):jupyter-$(SPARK_VERSION)
	docker push $(ECR_REPOSITORY):jupyter-$(SPARK_VERSION)
