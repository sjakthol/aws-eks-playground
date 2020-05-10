include ../../utils/common.mk

NAME := pyspark-script
ECR_REPOSITORY = $(AWS_ACCOUNT_ID).dkr.ecr.$(AWS_REGION).amazonaws.com/spark/spark-py

SPARK_VERSION ?= 3.0.0-preview2

build:
	docker build --build-arg AWS_ACCOUNT_ID=$(AWS_ACCOUNT_ID) --build-arg SPARK_VERSION=$(SPARK_VERSION) -t $(NAME) .

push: build login
	docker tag $(NAME):latest $(ECR_REPOSITORY):pyspark-script-$(SPARK_VERSION)
	docker push $(ECR_REPOSITORY):pyspark-script-$(SPARK_VERSION)

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
		local:///opt/spark/work-dir/main.py