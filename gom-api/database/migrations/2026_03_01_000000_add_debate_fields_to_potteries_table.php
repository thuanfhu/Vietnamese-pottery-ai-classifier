<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    // Adds TADP debate columns: physical evidence, historian rationale, forgery risk level, and full debate trail
    public function up(): void
    {
        Schema::table('potteries', function (Blueprint $table) {
            $table->longText('evidence')->nullable()->after('raw_answer');
            $table->longText('rationale')->nullable()->after('evidence');
            $table->string('forgery_risk', 30)->nullable()->after('rationale');
            $table->json('debate_trail')->nullable()->after('forgery_risk');
        });
    }

    public function down(): void
    {
        Schema::table('potteries', function (Blueprint $table) {
            $table->dropColumn(['evidence', 'rationale', 'forgery_risk', 'debate_trail']);
        });
    }
};
