#coding=utf-8
#导入BosClient配置文件
import bos_sample_conf
import sys

#导入BOS相关模块
from baidubce import exception
from baidubce.services import bos
from baidubce.services.bos import canned_acl
from baidubce.services.bos.bos_client import BosClient

#新建BosClient
bos_client = BosClient(bos_sample_conf.config)
file_name = sys.argv[1]
bos_client.put_object_from_file("paddle-serving", "bin/{}".format(file_name),
                                "{}".format(file_name))
print("upload {} success".format(file_name))
