# Copyright (c) 2020 PaddlePaddle Authors. All Rights Reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

from paddle_serving_client import Client
from paddle_serving_app.reader import File2Image, Resize, Normalize, Sequential, Div, BGR2RGB, Transpose
from paddle_serving_app.reader import RCNNPostprocess
import sys
import numpy as np
from paddle_serving_app.local_predict import Debugger
image_file = sys.argv[1]

read_image = Sequential([File2Image()])
preprocess = Sequential([
    BGR2RGB(), Resize(
        (608, 608), interpolation=2), Div(255.0),
    Normalize([0.485, 0.456, 0.406], [0.229, 0.224, 0.225], False), Transpose(
        (2, 0, 1))
])

postprocess = RCNNPostprocess("./labellist.txt", "output")
origin_image = read_image(image_file)

image = preprocess(origin_image)
im_size = np.array(list(origin_image.shape[:2]))
feed = {"image": image, "im_size": im_size}
fetch = ["matrix_nms_0.tmp_0"]

client = Client()
client.load_client_config("./serving_client/serving_client_conf.prototxt")
client.connect(["127.0.0.1:9393"])
fetch_map = client.predict(feed=feed, fetch=fetch)
fetch_map["image"] = image_file
postprocess(fetch_map)
