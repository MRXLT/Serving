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

import sys
import re

version = sys.argv[1]
for file_name in [
        "./paddle_serving_client/version.py",
        "./paddle_serving_server/version.py",
        "./paddle_serving_server_gpu/version.py"
]:
    lines = ""
    with open(file_name, "r") as f:
        lines = f.read()
        lines = re.sub("\d\.\d\.\d", version, lines, 3)

    with open(file_name, "w") as f:
        f.write(lines)
