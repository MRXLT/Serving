# 使用uwsgi启动HTTP预测服务

在提供的fit_a_line示例中，启动HTTP预测服务后会看到有以下信息：

```shell
web service address:
http://10.127.3.150:9393/uci/prediction
 * Serving Flask app "serve" (lazy loading)
 * Environment: production
   WARNING: This is a development server. Do not use it in a production deployment.
   Use a production WSGI server instead.
 * Debug mode: off
 * Running on http://0.0.0.0:9393/ (Press CTRL+C to quit)
```

这里会提示启动的HTTP服务是开发模式，并不能用于生产环境的部署。Flask启动的服务环境不够稳定也无法承受大量请求的并发，实际部署过程中配合需要WSGI（Web Server Gateway Interface）使用。

下面我们展示一下如何使用[uWSGI](https://github.com/unbit/uwsgi)模块来部署HTTP预测服务用于生产环境。

编写HTTP服务脚本

```python
#uwsgi_service.py
from paddle_serving_server.web_service import WebService
from flask import Flask, request

#配置预测服务
uci_service = WebService(name = "uci")
uci_service.load_model_config("./uci_housing_model")
uci_service.prepare_server(workdir="./workdir", port=int(9500), device="cpu")
uci_service.run_server()

#配置flask服务
app_instance = Flask(__name__)
@app_instance.before_first_request
def init():
    global uci_service
    uci_service._launch_web_service()

service_name = "/" + uci_service.name + "/prediction"
@app_instance.route(service_name, methods=["POST"])
def run():
    return uci_service.get_prediction(request)

#run方法用于直接调试中直接启动服务
if __name__ == "__main__":
    app_instance.run()
```

使用uwsgi启动HTTP服务

```bash
uwsgi --http :9000 --wsgi-file uwsgi_service.py --callable app_instance --processes 4
```

使用--processes参数可以指定服务的进程数，请注意目前Serving HTTP 服务暂时不支持多线程的方式使用。

更多uWSGI的信息请参考[uWSGI使用文档](https://uwsgi-docs.readthedocs.io/en/latest/)
