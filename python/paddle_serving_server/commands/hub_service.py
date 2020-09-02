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

import paddlehub as hub
from ..web_service import WebService
import os
import shutil
from paddle_serving_client.io import inference_model_to_serving


class HubService(WebService):
    def __init__(self, name):
        self.module = hub.Module(name)
        self.prepare_model_file()
        super(HubService, self).__init__(name)

    def prepare_model_file(self):
        model_dir = os.path.join(self.module.directory, "infer_model")
        os.chdir(model_dir)
        if not os.path.exists("serving_server_conf.prototxt"):
            inference_model_to_serving(
                dirname=".",
                serving_server="serving_server",
                serving_client="serving_client")
            shutil.copy("serving_server/serving_server_conf.prototxt",
                        "infer_model")
