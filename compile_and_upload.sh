set -e
set -v

version=0.0.0
app_version=0.0.0
cd ./python
python change_version.py $version
cd ..

alias ld=/root/env/bin/ld
export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/usr/local/python3.7/lib

PYTHONROOT=/usr/local/python2.7
PYTHON_INCLUDE_DIR_2=$PYTHONROOT/include/python2.7/
PYTHON_LIBRARY_2=$PYTHONROOT/lib/libpython2.7.so
PYTHON_EXECUTABLE_2=$PYTHONROOT/bin/python2.7

PYTHONROOT3=/usr/local/python3.6
PYTHON_INCLUDE_DIR_3=$PYTHONROOT3/include/python3.6m/
PYTHON_LIBRARY_3=$PYTHONROOT3/lib/libpython3.6m.so
PYTHON_EXECUTABLE_3=$PYTHONROOT3/bin/python3.6m

function change_py_version(){
py3_version=$1
case $py3_version in
35)
PYTHONROOT3=/usr/local/
PYTHON_INCLUDE_DIR_3=$PYTHONROOT3/include/python3.5m
PYTHON_LIBRARY_3=$PYTHONROOT3/lib/libpython3.5m.so
PYTHON_EXECUTABLE_3=$PYTHONROOT3/bin/python3.5m
;;
36)
PYTHONROOT3=/usr/local/python3.6
PYTHON_INCLUDE_DIR_3=$PYTHONROOT3/include/python3.6m/
PYTHON_LIBRARY_3=$PYTHONROOT3/lib/libpython3.6m.so
PYTHON_EXECUTABLE_3=$PYTHONROOT3/bin/python3.6m
;;
37)
PYTHONROOT3=/usr/local/python3.7
PYTHON_INCLUDE_DIR_3=$PYTHONROOT3/include/python3.7m/
PYTHON_LIBRARY_3=$PYTHONROOT3/lib/libpython3.7m.so
PYTHON_EXECUTABLE_3=$PYTHONROOT3/bin/python3.7m
;;
esac
}
#git fetch upstream
#git merge upstream/develop

git submodule init
git submodule update

function cp_lib(){
cp /usr/lib64/libcrypto.so.10 $1
cp /usr/lib64/libssl.so.10 $1
}

function pack(){
mkdir -p bin_package
cd bin_package
WITHAVX=$1
WITHMKL=$2
if [ $WITHAVX = "ON" -a $WITHMKL = "OFF" ]; then
    mkdir -p serving-cpu-avx-openblas-$version
    cp ../build_server/output/demo/serving/bin/serving  serving-cpu-avx-openblas-$version
    cp_lib serving-cpu-avx-openblas-$version
    tar -czvf serving-cpu-avx-openblas-$version.tar.gz serving-cpu-avx-openblas-$version/
fi
if [ $WITHAVX = "OFF" -a $WITHMKL = "OFF" ]; then
    mkdir -p serving-cpu-noavx-openblas-$version
    cp ../build_server/output/demo/serving/bin/serving serving-cpu-noavx-openblas-$version
    cp_lib serving-cpu-noavx-openblas-$version
    tar -czvf serving-cpu-noavx-openblas-$version.tar.gz serving-cpu-noavx-openblas-$version/
fi
if [ $WITHAVX = "ON" -a $WITHMKL = "ON" ]; then
    mkdir -p serving-cpu-avx-mkl-$version
    cp ../build_server/output/demo/serving/bin/* serving-cpu-avx-mkl-$version
    cp ../build_server/third_party/install/Paddle//third_party/install/mkldnn/lib/libdnnl.so.1 serving-cpu-avx-mkl-$version
    cp_lib serving-cpu-avx-mkl-$version
    tar -czvf serving-cpu-avx-mkl-$version.tar.gz serving-cpu-avx-mkl-$version/
fi
cd ..
}

function pack_gpu(){
mkdir -p bin_package
cd bin_package
CUDA_version=$1
mkdir -p serving-gpu-$CUDA_version-$version
cp ../build_gpu_server_$CUDA_version/output/demo/serving/bin/* serving-gpu-$CUDA_version-$version
cp ../build_gpu_server_$CUDA_version/third_party/install/Paddle//third_party/install/mklml/lib/* serving-gpu-$CUDA_version-$version
cp ../build_gpu_server_$CUDA_version/third_party/install/Paddle//third_party/install/mkldnn/lib/libdnnl.so.1 serving-gpu-$CUDA_version-$version
cp_lib serving-gpu-$CUDA_version-$version
tar -czvf serving-gpu-$CUDA_version-$version.tar.gz serving-gpu-$CUDA_version-$version/
cd ..
}

function cp_whl(){
cd ..
mkdir -p whl_package
cd -
cp ./python/dist/paddle_serving_*-$version* ../whl_package \
|| cp ./python/dist/paddle_serving_app*-$app_version* ../whl_package
}

function clean_whl(){
if [ -d "python" ];then
rm -r python
fi
}

function compile_cpu(){
mkdir -p build_server
cd build_server
clean_whl
WITHAVX=$1
WITHMKL=$2
cmake -DPYTHON_INCLUDE_DIR=$PYTHON_INCLUDE_DIR_2 \
      -DPYTHON_LIBRARY=$PYTHON_LIBRARY_2 \
      -DPYTHON_EXECUTABLE=$PYTHON_EXECUTABLE_2 \
      -DWITH_AVX=$WITHAVX \
      -DWITH_MKL=$WITHMKL \
      -DSERVER=ON .. > compile_log
make -j10 >> compile_log
make install >> compile_log
cp_whl
cd ..
pack $WITHAVX $WITHMKL
}

function compile_cpu_py3(){
mkdir -p build_server_py3
cd build_server_py3
clean_whl
WITHAVX=$1
WITHMKL=$2
cmake -DPYTHON_INCLUDE_DIR=$PYTHON_INCLUDE_DIR_3 \
      -DPYTHON_LIBRARY=$PYTHON_LIBRARY_3 \
      -DPYTHON_EXECUTABLE=$PYTHON_EXECUTABLE_3 \
      -DWITH_AVX=$WITHAVX \
      -DWITH_MKL=$WITHMKL \
      -DSERVER=ON .. > compile_log
make -j10 >> compile_log
make install >> compile_log
cp_whl
cd ..
#pack $WITHAVX $WITHMKL
}

function compile_gpu_cuda9(){
mkdir -p build_gpu_server_cuda9
cd build_gpu_server_cuda9
clean_whl
cmake -DPYTHON_INCLUDE_DIR=$PYTHON_INCLUDE_DIR_2 \
    -DPYTHON_LIBRARY=$PYTHON_LIBRARY_2 \
    -DPYTHON_EXECUTABLE=$PYTHON_EXECUTABLE_2 \
    -DCUDNN_LIBRARY=/root/cudnn/cuda9.0/cudnn-7.3.1/lib64 \
    -DWITH_GPU=ON \
    -DSERVER=ON .. > compile_log
make -j10 >> compile_log
make install >> compile_log
cp_whl
cd ..
pack_gpu cuda9
}

function compile_gpu_cuda93(){
mkdir -p build_gpu_server_cuda93
cd build_gpu_server_cuda93
clean_whl
cmake -DPYTHON_INCLUDE_DIR=$PYTHON_INCLUDE_DIR_3 \
    -DPYTHON_LIBRARY=$PYTHON_LIBRARY_3 \
    -DPYTHON_EXECUTABLE=$PYTHON_EXECUTABLE_3 \
    -DCUDNN_LIBRARY=/root/cudnn/cuda9.0/cudnn-7.3.1/lib64 \
    -DWITH_GPU=ON \
    -DSERVER=ON .. > compile_log
make -j10 >> compile_log
make install >> compile_log
cp_whl
cd ..
#pack_gpu
}

function compile_gpu_cuda10(){
mkdir -p build_gpu_server_cuda10
cd build_gpu_server_cuda10
clean_whl
cmake -DPYTHON_INCLUDE_DIR=$PYTHON_INCLUDE_DIR_2 \
    -DPYTHON_LIBRARY=$PYTHON_LIBRARY_2 \
    -DPYTHON_EXECUTABLE=$PYTHON_EXECUTABLE_2 \
    -DWITH_GPU=ON \
    -DCUDA_TOOLKIT_ROOT_DIR=/root/cuda-10.0 \
    -DCUDNN_LIBRARY=/root/cudnn/cuda10.0/cudnn-7.5.1/lib64/ \
    -DSERVER=ON .. > compile_log
make -j10 >> compile_log
make install >> compile_log
cp_whl
cd ..
pack_gpu cuda10
}

function compile_gpu_cuda103(){
mkdir -p build_gpu_server_cuda103
cd build_gpu_server_cuda103
clean_whl
cmake -DPYTHON_INCLUDE_DIR=$PYTHON_INCLUDE_DIR_2 \
    -DPYTHON_LIBRARY=$PYTHON_LIBRARY_3 \
    -DPYTHON_EXECUTABLE=$PYTHON_EXECUTABLE_3 \
    -DWITH_GPU=ON \
    -DCUDA_TOOLKIT_ROOT_DIR=/root/cuda-10.0 \
    -DCUDNN_LIBRARY=/root/cudnn/cuda10.0/cudnn-7.5.1/lib64/ \
    -DSERVER=ON .. > compile_log
make -j10 >> compile_log
make install >> compile_log
cp_whl
cd ..
pack_gpu cuda10
}

function compile_trt(){
mkdir -p build_trt_server
cd build_trt_server
clean_whl
cmake -DPYTHON_INCLUDE_DIR=$PYTHON_INCLUDE_DIR_2 -DPYTHON_LIBRARY=$PYTHON_LIBRARY_2 -DPYTHON_EXECUTABLE=$PYTHON_EXECUTABLE_2 -DWITH_GPU=ON -DSERVER=ON -DCUDNN_ROOT=/root/cuda-10.1/lib64 .. > compile_log
make -j10 >> compile_log
make install >> compile_log
#cp_whl
cd ..
#pack_gpu
}

function compile_client(){
mkdir -p build_client
cd build_client
clean_whl
cmake -DPYTHON_INCLUDE_DIR=$PYTHON_INCLUDE_DIR_2  -DPYTHON_LIBRARY=$PYTHON_LIBRARY_2 -DPYTHON_EXECUTABLE=$PYTHON_EXECUTABLE_2 -DCLIENT=ON -DPACK=ON .. > compile_log
make -j10 >> compile_log
#make install >> compile_log
cp_whl
cd ..
}

function compile_client_py3(){
mkdir -p build_client_py3
cd build_client_py3
clean_whl
cmake -DPYTHON_INCLUDE_DIR=$PYTHON_INCLUDE_DIR_3 -DPYTHON_LIBRARY=$PYTHON_LIBRARY_3 -DPYTHON_EXECUTABLE=$PYTHON_EXECUTABLE_3 -DCLIENT=ON -DPACK=ON .. > compile_log
make -j10 >> compile_log
#make install >> compile_log
cp_whl
cd ..
}

function compile_app(){
mkdir -p build_app
cd build_app
clean_whl
cmake -DPYTHON_INCLUDE_DIR=$PYTHON_INCLUDE_DIR_2  -DPYTHON_LIBRARY=$PYTHON_LIBRARY_2 -DPYTHON_EXECUTABLE=$PYTHON_EXECUTABLE_2 -DAPP=ON .. > compile_log
make -j10 >> compile_log
#make install >> compile_log
cp_whl
cd ..
}

function compile_app_py3(){
mkdir -p build_app_py3
cd build_app_py3
clean_whl
cmake -DPYTHON_INCLUDE_DIR=$PYTHON_INCLUDE_DIR_3 -DPYTHON_LIBRARY=$PYTHON_LIBRARY_3 -DPYTHON_EXECUTABLE=$PYTHON_EXECUTABLE_3 -DAPP=ON ..> compile_log
make -j10 >> compile_log
#make install >> compile_log
cp_whl
cd ..
}

function upload_bin(){
    cd bin_package
    python ../bos_conf/upload.py serving-cpu-avx-openblas-$version.tar.gz
    python ../bos_conf/upload.py serving-cpu-avx-mkl-$version.tar.gz
    python ../bos_conf/upload.py serving-cpu-noavx-openblas-$version.tar.gz
    python ../bos_conf/upload.py serving-gpu-cuda10-$version.tar.gz
    python ../bos_conf/upload.py serving-gpu-cuda9-$version.tar.gz
    cd ..
}

function upload_whl(){
    cd whl_package
    python ../bos_conf/upload_whl.py paddle_serving_client-$version-cp27-*
    python ../bos_conf/upload_whl.py paddle_serving_client-$version-cp36-*
    python ../bos_conf/upload_whl.py paddle_serving_client-$version-cp37-*
    python ../bos_conf/upload_whl.py paddle_serving_server-$version-py2-none-any.whl
    python ../bos_conf/upload_whl.py paddle_serving_server-$version-py3-none-any.whl
    python ../bos_conf/upload_whl.py paddle_serving_server_gpu-$version.post9-py2-none-any.whl
    python ../bos_conf/upload_whl.py paddle_serving_server_gpu-$version.post9-py3-none-any.whl
    python ../bos_conf/upload_whl.py paddle_serving_server_gpu-$version.post10-py2-none-any.whl
    python ../bos_conf/upload_whl.py paddle_serving_server_gpu-$version.post10-py3-none-any.whl
    python ../bos_conf/upload_whl.py paddle_serving_app-$app_version-py2-none-any.whl
    python ../bos_conf/upload_whl.py paddle_serving_app-$app_version-py3-none-any.whl
    cd ..
}

function compile(){
    #cpu-avx-openblas $1-avx  $2-mkl
    #compile_cpu ON OFF
    #compile_cpu_py3 ON OFF

    #cpu-avx-mkl
    #compile_cpu ON ON

    #cpu-noavx-openblas
    #compile_cpu OFF OFF

    #gpu
    #compile_gpu_cuda9
    #compile_gpu_cuda10
    #compile_gpu_cuda93
    #compile_gpu_cuda103
    #compile_trt

    #client
    #compile_client
    change_py_version 35 && compile_client_py3
    #change_py_version 36 && compile_client_py3
    #change_py_version 37 && compile_client_py3

    #app
    #compile_app
    #change_py_version 36 && compile_app_py3
}

#compile
compile

#upload bin
#upload_bin

#upload whl
#upload_whl
