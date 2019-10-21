FROM 000000000000.dkr.ecr.eu-north-1.amazonaws.com/spark/spark-py:2.4.4

RUN set -ex && \
    apk add --no-cache py3-zmq && \
    python3 -m pip install jupyterlab s3contents

ENV PYSPARK_PYTHON python3
ENV PYSPARK_DRIVER_PYTHON jupyter
ENV PYSPARK_DRIVER_PYTHON_OPTS "lab --no-browser --log-level=INFO --ip 0.0.0.0 --allow-root"
EXPOSE 8888

ADD jupyter_notebook_config.py /root/.jupyter/jupyter_notebook_config.py

CMD /opt/spark/bin/pyspark
