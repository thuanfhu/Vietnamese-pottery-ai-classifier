<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('potteries', function (Blueprint $table) {
            $table->text('raw_answer')->nullable()->after('ai_model');
        });
    }

    public function down(): void
    {
        Schema::table('potteries', function (Blueprint $table) {
            $table->dropColumn('raw_answer');
        });
    }
};
