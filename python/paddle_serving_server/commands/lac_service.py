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

from ..web_service import Op
from .hub_service import HubService


class LacOp(Op):
    def preprocess(self, input_dicts):
        pass

    def postprocess(self, input_dicts, fetch_dict):
        pass


class LacService(HubService):
    def get_pipeline_reponse(self, read_op):
        lac_op = LacOp(name="lac", input_ops=[read_op])
        return lac_op
