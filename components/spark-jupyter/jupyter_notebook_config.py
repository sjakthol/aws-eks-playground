from s3contents import S3ContentsManager

c = get_config()

c.NotebookApp.contents_manager_class = S3ContentsManager
c.S3ContentsManager.bucket = "en1-eksplayground-spark-jupyter-notebooks"
c.S3ContentsManager.prefix = "notebooks"
