ultra_light_fast_generic_face_detector_1mb_640

Get Model
hub install ultra_light_fast_generic_face_detector_1mb_640==1.1.2

Start Service
python3 -m paddle_serving_server.serve --model face_detector_serving_server --port 9494


Client Prediction
python3 client.py test.jpg
