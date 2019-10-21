from pyspark.sql import SparkSession

spark = SparkSession.builder.appName("App").getOrCreate()

try:
    data = spark.read.option('delimiter', '\t')\
            .csv('s3a://amazon-reviews-pds/tsv/amazon_reviews_us_Camera_v1_00.tsv.gz')
    print(data.count())
finally:
    spark.stop()
