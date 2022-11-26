include ../../utils/common.mk

NAME := pyspark-script
ECR_REPOSITORY = $(AWS_ACCOUNT_ID).dkr.ecr.$(AWS_REGION).amazonaws.com/spark/spark-py

SPARK_VERSION ?= 3.3.1

build:
	docker build --build-arg AWS_ACCOUNT_ID=$(AWS_ACCOUNT_ID) --build-arg AWS_REGION=$(AWS_REGION) --build-arg SPARK_VERSION=$(SPARK_VERSION) -t $(NAME) .

push: build
	docker tag $(NAME):latest $(ECR_REPOSITORY):pyspark-script-$(SPARK_VERSION)
	docker push $(ECR_REPOSITORY):pyspark-script-$(SPARK_VERSION)

build-arm:
	docker run --privileged tonistiigi/binfmt --install all
	docker buildx create --use --name eksplayground --driver docker-container || :
	docker buildx build \
		--platform linux/amd64,linux/arm64 \
		--push \
		--build-arg AWS_ACCOUNT_ID=$(AWS_ACCOUNT_ID) \
		--build-arg AWS_REGION=$(AWS_REGION) \
		--build-arg SPARK_VERSION=$(SPARK_VERSION) \
		--tag $(ECR_REPOSITORY):pyspark-script-$(SPARK_VERSION) \
		.

ca.pem:
	$(AWS_CMD) eks describe-cluster --name $(STACK_PREFIX)-eks-cluster --output text --query cluster.certificateAuthority.data | base64 -d > $@

MASTER_URL=$(shell $(AWS_CMD) eks describe-cluster --name $(STACK_PREFIX)-eks-cluster --output text --query cluster.endpoint)

submit:
	../spark/spark-$(SPARK_VERSION)/bin/spark-submit \
		--master k8s://$(MASTER_URL):443 \
		--deploy-mode cluster \
		--name pyspark-app \
		--conf spark.kubernetes.container.image=$(ECR_REPOSITORY):pyspark-script-$(SPARK_VERSION) \
		--conf spark.kubernetes.authenticate.submission.caCertFile=ca.pem \
		--conf spark.kubernetes.container.image.pullPolicy=Always \
		--conf spark.kubernetes.authenticate.driver.serviceAccountName=spark \
		--conf spark.kubernetes.pyspark.pythonVersion=3 \
		--conf spark.executor.instances=3 \
		--conf spark.kubernetes.executor.request.cores=0.85 \
		--conf spark.executor.memory=1280M \
		--conf spark.hadoop.fs.s3a.aws.credentials.provider=com.amazonaws.auth.WebIdentityTokenCredentialsProvider \
		local:///opt/spark/work-dir/main.py