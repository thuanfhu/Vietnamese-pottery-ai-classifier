import tensorflow as tf
import numpy as np
import joblib
import tkinter as tk
from tkinter import filedialog

from tensorflow.keras.applications.resnet50 import preprocess_input
from tensorflow.keras.preprocessing.image import load_img, img_to_array
from tensorflow.keras.applications import ResNet50

# ===== LOAD MODEL & LABEL =====
svm = joblib.load("gom_svm.pkl")
class_names = joblib.load("class_names.pkl")

# ===== LOAD RESNET LÀM FEATURE EXTRACTOR =====
base_model = ResNet50(weights="imagenet", include_top=False)
feature_model = tf.keras.Model(
    inputs=base_model.input,
    outputs=tf.keras.layers.GlobalAveragePooling2D()(base_model.output)
)

# ===== MỞ HỘP THOẠI CHỌN ẢNH =====
root = tk.Tk()
root.withdraw()
root.attributes('-topmost', True)

IMG_PATH = filedialog.askopenfilename(
    parent=root,
    title="Chọn ảnh gốm cần nhận diện",
    filetypes=[("Image files", "*.jpg *.jpeg *.png")]
)

root.destroy()

if not IMG_PATH:
    print(" Bạn chưa chọn ảnh!")
    exit()

print(f"\n Ảnh đã chọn: {IMG_PATH}\n")

# ===== TIỀN XỬ LÝ ẢNH =====
img = load_img(IMG_PATH, target_size=(224,224))
img_array = img_to_array(img)
img_array = np.expand_dims(img_array, axis=0)
img_array = preprocess_input(img_array)

# ===== TRÍCH ĐẶC TRƯNG =====
features = feature_model.predict(img_array)
features = features.reshape(1, -1)

# ===== DỰ ĐOÁN =====
pred = svm.predict(features)[0]
prob = svm.predict_proba(features)[0]

print("===== KẾT QUẢ NHẬN DIỆN =====")
print("Dòng gốm dự đoán:", class_names[pred])
print(f"Độ tin cậy: {max(prob)*100:.2f}%")
