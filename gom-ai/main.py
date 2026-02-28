from fastapi import FastAPI, File, UploadFile
from PIL import Image
import shutil
import os
import random

app = FastAPI()

UPLOAD_FOLDER = "uploads"
os.makedirs(UPLOAD_FOLDER, exist_ok=True)

@app.post("/predict")
async def predict(file: UploadFile = File(...)):
    
    file_path = os.path.join(UPLOAD_FOLDER, file.filename)
    
    with open(file_path, "wb") as buffer:
        shutil.copyfileobj(file.file, buffer)

    # Giả lập AI predict
    labels = ["Bat Trang", "Bau Truc", "Thanh Ha"]
    predicted_label = random.choice(labels)
    confidence = round(random.uniform(0.7, 0.99), 2)

    return {
        "predicted_label": predicted_label,
        "confidence": confidence
    }