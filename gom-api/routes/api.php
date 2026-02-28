<?php

use Illuminate\Support\Facades\Route;
use App\Http\Controllers\Api\PotteryController;

Route::get('/potteries', [PotteryController::class, 'index']);
Route::post('/upload', [PotteryController::class, 'upload']);
Route::delete('/potteries/{pottery}', [PotteryController::class, 'destroy']);

Route::get('/img/{path}', function (string $path) {
    $fullPath = storage_path('app/public/' . $path);
    if (!file_exists($fullPath)) {
        abort(404);
    }
    $mime = mime_content_type($fullPath) ?: 'application/octet-stream';
    return response()->file($fullPath, [
        'Content-Type'                 => $mime,
        'Cache-Control'                => 'public, max-age=86400',
    ]);
})->where('path', '.*');
