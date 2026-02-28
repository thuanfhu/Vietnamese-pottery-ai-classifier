<?php

use Illuminate\Support\Facades\Route;
use App\Http\Controllers\Api\PotteryController;

Route::post('/upload', [PotteryController::class, 'upload']);