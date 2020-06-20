NAME := $(notdir $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST))))))
ECR_REPOSITORY = $(AWS_ACCOUNT_ID).dkr.ecr.$(AWS_REGION).amazonaws.com/$(NAME)

SPARK_VERSION ?= 3.0.0
ifeq ($(SPARK_VERSION), 3.0.0)
	SCALA_VERSION = 2.12
else
	SCALA_VERSION = 2.11
endif

include ../../utils/common.mk

spark-2.4.6:
	curl -sSfL http://www.nic.funet.fi/pub/mirrors/apache.org/spark/spark-2.4.6/spark-2.4.6-bin-hadoop2.7.tgz | tar xzv

	# To workaround SPARK-28921 / SPARK-28925
	rm spark-2.4.6-bin-hadoop2.7/jars/kubernetes-*.jar
	curl -sSfLo spark-2.4.6-bin-hadoop2.7/jars/kubernetes-client-4.4.2.jar https://repo1.maven.org/maven2/io/fabric8/kubernetes-client/4.4.2/kubernetes-client-4.4.2.jar
	curl -sSfLo spark-2.4.6-bin-hadoop2.7/jars/kubernetes-model-4.4.2.jar https://repo1.maven.org/maven2/io/fabric8/kubernetes-model/4.4.2/kubernetes-model-4.4.2.jar
	curl -sSfLo spark-2.4.6-bin-hadoop2.7/jars/kubernetes-model-common-4.4.2.jar https://repo1.maven.org/maven2/io/fabric8/kubernetes-model-common/4.4.2/kubernetes-model-common-4.4.2.jar

	# Apply some fixes and modifications
	cd spark-2.4.6-bin-hadoop2.7/ && patch -p1 < ../patches/01-backport-spark-26083.patch
	cd spark-2.4.6-bin-hadoop2.7/ && patch -p1 < ../patches/02-install-hadoop-aws.patch

	mv spark-2.4.6-bin-hadoop2.7 spark-2.4.6

spark-3.0.0:
	curl -sSfL https://archive.apache.org/dist/spark/spark-3.0.0/spark-3.0.0-bin-hadoop3.2.tgz | tar xzv
	mv spark-3.0.0-bin-hadoop3.2 spark-3.0.0

	cd spark-3.0.0/ && patch -p1 < ../patches/02-install-hadoop-aws-3.2.patch

build: login spark-$(SPARK_VERSION)
	cd spark-$(SPARK_VERSION) && ./bin/docker-image-tool.sh -r $(ECR_REPOSITORY) -t $(SPARK_VERSION) -p kubernetes/dockerfiles/spark/bindings/python/Dockerfile build
	cd spark-$(SPARK_VERSION) && ./bin/docker-image-tool.sh -r $(ECR_REPOSITORY) -t $(SPARK_VERSION) -p kubernetes/dockerfiles/spark/bindings/python/Dockerfile push

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
		local:///opt/spark/examples/jars/spark-examples_$(SCALA_VERSION)-$(SPARK_VERSION).jar
