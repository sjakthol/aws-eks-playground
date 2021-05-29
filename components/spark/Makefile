NAME := $(notdir $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST))))))
ECR_REPOSITORY = $(AWS_ACCOUNT_ID).dkr.ecr.$(AWS_REGION).amazonaws.com/$(NAME)

SPARK_VERSION ?= 3.1.1
SCALA_VERSION = 2.12

include ../../utils/common.mk


spark-3.1.1:
	curl -sSfL https://archive.apache.org/dist/spark/spark-3.1.1/spark-3.1.1-bin-hadoop3.2.tgz | tar xzv
	mv spark-3.1.1-bin-hadoop3.2 spark-3.1.1

	cd spark-3.1.1/ && patch -p1 < ../patches/3.0_01-install-hadoop-aws-3.2.patch

build: login spark-$(SPARK_VERSION)
	cd spark-$(SPARK_VERSION) && ./bin/docker-image-tool.sh -r $(ECR_REPOSITORY) -t $(SPARK_VERSION) -p kubernetes/dockerfiles/spark/bindings/python/Dockerfile build
	cd spark-$(SPARK_VERSION) && ./bin/docker-image-tool.sh -r $(ECR_REPOSITORY) -t $(SPARK_VERSION) -p kubernetes/dockerfiles/spark/bindings/python/Dockerfile push

build-arm: login spark-$(SPARK_VERSION)
	docker run --privileged linuxkit/binfmt:v0.8
	docker buildx create --use --name eksplayground --driver docker-container || :
	cd spark-$(SPARK_VERSION) && \
		docker buildx build \
			--platform linux/amd64,linux/arm64 \
			--push \
			--build-arg java_image_tag=11-jre-slim \
			--tag $(ECR_REPOSITORY)/spark:$(SPARK_VERSION) \
			--file kubernetes/dockerfiles/spark/Dockerfile .

	cd spark-$(SPARK_VERSION) && \
		docker buildx build \
		--platform linux/amd64,linux/arm64 \
		--push \
		--build-arg base_img=$(ECR_REPOSITORY)/spark:$(SPARK_VERSION) \
		--tag $(ECR_REPOSITORY)/spark-py:$(SPARK_VERSION) \
		--file kubernetes/dockerfiles/spark/bindings/python/Dockerfile .

ca.pem:
	$(AWS_CMD) eks describe-cluster --name $(STACK_PREFIX)-eks-cluster --output text --query cluster.certificateAuthority.data | base64 -d > $@

MASTER_URL=$(shell $(AWS_CMD) eks describe-cluster --name $(STACK_PREFIX)-eks-cluster --output text --query cluster.endpoint)

submit: spark-$(SPARK_VERSION) ca.pem
	./spark-$(SPARK_VERSION)/bin/spark-submit \
		--master k8s://$(MASTER_URL):443 \
		--deploy-mode cluster \
		--name spark-pi \
		--class org.apache.spark.examples.SparkPi \
		--conf spark.kubernetes.container.image=$(ECR_REPOSITORY)/spark:$(SPARK_VERSION) \
		--conf spark.kubernetes.authenticate.submission.caCertFile=ca.pem \
		--conf spark.kubernetes.container.image.pullPolicy=Always \
		--conf spark.kubernetes.authenticate.driver.serviceAccountName=spark \
		--conf spark.executor.instances=3 \
		--conf spark.kubernetes.executor.request.cores=0.85 \
		--conf spark.executor.memory=1416M \
		--conf spark.hadoop.fs.s3a.aws.credentials.provider=com.amazonaws.auth.WebIdentityTokenCredentialsProvider \
		local:///opt/spark/examples/jars/spark-examples_$(SCALA_VERSION)-$(SPARK_VERSION).jar
