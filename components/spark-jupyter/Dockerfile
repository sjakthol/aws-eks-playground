ARG AWS_ACCOUNT_ID
ARG SPARK_VERSION

FROM ${AWS_ACCOUNT_ID}.dkr.ecr.eu-north-1.amazonaws.com/spark/spark-py:${SPARK_VERSION}

USER 0

# Spark v2.4.4 image is based on Alphine which does not have build tools required to
# install zeromq. Hence, install it through apk.
#
# Spark v3.0.0 image is based on Debian which has build tools available. Hence, install
# zeromq with pip.

RUN set -ex && \
    command -v apk && apk add --no-cache py3-zmq || true && \
    python3 -m pip install jupyterlab s3contents

# TODO: Figure out how to drop privileges while keeping Jupyter working

ENV PYSPARK_PYTHON python3
ENV PYSPARK_DRIVER_PYTHON jupyter
ENV PYSPARK_DRIVER_PYTHON_OPTS "lab --no-browser --log-level=INFO --ip 0.0.0.0 --allow-root"
EXPOSE 8888

ADD jupyter_notebook_config.py /root/.jupyter/jupyter_notebook_config.py

CMD /opt/spark/bin/pyspark
