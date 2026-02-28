<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use Illuminate\Http\Request;
use App\Models\Pottery;
use Illuminate\Http\JsonResponse;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Storage;

class PotteryController extends Controller
{
    public function index(): JsonResponse
    {
        return response()->json(Pottery::latest()->get());
    }

    public function upload(Request $request)
    {
        $request->validate([
            'image' => 'required|image',
            'model' => 'nullable|string|in:gemini,gemini3,gemini_lite,llama4',
        ]);

        $path = $request->file('image')->store('potteries', 'public');

        $fullPath = storage_path('app/public/' . $path);

        $model = $request->input('model', 'gemini');

        $response = Http::timeout(60)->attach(
            'file',
            file_get_contents($fullPath),
            basename($fullPath)
        )->post('http://127.0.0.1:8001/predict?model=' . urlencode($model));

        if (!$response->successful()) {
            Storage::disk('public')->delete($path);
            return response()->json([
                'message' => 'AI model error: ' . ($response->json('detail') ?? $response->body()),
            ], 502);
        }

        $result = $response->json();

        if (($result['predicted_label'] ?? null) === 'not_pottery') {
            Storage::disk('public')->delete($path);
            return response()->json([
                'message' => 'Image is not pottery',
                'data'    => [
                    'predicted_label' => 'not_pottery',
                    'confidence'      => 0,
                    'ai_model'        => $model,
                    'raw_answer'      => $result['raw_text'] ?? null,
                ]
            ]);
        }

        $pottery = Pottery::create([
            'image_path'      => $path,
            'predicted_label' => $result['predicted_label'] ?? null,
            'confidence'      => $result['confidence'] ?? null,
            'ai_model'        => $model,
            'raw_answer'      => $result['raw_text'] ?? null,
        ]);

        return response()->json([
            'message' => 'Upload and prediction successful',
            'data'    => $pottery
        ]);
    }

    public function destroy(Pottery $pottery): JsonResponse
    {
        if ($pottery->image_path) {
            Storage::disk('public')->delete($pottery->image_path);
        }
        $pottery->delete();
        return response()->json(['message' => 'Deleted successfully']);
    }
}
