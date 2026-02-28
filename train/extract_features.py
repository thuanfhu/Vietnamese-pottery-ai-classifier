import tensorflow as tf
import numpy as np
import os
from tensorflow.keras.applications import ResNet50
from tensorflow.keras.applications.resnet50 import preprocess_input
from tensorflow.keras.preprocessing.image import load_img, img_to_array
from sklearn.model_selection import train_test_split
from sklearn.svm import SVC
import joblib

DATASET_PATH = "dataset/train"
IMG_SIZE = (224, 224)

# ===== LOAD RESNET LÀM FEATURE EXTRACTOR =====
base_model = ResNet50(weights="imagenet", include_top=False)

feature_model = tf.keras.Model(
    inputs=base_model.input,
    outputs=tf.keras.layers.GlobalAveragePooling2D()(base_model.output)
)

# ===== LẤY TÊN LỚP =====
class_names = sorted(os.listdir(DATASET_PATH))
print("Classes:", class_names)

X = []
y = []

# ===== DUYỆT DATASET =====
for label, class_name in enumerate(class_names):
    class_path = os.path.join(DATASET_PATH, class_name)

    for img_name in os.listdir(class_path):
        img_path = os.path.join(class_path, img_name)

        img = load_img(img_path, target_size=IMG_SIZE)
        img_array = img_to_array(img)
        img_array = np.expand_dims(img_array, axis=0)
        img_array = preprocess_input(img_array)

        # TRÍCH FEATURE 2048 chiều
        features = feature_model.predict(img_array)
        X.append(features.flatten())
        y.append(label)

X = np.array(X)
y = np.array(y)

print("Feature shape:", X.shape)   # (số ảnh, 2048)

# ===== CHIA TRAIN/TEST =====
X_train, X_test, y_train, y_test = train_test_split(
    X, y, test_size=0.2, random_state=42, stratify=y
)

# ===== TRAIN SVM =====
svm = SVC(kernel="linear", probability=True)
svm.fit(X_train, y_train)

# ===== ĐÁNH GIÁ =====
acc = svm.score(X_test, y_test)
print(f"Accuracy SVM: {acc*100:.2f}%")

# ===== LƯU MODEL =====
joblib.dump(svm, "gom_svm.pkl")
joblib.dump(class_names, "class_names.pkl")

print("Đã lưu gom_svm.pkl và class_names.pkl")
