<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use Illuminate\Http\Request;
use App\Models\Pottery;
use Illuminate\Http\JsonResponse;
use Illuminate\Support\Facades\Http;

class PotteryController extends Controller
{
    public function index(): JsonResponse
    {
        return response()->json(Pottery::latest()->get());
    }

    public function upload(Request $request)
    {
        $request->validate([
            'image' => 'required|image'
        ]);

        $path = $request->file('image')->store('potteries', 'public');

        $fullPath = storage_path('app/public/' . $path);

        $response = Http::attach(
            'file',
            file_get_contents($fullPath),
            basename($fullPath)
        )->post('http://127.0.0.1:8001/predict');

        $result = $response->json();

        $pottery = Pottery::create([
            'image_path' => $path,
            'predicted_label' => $result['predicted_label'] ?? null,
            'confidence' => $result['confidence'] ?? null
        ]);

        return response()->json([
            'message' => 'Upload and prediction successful',
            'data' => $pottery
        ]);
    }
}
