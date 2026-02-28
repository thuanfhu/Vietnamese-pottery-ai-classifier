<?php

use Illuminate\Support\Facades\Route;
use App\Http\Controllers\Api\PotteryController;

Route::get('/potteries', [PotteryController::class, 'index']);
Route::post('/upload', [PotteryController::class, 'upload']);
