<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class Pottery extends Model
{
    protected $fillable = [
        'image_path',
        'predicted_label',
        'confidence',
        'ai_model',
        'raw_answer',
    ];
}
