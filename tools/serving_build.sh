#!/usr/bin/env bash

function unsetproxy() {
    HTTP_PROXY_TEMP=$http_proxy
    HTTPS_PROXY_TEMP=$https_proxy
    unset http_proxy
    unset https_proxy
}

function setproxy() {
    export http_proxy=$HTTP_PROXY_TEMP
    export https_proxy=$HTTPS_PROXY_TEMP
}

function init() {
    source /root/.bashrc
    set -v
    export PYTHONROOT=/usr
    cd Serving
    export SERVING_WORKDIR=$PWD
    $PYTHONROOT/bin/python -m pip install -r python/requirements.txt
}

function check_cmd() {
    eval $@
    if [ $? -ne 0 ]; then
        exit 1
    fi
}

function rerun() {
    if [ $# -ne 2 ]; then
        echo "usage: rerun command rerun-times"
        exit 1
    fi
    local command=$1
    local times=$2
    for((i=1;i<=${times};i++))
    do
        if [ ${i} != 1 ]; then
            echo "${i}-th run command: ${command}..."
        fi
        eval $command
        if [ $? -eq 0 ]; then
            return 0
        fi
        echo "${i}-th run(command: ${command}) failed."
    done
    exit 1
}

function build_app() {
    local TYPE=$1
    local DIRNAME=build-app-$TYPE
    mkdir $DIRNAME # pwd: /Serving
    cd $DIRNAME # pwd: /Serving/build-app-$TYPE
    pip install numpy sentencepiece
    case $TYPE in
        CPU|GPU)
            cmake -DPYTHON_INCLUDE_DIR=$PYTHONROOT/include/python2.7/ \
                  -DPYTHON_LIBRARIES=$PYTHONROOT/lib/libpython2.7.so \
                  -DPYTHON_EXECUTABLE=$PYTHONROOT/bin/python \
                  -DAPP=ON ..
            rerun "make -j2 >/dev/null" 3 # due to some network reasons, compilation may fail
            pip install -U python/dist/paddle_serving_app* >/dev/null
            ;;
        *)
            echo "error type"
            exit 1
            ;;
    esac
    echo "build app $TYPE part finished as expected."
    cd .. # pwd: /Serving
}

function build_client() {
    local TYPE=$1
    local DIRNAME=build-client-$TYPE
    mkdir $DIRNAME # pwd: /Serving
    cd $DIRNAME # pwd: /Serving/build-client-$TYPE
    case $TYPE in
        CPU|GPU)
            cmake -DPYTHON_INCLUDE_DIR=$PYTHONROOT/include/python2.7/ \
                  -DPYTHON_LIBRARIES=$PYTHONROOT/lib64/libpython2.7.so \
                  -DPYTHON_EXECUTABLE=$PYTHONROOT/bin/python \
                  -DCLIENT=ON ..
            rerun "make -j2 >/dev/null" 3 # due to some network reasons, compilation may fail
            pip install -U python/dist/paddle_serving_client* >/dev/null
            ;;
        *)
            echo "error type"
            exit 1
            ;;
    esac
    echo "build client $TYPE part finished as expected."
    cd .. # pwd: /Serving
    # rm -rf $DIRNAME
}

function build_server() {
    local TYPE=$1
    local DIRNAME=build-server-$TYPE
    mkdir $DIRNAME # pwd: /Serving
    cd $DIRNAME # pwd: /Serving/build-server-$TYPE
    case $TYPE in
        CPU)
            cmake -DPYTHON_INCLUDE_DIR=$PYTHONROOT/include/python2.7/ \
                  -DPYTHON_LIBRARIES=$PYTHONROOT/lib64/libpython2.7.so \
                  -DPYTHON_EXECUTABLE=$PYTHONROOT/bin/python \
                  -DSERVER=ON ..
            rerun "make -j2 >/dev/null" 3 # due to some network reasons, compilation may fail
            check_cmd "make install -j2 >/dev/null"
            pip install -U python/dist/paddle_serving_server* >/dev/null
            ;;
        GPU)
            cmake -DPYTHON_INCLUDE_DIR=$PYTHONROOT/include/python2.7/ \
                  -DPYTHON_LIBRARIES=$PYTHONROOT/lib64/libpython2.7.so \
                  -DPYTHON_EXECUTABLE=$PYTHONROOT/bin/python \
                  -DSERVER=ON \
                  -DWITH_GPU=ON ..
            rerun "make -j2 >/dev/null" 3 # due to some network reasons, compilation may fail
            check_cmd "make install -j2 >/dev/null"
            pip install -U python/dist/paddle_serving_server* >/dev/null
            ;;
        *)
            echo "error type"
            exit 1
            ;;
    esac
    echo "build server $TYPE part finished as expected."
    cd .. # pwd: /Serving
    # rm -rf $DIRNAME    for export SERVING_BIN
}

function kill_server_process() {
    ps -ef | grep "serving" | grep -v serving_build | grep -v grep | awk '{print $2}' | xargs kill
}

function python_test_fit_a_line() {
    # pwd: /Serving/python/examples
    cd fit_a_line # pwd: /Serving/python/examples/fit_a_line
    sh get_data.sh
    local TYPE=$1
    export SERVING_BIN=${SERVING_WORKDIR}/build-server-${TYPE}/core/general-server/serving
    case $TYPE in
        CPU)
            # test rpc
            check_cmd "python -m paddle_serving_server.serve --model uci_housing_model --port 9393 --thread 4 > /dev/null &"
            sleep 5 # wait for the server to start
            check_cmd "python test_client.py uci_housing_client/serving_client_conf.prototxt > /dev/null"
            kill_server_process

            # test web
            unsetproxy # maybe the proxy is used on iPipe, which makes web-test failed.
            check_cmd "python -m paddle_serving_server.serve --model uci_housing_model --name uci --port 9393 --thread 4 --name uci > /dev/null &"
            sleep 5 # wait for the server to start
            check_cmd "curl -H \"Content-Type:application/json\" -X POST -d '{\"feed\":[{\"x\": [0.0137, -0.1136, 0.2553, -0.0692, 0.0582, -0.0727, -0.1583, -0.0584, 0.6283, 0.4919, 0.1856, 0.0795, -0.0332]}], \"fetch\":[\"price\"]}' http://127.0.0.1:9393/uci/prediction"
            # check http code
            http_code=`curl -H "Content-Type:application/json" -X POST -d '{"feed":[{"x": [0.0137, -0.1136, 0.2553, -0.0692, 0.0582, -0.0727, -0.1583, -0.0584, 0.6283, 0.4919, 0.1856, 0.0795, -0.0332]}], "fetch":["price"]}' -s -w "%{http_code}" -o /dev/null http://127.0.0.1:9393/uci/prediction`
            if [ ${http_code} -ne 200 ]; then
                echo "HTTP status code -ne 200"
                exit 1
            fi
            # test web batch
            check_cmd "curl -H \"Content-Type:application/json\" -X POST -d '{\"feed\":[{\"x\": [0.0137, -0.1136, 0.2553, -0.0692, 0.0582, -0.0727, -0.1583, -0.0584, 0.6283, 0.4919, 0.1856, 0.0795, -0.0332]}, {\"x\": [0.0137, -0.1136, 0.2553, -0.0692, 0.0582, -0.0727, -0.1583, -0.0584, 0.6283, 0.4919, 0.1856, 0.0795, -0.0332]}], \"fetch\":[\"price\"]}' http://127.0.0.1:9393/uci/prediction"
            # check http code
            http_code=`curl -H "Content-Type:application/json" -X POST -d '{"feed":[{"x": [0.0137, -0.1136, 0.2553, -0.0692, 0.0582, -0.0727, -0.1583, -0.0584, 0.6283, 0.4919, 0.1856, 0.0795, -0.0332]}, {"x": [0.0137, -0.1136, 0.2553, -0.0692, 0.0582, -0.0727, -0.1583, -0.0584, 0.6283, 0.4919, 0.1856, 0.0795, -0.0332]}], "fetch":["price"]}' -s -w "%{http_code}" -o /dev/null http://127.0.0.1:9393/uci/prediction`
            if [ ${http_code} -ne 200 ]; then
                echo "HTTP status code -ne 200"
                exit 1
            fi
            setproxy # recover proxy state
            kill_server_process
            ;;
        GPU)
            export CUDA_VISIBLE_DEVICES=0
            # test rpc
            check_cmd "python -m paddle_serving_server_gpu.serve --model uci_housing_model --port 9393 --thread 4 --gpu_ids 0 > /dev/null &"
            sleep 5 # wait for the server to start
            check_cmd "python test_client.py uci_housing_client/serving_client_conf.prototxt > /dev/null"
            kill_server_process

            # test web
            unsetproxy # maybe the proxy is used on iPipe, which makes web-test failed.
            check_cmd "python -m paddle_serving_server_gpu.serve --model uci_housing_model --port 9393 --thread 2 --gpu_ids 0 --name uci > /dev/null &"
            sleep 5 # wait for the server to start
            check_cmd "curl -H \"Content-Type:application/json\" -X POST -d '{\"feed\":[{\"x\": [0.0137, -0.1136, 0.2553, -0.0692, 0.0582, -0.0727, -0.1583, -0.0584, 0.6283, 0.4919, 0.1856, 0.0795, -0.0332]}], \"fetch\":[\"price\"]}' http://127.0.0.1:9393/uci/prediction"
            # check http code
            http_code=`curl -H "Content-Type:application/json" -X POST -d '{"feed":[{"x": [0.0137, -0.1136, 0.2553, -0.0692, 0.0582, -0.0727, -0.1583, -0.0584, 0.6283, 0.4919, 0.1856, 0.0795, -0.0332]}], "fetch":["price"]}' -s -w "%{http_code}" -o /dev/null http://127.0.0.1:9393/uci/prediction`
            if [ ${http_code} -ne 200 ]; then
                echo "HTTP status code -ne 200"
                exit 1
            fi
            # test web batch
            check_cmd "curl -H \"Content-Type:application/json\" -X POST -d '{\"feed\":[{\"x\": [0.0137, -0.1136, 0.2553, -0.0692, 0.0582, -0.0727, -0.1583, -0.0584, 0.6283, 0.4919, 0.1856, 0.0795, -0.0332]}, {\"x\": [0.0137, -0.1136, 0.2553, -0.0692, 0.0582, -0.0727, -0.1583, -0.0584, 0.6283, 0.4919, 0.1856, 0.0795, -0.0332]}], \"fetch\":[\"price\"]}' http://127.0.0.1:9393/uci/prediction"
            # check http code
            http_code=`curl -H "Content-Type:application/json" -X POST -d '{"feed":[{"x": [0.0137, -0.1136, 0.2553, -0.0692, 0.0582, -0.0727, -0.1583, -0.0584, 0.6283, 0.4919, 0.1856, 0.0795, -0.0332]}, {"x": [0.0137, -0.1136, 0.2553, -0.0692, 0.0582, -0.0727, -0.1583, -0.0584, 0.6283, 0.4919, 0.1856, 0.0795, -0.0332]}], "fetch":["price"]}' -s -w "%{http_code}" -o /dev/null http://127.0.0.1:9393/uci/prediction`
            if [ ${http_code} -ne 200 ]; then
                echo "HTTP status code -ne 200"
                exit 1
            fi
            setproxy # recover proxy state
            kill_server_process
            ;;
        *)
            echo "error type"
            exit 1
            ;;
    esac
    echo "test fit_a_line $TYPE part finished as expected."
    rm -rf image kvdb log uci_housing* work*
    unset SERVING_BIN
    cd .. # pwd: /Serving/python/examples
}

function python_run_criteo_ctr_with_cube() {
    # pwd: /Serving/python/examples
    local TYPE=$1
    yum install -y bc >/dev/null
    cd criteo_ctr_with_cube # pwd: /Serving/python/examples/criteo_ctr_with_cube
    export SERVING_BIN=${SERVING_WORKDIR}/build-server-${TYPE}/core/general-server/serving
    case $TYPE in
        CPU)
            check_cmd "wget https://paddle-serving.bj.bcebos.com/unittest/ctr_cube_unittest.tar.gz"
            check_cmd "tar xf ctr_cube_unittest.tar.gz"
            check_cmd "mv models/ctr_client_conf ./"
            check_cmd "mv models/ctr_serving_model_kv ./"
            check_cmd "mv models/data ./cube/"
            check_cmd "mv models/ut_data ./"
            cp ../../../build-server-$TYPE/output/bin/cube* ./cube/
            mkdir -p $PYTHONROOT/lib/python2.7/site-packages/paddle_serving_server/serving-cpu-avx-openblas-0.1.3/
            yes | cp ../../../build-server-$TYPE/output/demo/serving/bin/serving $PYTHONROOT/lib/python2.7/site-packages/paddle_serving_server/serving-cpu-avx-openblas-0.1.3/
            sh cube_prepare.sh &
            check_cmd "mkdir work_dir1 && cp cube/conf/cube.conf ./work_dir1/"
            python test_server.py ctr_serving_model_kv &
            sleep 5
            check_cmd "python test_client.py ctr_client_conf/serving_client_conf.prototxt ./ut_data >score"
            tail -n 2 score | awk 'NR==1'
            AUC=$(tail -n 2  score | awk 'NR==1')
            VAR2="0.67" #TODO: temporarily relax the threshold to 0.67
            RES=$( echo "$AUC>$VAR2" | bc )
            if [[ $RES -eq 0 ]]; then
                echo "error with criteo_ctr_with_cube inference auc test, auc should > 0.67"
                exit 1
            fi
            echo "criteo_ctr_with_cube inference auc test success"
            kill_server_process
            ps -ef | grep "cube" | grep -v grep | awk '{print $2}' | xargs kill
            ;;
        GPU)
            check_cmd "wget https://paddle-serving.bj.bcebos.com/unittest/ctr_cube_unittest.tar.gz"
            check_cmd "tar xf ctr_cube_unittest.tar.gz"
            check_cmd "mv models/ctr_client_conf ./"
            check_cmd "mv models/ctr_serving_model_kv ./"
            check_cmd "mv models/data ./cube/"
            check_cmd "mv models/ut_data ./"
            cp ../../../build-server-$TYPE/output/bin/cube* ./cube/
            mkdir -p $PYTHONROOT/lib/python2.7/site-packages/paddle_serving_server_gpu/serving-gpu-0.1.3/
            yes | cp ../../../build-server-$TYPE/output/demo/serving/bin/serving $PYTHONROOT/lib/python2.7/site-packages/paddle_serving_server_gpu/serving-gpu-0.1.3/
            sh cube_prepare.sh &
            check_cmd "mkdir work_dir1 && cp cube/conf/cube.conf ./work_dir1/"
            python test_server_gpu.py ctr_serving_model_kv &
            sleep 5
            check_cmd "python test_client.py ctr_client_conf/serving_client_conf.prototxt ./ut_data >score"
            tail -n 2 score | awk 'NR==1'
            AUC=$(tail -n 2  score | awk 'NR==1')
            VAR2="0.67" #TODO: temporarily relax the threshold to 0.67
            RES=$( echo "$AUC>$VAR2" | bc )
            if [[ $RES -eq 0 ]]; then
                echo "error with criteo_ctr_with_cube inference auc test, auc should > 0.67"
                exit 1
            fi
            echo "criteo_ctr_with_cube inference auc test success"
            kill_server_process
            ps -ef | grep "cube" | grep -v grep | awk '{print $2}' | xargs kill
            ;;
        *)
            echo "error type"
            exit 1
            ;;
    esac
    unset SERVING_BIN
    echo "test criteo_ctr_with_cube $TYPE part finished as expected."
    cd .. # pwd: /Serving/python/examples
}

function python_test_bert() {
    # pwd: /Serving/python/examples
    local TYPE=$1
    yum install -y libXext libSM libXrender >/dev/null
    pip install ujson
    export SERVING_BIN=${SERVING_WORKDIR}/build-server-${TYPE}/core/general-server/serving
    cd bert # pwd: /Serving/python/examples/bert
    case $TYPE in
        CPU)
            pip install paddlehub
            # Because download from paddlehub may timeout,
            # download the model from bos(max_seq_len=128).
            wget https://paddle-serving.bj.bcebos.com/paddle_hub_models/text/SemanticModel/bert_chinese_L-12_H-768_A-12.tar.gz
            tar -xzf bert_chinese_L-12_H-768_A-12.tar.gz
            sh get_data.sh
            check_cmd "python -m paddle_serving_server.serve --model bert_chinese_L-12_H-768_A-12_model --port 9292 &"
            sleep 5
            pip install paddle_serving_app
            check_cmd "head -n 10 data-c.txt | python bert_client.py --model bert_chinese_L-12_H-768_A-12_client/serving_client_conf.prototxt"
            kill_server_process
            echo "bert RPC inference pass"
            ;;
        GPU)
            export CUDA_VISIBLE_DEVICES=0
            pip install paddlehub
            # Because download from paddlehub may timeout,
            # download the model from bos(max_seq_len=128).
            wget https://paddle-serving.bj.bcebos.com/paddle_hub_models/text/SemanticModel/bert_chinese_L-12_H-768_A-12.tar.gz
            tar -xzf bert_chinese_L-12_H-768_A-12.tar.gz
            sh get_data.sh
            check_cmd "python -m paddle_serving_server_gpu.serve --model bert_chinese_L-12_H-768_A-12_model --port 9292 --gpu_ids 0 &"
            sleep 5
            pip install paddle_serving_app
            check_cmd "head -n 10 data-c.txt | python bert_client.py --model bert_chinese_L-12_H-768_A-12_client/serving_client_conf.prototxt"
            kill_server_process
            echo "bert RPC inference pass"
            ;;
        *)
            echo "error type"
            exit 1
            ;;
    esac
    echo "test bert $TYPE finished as expected."
    unset SERVING_BIN
    cd ..
}

function python_test_imdb() {
    # pwd: /Serving/python/examples
    local TYPE=$1
    export SERVING_BIN=${SERVING_WORKDIR}/build-server-${TYPE}/core/general-server/serving
    cd imdb # pwd: /Serving/python/examples/imdb
    case $TYPE in
        CPU)
            sh get_data.sh
            check_cmd "python -m paddle_serving_server.serve --model imdb_cnn_model/ --port 9292 &"
            sleep 5
            check_cmd "head test_data/part-0 | python test_client.py imdb_cnn_client_conf/serving_client_conf.prototxt imdb.vocab"
            # test batch predict
            check_cmd "python benchmark_batch.py --thread 4 --batch_size 8 --model imdb_bow_client_conf/serving_client_conf.prototxt --request rpc --endpoint 127.0.0.1:9292"
            echo "imdb CPU RPC inference pass"
            kill_server_process
            rm -rf work_dir1
            sleep 5

            unsetproxy # maybe the proxy is used on iPipe, which makes web-test failed.
            check_cmd "python text_classify_service.py imdb_cnn_model/ workdir/ 9292 imdb.vocab &"
            sleep 5
            check_cmd "curl -H \"Content-Type:application/json\" -X POST -d '{\"feed\":[{\"words\": \"i am very sad | 0\"}], \"fetch\":[\"prediction\"]}' http://127.0.0.1:9292/imdb/prediction"
            http_code=`curl -H "Content-Type:application/json" -X POST -d '{"feed":[{"words": "i am very sad | 0"}], "fetch":["prediction"]}' -s -w "%{http_code}" -o /dev/null http://127.0.0.1:9292/imdb/prediction`
            if [ ${http_code} -ne 200 ]; then
                echo "HTTP status code -ne 200"
                exit 1
            fi
            # test batch predict
            check_cmd "python benchmark_batch.py --thread 4 --batch_size 8 --model imdb_bow_client_conf/serving_client_conf.prototxt --request http --endpoint 127.0.0.1:9292"
            setproxy # recover proxy state
            kill_server_process
            ps -ef | grep "text_classify_service.py" | grep -v grep | awk '{print $2}' | xargs kill
            echo "imdb CPU HTTP inference pass"
            ;;
        GPU)
            echo "imdb ignore GPU test"
            ;;
        *)
            echo "error type"
            exit 1
            ;;
    esac
    echo "test imdb $TYPE finished as expected."
    unset SERVING_BIN
    cd ..
}

function python_test_lac() {
    # pwd: /Serving/python/examples
    local TYPE=$1
    export SERVING_BIN=${SERVING_WORKDIR}/build-server-${TYPE}/core/general-server/serving
    cd lac # pwd: /Serving/python/examples/lac
    case $TYPE in
        CPU)
            sh get_data.sh
            check_cmd "python -m paddle_serving_server.serve --model jieba_server_model/ --port 9292 &"
            sleep 5
            check_cmd "echo \"我爱北京天安门\" | python lac_client.py jieba_client_conf/serving_client_conf.prototxt lac_dict/"
            echo "lac CPU RPC inference pass"
            kill_server_process

            unsetproxy # maybe the proxy is used on iPipe, which makes web-test failed.
            check_cmd "python lac_web_service.py jieba_server_model/ lac_workdir 9292 &"
            sleep 5
            check_cmd "curl -H \"Content-Type:application/json\" -X POST -d '{\"feed\":[{\"words\": \"我爱北京天安门\"}], \"fetch\":[\"word_seg\"]}' http://127.0.0.1:9292/lac/prediction"
            # check http code
            http_code=`curl -H "Content-Type:application/json" -X POST -d '{"feed":[{"words": "我爱北京天安门"}], "fetch":["word_seg"]}' -s -w "%{http_code}" -o /dev/null http://127.0.0.1:9292/lac/prediction`
            if [ ${http_code} -ne 200 ]; then
                echo "HTTP status code -ne 200"
                exit 1
            fi
            # http batch
            check_cmd "curl -H \"Content-Type:application/json\" -X POST -d '{\"feed\":[{\"words\": \"我爱北京天安门\"}, {\"words\": \"我爱北京天安门\"}], \"fetch\":[\"word_seg\"]}' http://127.0.0.1:9292/lac/prediction"
            # check http code
            http_code=`curl -H "Content-Type:application/json" -X POST -d '{"feed":[{"words": "我爱北京天安门"}, {"words": "我爱北京天安门"}], "fetch":["word_seg"]}' -s -w "%{http_code}" -o /dev/null http://127.0.0.1:9292/lac/prediction`
            if [ ${http_code} -ne 200 ]; then
                echo "HTTP status code -ne 200"
                exit 1
            fi
            setproxy # recover proxy state
            kill_server_process
            ps -ef | grep "lac_web_service" | grep -v grep | awk '{print $2}' | xargs kill
            echo "lac CPU HTTP inference pass"
            ;;
        GPU)
            echo "lac ignore GPU test"
            ;;
        *)
            echo "error type"
            exit 1
            ;;
    esac
    echo "test lac $TYPE finished as expected."
    unset SERVING_BIN
    cd ..
}

function python_run_test() {
    # Using the compiled binary
    local TYPE=$1 # pwd: /Serving
    cd python/examples # pwd: /Serving/python/examples
    python_test_fit_a_line $TYPE # pwd: /Serving/python/examples
    python_run_criteo_ctr_with_cube $TYPE # pwd: /Serving/python/examples
    python_test_bert $TYPE # pwd: /Serving/python/examples
    python_test_imdb $TYPE # pwd: /Serving/python/examples
    python_test_lac $TYPE
    echo "test python $TYPE part finished as expected."
    cd ../.. # pwd: /Serving
}

function monitor_test() {
    local TYPE=$1 # pwd: /Serving
    mkdir _monitor_test && cd _monitor_test # pwd: /Serving/_monitor_test
    case $TYPE in
        CPU):
            pip install pyftpdlib
            mkdir remote_path
            mkdir local_path
            cd remote_path # pwd: /Serving/_monitor_test/remote_path
            check_cmd "python -m pyftpdlib -p 8000 &>/dev/null &"
            cd .. # pwd: /Serving/_monitor_test

            # type: ftp
            # remote_path: /
            # remote_model_name: uci_housing.tar.gz
            # local_tmp_path: ___tmp
            # local_path: local_path
            cd remote_path # pwd: /Serving/_monitor_test/remote_path
            wget --no-check-certificate https://paddle-serving.bj.bcebos.com/uci_housing.tar.gz
            touch donefile
            cd ..  # pwd: /Serving/_monitor_test
            mkdir -p local_path/uci_housing_model
            python -m paddle_serving_server.monitor \
                    --type='ftp' --ftp_host='127.0.0.1' --ftp_port='8000' \
                    --remote_path='/' --remote_model_name='uci_housing.tar.gz' \
                    --remote_donefile_name='donefile' --local_path='local_path' \
                    --local_model_name='uci_housing_model' --local_timestamp_file='fluid_time_file' \
                    --local_tmp_path='___tmp' --unpacked_filename='uci_housing_model' \
                    --interval='1' >/dev/null &
            sleep 10
            if [ ! -f "local_path/uci_housing_model/fluid_time_file" ]; then
                echo "local_path/uci_housing_model/fluid_time_file not exist."
                exit 1
            fi
            ps -ef | grep "monitor" | grep -v grep | awk '{print $2}' | xargs kill
            rm -rf remote_path/*
            rm -rf local_path/*

            # type: ftp
            # remote_path: /tmp_dir
            # remote_model_name: uci_housing_model
            # local_tmp_path: ___tmp
            # local_path: local_path
            mkdir -p remote_path/tmp_dir && cd remote_path/tmp_dir # pwd: /Serving/_monitor_test/remote_path/tmp_dir
            wget --no-check-certificate https://paddle-serving.bj.bcebos.com/uci_housing.tar.gz
            tar -xzf uci_housing.tar.gz
            touch donefile
            cd ../.. # pwd: /Serving/_monitor_test
            mkdir -p local_path/uci_housing_model
            python -m paddle_serving_server.monitor \
                    --type='ftp' --ftp_host='127.0.0.1' --ftp_port='8000' \
                    --remote_path='/tmp_dir' --remote_model_name='uci_housing_model' \
                    --remote_donefile_name='donefile' --local_path='local_path' \
                    --local_model_name='uci_housing_model' --local_timestamp_file='fluid_time_file' \
                    --local_tmp_path='___tmp' --interval='1' >/dev/null &
            sleep 10
            if [ ! -f "local_path/uci_housing_model/fluid_time_file" ]; then
                echo "local_path/uci_housing_model/fluid_time_file not exist."
                exit 1
            fi
            ps -ef | grep "monitor" | grep -v grep | awk '{print $2}' | xargs kill
            rm -rf remote_path/*
            rm -rf local_path/*

            # type: general
            # remote_path: /
            # remote_model_name: uci_housing.tar.gz
            # local_tmp_path: ___tmp
            # local_path: local_path
            cd remote_path # pwd: /Serving/_monitor_test/remote_path
            wget --no-check-certificate https://paddle-serving.bj.bcebos.com/uci_housing.tar.gz
            touch donefile
            cd ..  # pwd: /Serving/_monitor_test
            mkdir -p local_path/uci_housing_model
            python -m paddle_serving_server.monitor \
                    --type='general' --general_host='ftp://127.0.0.1:8000' \
                    --remote_path='/' --remote_model_name='uci_housing.tar.gz' \
                    --remote_donefile_name='donefile' --local_path='local_path' \
                    --local_model_name='uci_housing_model' --local_timestamp_file='fluid_time_file' \
                    --local_tmp_path='___tmp' --unpacked_filename='uci_housing_model' \
                    --interval='1' >/dev/null &
            sleep 10
            if [ ! -f "local_path/uci_housing_model/fluid_time_file" ]; then
                echo "local_path/uci_housing_model/fluid_time_file not exist."
                exit 1
            fi
            ps -ef | grep "monitor" | grep -v grep | awk '{print $2}' | xargs kill
            rm -rf remote_path/*
            rm -rf local_path/*

            # type: general
            # remote_path: /tmp_dir
            # remote_model_name: uci_housing_model
            # local_tmp_path: ___tmp
            # local_path: local_path
            mkdir -p remote_path/tmp_dir && cd remote_path/tmp_dir # pwd: /Serving/_monitor_test/remote_path/tmp_dir
            wget --no-check-certificate https://paddle-serving.bj.bcebos.com/uci_housing.tar.gz
            tar -xzf uci_housing.tar.gz
            touch donefile
            cd ../.. # pwd: /Serving/_monitor_test
            mkdir -p local_path/uci_housing_model
            python -m paddle_serving_server.monitor \
                    --type='general' --general_host='ftp://127.0.0.1:8000' \
                    --remote_path='/tmp_dir' --remote_model_name='uci_housing_model' \
                    --remote_donefile_name='donefile' --local_path='local_path' \
                    --local_model_name='uci_housing_model' --local_timestamp_file='fluid_time_file' \
                    --local_tmp_path='___tmp' --interval='1' >/dev/null &
            sleep 10
            if [ ! -f "local_path/uci_housing_model/fluid_time_file" ]; then
                echo "local_path/uci_housing_model/fluid_time_file not exist."
                exit 1
            fi
            ps -ef | grep "monitor" | grep -v grep | awk '{print $2}' | xargs kill
            rm -rf remote_path/*
            rm -rf local_path/*

            ps -ef | grep "pyftpdlib" | grep -v grep | awk '{print $2}' | xargs kill
            ;;
        GPU):
            pip install pyftpdlib
            mkdir remote_path
            mkdir local_path
            cd remote_path # pwd: /Serving/_monitor_test/remote_path
            check_cmd "python -m pyftpdlib -p 8000 &>/dev/null &"
            cd .. # pwd: /Serving/_monitor_test

            # type: ftp
            # remote_path: /
            # remote_model_name: uci_housing.tar.gz
            # local_tmp_path: ___tmp
            # local_path: local_path
            cd remote_path # pwd: /Serving/_monitor_test/remote_path
            wget --no-check-certificate https://paddle-serving.bj.bcebos.com/uci_housing.tar.gz
            touch donefile
            cd ..  # pwd: /Serving/_monitor_test
            mkdir -p local_path/uci_housing_model
            python -m paddle_serving_server_gpu.monitor \
                    --type='ftp' --ftp_host='127.0.0.1' --ftp_port='8000' \
                    --remote_path='/' --remote_model_name='uci_housing.tar.gz' \
                    --remote_donefile_name='donefile' --local_path='local_path' \
                    --local_model_name='uci_housing_model' --local_timestamp_file='fluid_time_file' \
                    --local_tmp_path='___tmp' --unpacked_filename='uci_housing_model' \
                    --interval='1' >/dev/null &
            sleep 10
            if [ ! -f "local_path/uci_housing_model/fluid_time_file" ]; then
                echo "local_path/uci_housing_model/fluid_time_file not exist."
                exit 1
            fi
            ps -ef | grep "monitor" | grep -v grep | awk '{print $2}' | xargs kill
            rm -rf remote_path/*
            rm -rf local_path/*

            # type: ftp
            # remote_path: /tmp_dir
            # remote_model_name: uci_housing_model
            # local_tmp_path: ___tmp
            # local_path: local_path
            mkdir -p remote_path/tmp_dir && cd remote_path/tmp_dir # pwd: /Serving/_monitor_test/remote_path/tmp_dir
            wget --no-check-certificate https://paddle-serving.bj.bcebos.com/uci_housing.tar.gz
            tar -xzf uci_housing.tar.gz
            touch donefile
            cd ../.. # pwd: /Serving/_monitor_test
            mkdir -p local_path/uci_housing_model
            python -m paddle_serving_server_gpu.monitor \
                    --type='ftp' --ftp_host='127.0.0.1' --ftp_port='8000' \
                    --remote_path='/tmp_dir' --remote_model_name='uci_housing_model' \
                    --remote_donefile_name='donefile' --local_path='local_path' \
                    --local_model_name='uci_housing_model' --local_timestamp_file='fluid_time_file' \
                    --local_tmp_path='___tmp' --interval='1' >/dev/null &
            sleep 10
            if [ ! -f "local_path/uci_housing_model/fluid_time_file" ]; then
                echo "local_path/uci_housing_model/fluid_time_file not exist."
                exit 1
            fi
            ps -ef | grep "monitor" | grep -v grep | awk '{print $2}' | xargs kill
            rm -rf remote_path/*
            rm -rf local_path/*

            # type: general
            # remote_path: /
            # remote_model_name: uci_housing.tar.gz
            # local_tmp_path: ___tmp
            # local_path: local_path
            cd remote_path # pwd: /Serving/_monitor_test/remote_path
            wget --no-check-certificate https://paddle-serving.bj.bcebos.com/uci_housing.tar.gz
            touch donefile
            cd ..  # pwd: /Serving/_monitor_test
            mkdir -p local_path/uci_housing_model
            python -m paddle_serving_server_gpu.monitor \
                    --type='general' --general_host='ftp://127.0.0.1:8000' \
                    --remote_path='/' --remote_model_name='uci_housing.tar.gz' \
                    --remote_donefile_name='donefile' --local_path='local_path' \
                    --local_model_name='uci_housing_model' --local_timestamp_file='fluid_time_file' \
                    --local_tmp_path='___tmp' --unpacked_filename='uci_housing_model' \
                    --interval='1' >/dev/null &
            sleep 10
            if [ ! -f "local_path/uci_housing_model/fluid_time_file" ]; then
                echo "local_path/uci_housing_model/fluid_time_file not exist."
                exit 1
            fi
            ps -ef | grep "monitor" | grep -v grep | awk '{print $2}' | xargs kill
            rm -rf remote_path/*
            rm -rf local_path/*

            # type: general
            # remote_path: /tmp_dir
            # remote_model_name: uci_housing_model
            # local_tmp_path: ___tmp
            # local_path: local_path
            mkdir -p remote_path/tmp_dir && cd remote_path/tmp_dir # pwd: /Serving/_monitor_test/remote_path/tmp_dir
            wget --no-check-certificate https://paddle-serving.bj.bcebos.com/uci_housing.tar.gz
            tar -xzf uci_housing.tar.gz
            touch donefile
            cd ../.. # pwd: /Serving/_monitor_test
            mkdir -p local_path/uci_housing_model
            python -m paddle_serving_server_gpu.monitor \
                    --type='general' --general_host='ftp://127.0.0.1:8000' \
                    --remote_path='/tmp_dir' --remote_model_name='uci_housing_model' \
                    --remote_donefile_name='donefile' --local_path='local_path' \
                    --local_model_name='uci_housing_model' --local_timestamp_file='fluid_time_file' \
                    --local_tmp_path='___tmp' --interval='1' >/dev/null &
            sleep 10
            if [ ! -f "local_path/uci_housing_model/fluid_time_file" ]; then
                echo "local_path/uci_housing_model/fluid_time_file not exist."
                exit 1
            fi
            ps -ef | grep "monitor" | grep -v grep | awk '{print $2}' | xargs kill
            rm -rf remote_path/*
            rm -rf local_path/*

            ps -ef | grep "pyftpdlib" | grep -v grep | awk '{print $2}' | xargs kill
            ;;
        *)
            echo "error type"
            exit 1
            ;;
    esac
    cd .. # pwd: /Serving
    rm -rf _monitor_test
    echo "test monitor $TYPE finished as expected."
}

function main() {
    local TYPE=$1 # pwd: /
    init # pwd: /Serving
    build_client $TYPE # pwd: /Serving
    build_server $TYPE # pwd: /Serving
    build_app $TYPE # pwd: /Serving
    python_run_test $TYPE # pwd: /Serving
    monitor_test $TYPE # pwd: /Serving
    echo "serving $TYPE part finished as expected."
}

main $@
