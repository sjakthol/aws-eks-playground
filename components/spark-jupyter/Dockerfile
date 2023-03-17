ARG AWS_ACCOUNT_ID
ARG AWS_REGION
ARG SPARK_VERSION

FROM ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/spark/spark-py:${SPARK_VERSION}

USER 0
RUN python3 -m pip install -U pip
RUN python3 -m pip install jupyterlab s3contents

# TODO: Figure out how to drop privileges while keeping Jupyter working

ENV PYSPARK_PYTHON python3
ENV PYSPARK_DRIVER_PYTHON jupyter
ENV PYSPARK_DRIVER_PYTHON_OPTS "lab --no-browser --log-level=INFO --ip 0.0.0.0 --allow-root"
EXPOSE 8888

ADD jupyter_notebook_config.py /root/.jupyter/jupyter_notebook_config.py

CMD /opt/spark/bin/pyspark
