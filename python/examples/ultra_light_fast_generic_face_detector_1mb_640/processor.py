# coding=utf-8
from __future__ import absolute_import
from __future__ import division
from __future__ import print_function

import os
import time

import base64
import cv2
import numpy as np

__all__ = ['postprocess']


def base64_to_cv2(b64str):
    data = base64.b64decode(b64str.encode('utf8'))
    data = np.fromstring(data, np.uint8)
    data = cv2.imdecode(data, cv2.IMREAD_COLOR)
    return data


def area_of(left_top, right_bottom):
    hw = np.clip(right_bottom - left_top, 0.0, None)
    return hw[..., 0] * hw[..., 1]


def iou_of(boxes0, boxes1, eps=1e-5):
    overlap_left_top = np.maximum(boxes0[..., :2], boxes1[..., :2])
    overlap_right_bottom = np.minimum(boxes0[..., 2:], boxes1[..., 2:])
    overlap_area = area_of(overlap_left_top, overlap_right_bottom)
    area0 = area_of(boxes0[..., :2], boxes0[..., 2:])
    area1 = area_of(boxes1[..., :2], boxes1[..., 2:])
    return overlap_area / (area0 + area1 - overlap_area + eps)


def hard_nms(box_scores, iou_threshold, top_k=-1, candidate_size=200):
    scores = box_scores[:, -1]
    boxes = box_scores[:, :-1]
    picked = []
    # _, indexes = scores.sort(descending=True)
    indexes = np.argsort(scores)
    # indexes = indexes[:candidate_size]
    indexes = indexes[-candidate_size:]
    while len(indexes) > 0:
        # current = indexes[0]
        current = indexes[-1]
        picked.append(current)
        if 0 < top_k == len(picked) or len(indexes) == 1:
            break
        current_box = boxes[current, :]
        # indexes = indexes[1:]
        indexes = indexes[:-1]
        rest_boxes = boxes[indexes, :]
        iou = iou_of(rest_boxes, np.expand_dims(current_box, axis=0))
        indexes = indexes[iou <= iou_threshold]
    return box_scores[picked, :]


def check_dir(dir_path):
    if not os.path.exists(dir_path):
        os.makedirs(dir_path)
    elif os.path.isfile(dir_path):
        os.remove(dir_path)
        os.makedirs(dir_path)


def get_image_ext(image):
    if image.shape[2] == 4:
        return ".png"
    return ".jpg"

def preprocess(im_path):
    orig_image = cv2.imread(im_path)
    image = cv2.cvtColor(orig_image, cv2.COLOR_BGR2RGB)
    image = cv2.resize(image, (640, 480))
    image_mean = np.array([127, 127, 127])
    image = (image - image_mean) / 128.0
    image = np.transpose(image, [2, 0, 1])
    image = np.array(image).astype('float32')
    return image

def postprocess(image_with_bbox,
		  output_dir='face_detector_640_predict_output',
                  visualization=True,
                  confs_threshold=0.5,
                  iou_threshold=0.5):

    confidences = image_with_bbox['save_infer_model/scale_0.tmp_0']
    boxes = image_with_bbox['save_infer_model/scale_1.tmp_0']
    orig_im_path=image_with_bbox['image']
    orig_im = cv2.imread(orig_im_path)
    orig_im_shape = orig_im.shape
    out = postprocess_2(
                    confidences=confidences[0],
                    boxes=boxes[0],
                    orig_im=orig_im,
                    orig_im_shape=orig_im_shape,
                    orig_im_path=orig_im_path,
                    output_dir=output_dir,
                    visualization=visualization,
                    confs_threshold=confs_threshold,
                    iou_threshold=iou_threshold)

def postprocess_2(confidences,
                boxes,
                orig_im,
                orig_im_shape,
                orig_im_path,
                output_dir,
                visualization,
                confs_threshold=0.5,
                iou_threshold=0.5):
    """
    Postprocess output of network. one image at a time.

    Args:
        confidences (numpy.ndarray): confidences, with shape [num, 2]
        boxes (numpy.ndaray): boxes coordinate,  with shape [num, 4]
        orig_im (numpy.ndarray): original image.
        orig_im_shape (list): shape pf original image.
        orig_im_path (list): path of riginal image.
        output_dir (str): output directory to store image.
        visualization (bool): whether to save image or not.
    """
    output = {}
    output['data'] = []
    if orig_im_path:
        output['path'] = orig_im_path
    picked_box_probs = []
    picked_labels = []
    for class_index in range(1, confidences.shape[1]):
        probs = confidences[:, class_index]
        mask = probs > confs_threshold
        probs = probs[mask]
        if probs.shape[0] == 0:
            continue
        subset_boxes = boxes[mask, :]
        box_probs = np.concatenate([subset_boxes, probs.reshape(-1, 1)], axis=1)
        box_probs = hard_nms(box_probs, iou_threshold=iou_threshold, top_k=-1)
        picked_box_probs.append(box_probs)
        picked_labels.extend([class_index] * box_probs.shape[0])

    if not picked_box_probs:
        return output

    picked_box_probs = np.concatenate(picked_box_probs)
    picked_box_probs[:, 0] *= orig_im_shape[1]
    picked_box_probs[:, 1] *= orig_im_shape[0]
    picked_box_probs[:, 2] *= orig_im_shape[1]
    picked_box_probs[:, 3] *= orig_im_shape[0]

    for data in picked_box_probs:
        output['data'].append({
            'left': float(data[0]),
            'right': float(data[2]),
            'top': float(data[1]),
            'bottom': float(data[3]),
            'confidence': float(data[4])
        })

    picked_box_probs = picked_box_probs[:, :4].astype(np.int32)
    if visualization:
        for i in range(picked_box_probs.shape[0]):
            box = picked_box_probs[i]
            cv2.rectangle(orig_im, (box[0], box[1]), (box[2], box[3]),
                          (255, 255, 0), 2)
        check_dir(output_dir)
        ext = os.path.splitext(orig_im_path) if orig_im_path else ''
        ext = ext if ext else get_image_ext(orig_im)
        orig_im_path = orig_im_path if orig_im_path else 'ndarray_{}{}'.format(
            time.time(), ext)
        im_name = os.path.basename(orig_im_path)
        im_save_path = os.path.join(output_dir, im_name)
        output['save_path'] = im_save_path
        cv2.imwrite(im_save_path, orig_im)
    return output
