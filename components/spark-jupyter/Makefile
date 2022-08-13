include ../../utils/common.mk

NAME := jupyter
ECR_REPOSITORY = $(AWS_ACCOUNT_ID).dkr.ecr.$(AWS_REGION).amazonaws.com/spark/spark-py

SPARK_VERSION ?= 3.2.1

build:
	docker build --build-arg AWS_ACCOUNT_ID=$(AWS_ACCOUNT_ID) --build-arg AWS_REGION=$(AWS_REGION) --build-arg SPARK_VERSION=$(SPARK_VERSION) -t $(NAME) .

push: build
	docker tag $(NAME):latest $(ECR_REPOSITORY):jupyter-$(SPARK_VERSION)
	docker push $(ECR_REPOSITORY):jupyter-$(SPARK_VERSION)

build-arm:
	docker run --privileged linuxkit/binfmt:v0.8
	docker buildx create --use --name eksplayground --driver docker-container || :
	docker buildx build \
		--platform linux/amd64,linux/arm64 \
		--push \
		--build-arg AWS_ACCOUNT_ID=$(AWS_ACCOUNT_ID) \
		--build-arg AWS_REGION=$(AWS_REGION) \
		--build-arg SPARK_VERSION=$(SPARK_VERSION) \
		--tag $(ECR_REPOSITORY):jupyter-$(SPARK_VERSION) \
		.
