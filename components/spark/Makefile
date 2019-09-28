# Mapping from long region names to shorter ones that is to be
# used in the stack names
AWS_ap-northeast-1_PREFIX = an1
AWS_ap-northeast-2_PREFIX = an2
AWS_ap-south-1_PREFIX = as1
AWS_ap-southeast-1_PREFIX = as1
AWS_ap-southeast-2_PREFIX = as2
AWS_ca-central-1_PREFIX = cc1
AWS_eu-central-1_PREFIX = ec1
AWS_eu-west-1_PREFIX = ew1
AWS_eu-west-2_PREFIX = ew2
AWS_eu-west-3_PREFIX = ew3
AWS_sa-east-1_PREFIX = se1
AWS_us-east-1_PREFIX = ue1
AWS_us-east-2_PREFIX = ue2
AWS_us-west-1_PREFIX = uw1
AWS_us-west-2_PREFIX = uw2
AWS_eu-north-1_PREFIX = en1

# Some defaults
AWS ?= aws
AWS_REGION ?= eu-north-1
AWS_PROFILE ?= default

AWS_CMD := $(AWS) --profile $(AWS_PROFILE) --region $(AWS_REGION)
AWS_ACCOUNT_ID = $(eval AWS_ACCOUNT_ID := $(shell $(AWS_CMD) sts get-caller-identity --query Account --output text))$(AWS_ACCOUNT_ID)

NAME := $(notdir $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST))))))
ECR_REPOSITORY = $(AWS_ACCOUNT_ID).dkr.ecr.$(AWS_REGION).amazonaws.com/$(NAME)

STACK_REGION_PREFIX := $(AWS_$(AWS_REGION)_PREFIX)
STACK_PREFIX := $(STACK_REGION_PREFIX)-eksplayground
SPARK_VERSION ?= 2.4.4

login:
	$(AWS_CMD) ecr get-login --no-include-email | bash

spark-$(SPARK_VERSION)-bin-hadoop2.7:
	curl -sSfL http://www.nic.funet.fi/pub/mirrors/apache.org/spark/spark-$(SPARK_VERSION)/spark-$(SPARK_VERSION)-bin-hadoop2.7.tgz | tar xzv

	# To workaround SPARK-28921 / SPARK-28925
	rm spark-$(SPARK_VERSION)-bin-hadoop2.7/jars/kubernetes-*.jar
	curl -sSfLo spark-$(SPARK_VERSION)-bin-hadoop2.7/jars/kubernetes-client-4.4.2.jar https://repo1.maven.org/maven2/io/fabric8/kubernetes-client/4.4.2/kubernetes-client-4.4.2.jar
	curl -sSfLo spark-$(SPARK_VERSION)-bin-hadoop2.7/jars/kubernetes-model-4.4.2.jar https://repo1.maven.org/maven2/io/fabric8/kubernetes-model/4.4.2/kubernetes-model-4.4.2.jar
	curl -sSfLo spark-$(SPARK_VERSION)-bin-hadoop2.7/jars/kubernetes-model-common-4.4.2.jar https://repo1.maven.org/maven2/io/fabric8/kubernetes-model-common/4.4.2/kubernetes-model-common-4.4.2.jar

build: login spark-$(SPARK_VERSION)-bin-hadoop2.7
	cd spark-$(SPARK_VERSION)-bin-hadoop2.7 && ./bin/docker-image-tool.sh -r $(ECR_REPOSITORY) -t $(SPARK_VERSION) build
	cd spark-$(SPARK_VERSION)-bin-hadoop2.7 && ./bin/docker-image-tool.sh -r $(ECR_REPOSITORY) -t $(SPARK_VERSION) push

ca.pem:
	$(AWS_CMD) eks describe-cluster --name $(STACK_PREFIX)-eks-cluster --output text --query cluster.certificateAuthority.data | base64 -d > $@

MASTER_URL=$(shell $(AWS_CMD) eks describe-cluster --name $(STACK_PREFIX)-eks-cluster --output text --query cluster.endpoint)

submit: spark-$(SPARK_VERSION)-bin-hadoop2.7 ca.pem
	./spark-$(SPARK_VERSION)-bin-hadoop2.7/bin/spark-submit \
		--master k8s://$(MASTER_URL):443 \
		--deploy-mode cluster \
		--name spark-pi \
		--class org.apache.spark.examples.SparkPi \
		--conf spark.executor.instances=2 \
		--conf spark.kubernetes.container.image=$(ECR_REPOSITORY)/spark:$(SPARK_VERSION) \
		--conf spark.kubernetes.authenticate.submission.caCertFile=ca.pem \
		--conf spark.kubernetes.container.image.pullPolicy=Always \
		--conf spark.kubernetes.authenticate.driver.serviceAccountName=spark \
		--conf spark.kubernetes.executor.request.cores=0.25 \
		file:///opt/spark/examples/jars/spark-examples_2.11-$(SPARK_VERSION).jar