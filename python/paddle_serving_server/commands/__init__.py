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
import six
import argparse
from .service_dict import hub_model_dict


class ServingCommand(object):
    def __init__(self):
        self.parser = argparse.ArgumentParser()
        self.init_argument()

    def init_argument(self):
        self.parser.add_argument("command")
        self.parser.add_argument("--model", type=str, default=None)
        self.parser.add_argument("--hub_model", type=str, default=None)
        self.parser.add_argument("--http_port", type=int, default=8080)
        self.parser.add_argument("--gpu_ids", type=int, default=0)
        self.parser.add_argument("--grpc_port", type=int, default=9090)
        self.parser.add_argument("--use_multiprocess", type=int, default=False)
        self.parser.add_argument("--workers", type=int, default=1)
        self.parser.add_argument("--config", type=int, default=None)
        self.parser.add_argument("--script", type=int, default=None)

    def run(self):
        try:
            self.args = self.parser.parse_args()
        except:
            self.show_help()
            return
        command = self.args.command
        if command == "start":
            self.start_serving()
        elif command == "stop":
            self.stop_serving()

    def start_serving(self):
        # start service
        if self.args.hub_model is not None and self.args.model is not None:
            raise RuntimeError(
                "Do not use '--hub_model' and '--model' at the same time.")
        if self.args.hub_model is not None:
            model_name = self.args.hub_model
            if model_name in hub_model_dict:
                hub_model_service = self.prepare_hub_model_service(model_name)
                hub_model_service.prepare_pipeline_config()
                hub_model_service.run_service()
            else:
                print("Start hub serving instead.")
                self.run_hub_serving(model_name)
        elif self.args.model is not None:
            pass
        else:
            raise RuntimeError(
                "Please set model for service by '--hub_model' or '--model'.")

    def prepare_hub_model_service(self, model_name):
        # load and return hub model service
        hub_model_service = hub_model_dict["model_name"]
        return hub_model_service

    def run_hub_serving(self, model_name):
        pass

    def save_pid_file(self):
        pass

    def stop_serving(self):
        pass

    def show_help(self):
        pass


def main():
    serving_command = ServingCommand()
    serving_command.run()
