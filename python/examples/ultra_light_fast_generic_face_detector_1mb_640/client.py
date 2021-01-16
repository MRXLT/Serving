from paddle_serving_client import Client
import sys
from processor import preprocess,postprocess

client = Client()
# load client prototxt
client.load_client_config("./serving_client/serving_client_conf.prototxt")
client.connect(['127.0.0.1:9494'])
image= preprocess(sys.argv[1])
fetch_map = client.predict(
    feed={"_input": image}, fetch=["save_infer_model/scale_0.tmp_0","save_infer_model/scale_1.tmp_0"])
fetch_map["image"] = sys.argv[1]
postprocess(image_with_bbox = fetch_map)
