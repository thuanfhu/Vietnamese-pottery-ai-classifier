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
        ]);

        $path = $request->file('image')->store('potteries', 'public');

        $fullPath = storage_path('app/public/' . $path);

        // Send the image to the Python AI server and await the TADP pipeline result
        $response = Http::timeout(220)->attach(
            'file',
            file_get_contents($fullPath),
            basename($fullPath)
        )->post('http://127.0.0.1:8001/predict');

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
                    'ai_model'        => 'TADP',
                    'raw_answer'      => $result['raw_text'] ?? null,
                    'forgery_risk'    => $result['forgery_risk'] ?? null,
                    'debate_trail'    => $result['debate_trail'] ?? [],
                ]
            ]);
        }

        $pottery = Pottery::create([
            'image_path'      => $path,
            'predicted_label' => $result['predicted_label'] ?? null,
            'confidence'      => $result['confidence'] ?? null,
            'ai_model'        => 'TADP',
            'raw_answer'      => $result['raw_text'] ?? null,
            'evidence'        => $result['evidence'] ?? null,
            'rationale'       => $result['rationale'] ?? null,
            'forgery_risk'    => $result['forgery_risk'] ?? null,
            'debate_trail'    => $result['debate_trail'] ?? [],
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
