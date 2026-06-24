<?php

namespace App\Http\Controllers;

use Aws\LexRuntimeService\LexRuntimeServiceClient;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class ChatbotController extends Controller
{
    private array $faq = [
        'ktp' => [
            'keywords' => ['ktp', 'kartu tanda penduduk', 'kartu penduduk', 'ektp'],
            'answer' => "Untuk membuat KTP, daftar akun dulu lalu ajukan di menu Layanan > Pembuatan KTP. Estimasi 14 hari kerja. Syarat: KK asli, surat pengantar RT/RW, dan pas foto.",
        ],
        'kk' => [
            'keywords' => ['kk', 'kartu keluarga', 'keluarga'],
            'answer' => "Pembuatan KK bisa diajukan online lewat platform ini. Pilih menu Layanan > Pembuatan KK. Estimasi 7 hari kerja. Pastikan data anggota keluarga sudah lengkap.",
        ],
        'akta' => [
            'keywords' => ['akta', 'kelahiran', 'lahir', 'anak'],
            'answer' => "Akta Kelahiran bisa diajukan di menu Layanan > Akta Kelahiran. Estimasi 7 hari kerja. Syarat: surat keterangan lahir dari dokter/bidan, KK orang tua, dan KTP orang tua.",
        ],
        'izin' => [
            'keywords' => ['izin', 'usaha', 'umkm', 'bisnis', 'dagang'],
            'answer' => "Izin Usaha Mikro bisa diajukan online. Estimasi 21 hari kerja. Syarat: KTP, NPWP (jika ada), surat keterangan domisili usaha, dan foto tempat usaha.",
        ],
        'pindah' => [
            'keywords' => ['pindah', 'domisili', 'alamat', 'pindahan'],
            'answer' => "Surat Pindah bisa diajukan online. Estimasi 5 hari kerja. Syarat: KTP, KK, surat keterangan pindah dari daerah asal, dan alamat tujuan yang jelas.",
        ],
        'status' => [
            'keywords' => ['status', 'cek', 'pantau', 'progress', 'proses'],
            'answer' => "Cek status permintaan di Dashboard Warga atau menu Layanan. Anda akan mendapat notifikasi otomatis tiap kali status berubah.",
        ],
        'lapor' => [
            'keywords' => ['lapor', 'aduan', 'masalah', 'rusak', 'sampah', 'jalan'],
            'answer' => "Laporkan masalah di menu Laporan Warga. Pilih kategori (infrastruktur/lingkungan/sosial), isi deskripsi dan lokasi, lalu kirim. Bisa upload foto juga.",
        ],
        'daftar' => [
            'keywords' => ['daftar', 'registrasi', 'akun', 'buat akun', 'register'],
            'answer' => "Klik Register di pojok kanan atas. Isi nama, email, password, telepon, dan alamat. Proses pendaftaran gratis dan hanya butuh 1 menit.",
        ],
        'waktu' => [
            'keywords' => ['jam', 'waktu', 'buka', 'operasional', 'kapan'],
            'answer' => "Platform kami beroperasi 24 jam sehari, 7 hari seminggu. Anda bisa mengajukan layanan kapan saja, di mana saja!",
        ],
    ];

    private $greetings = [
        'halo', 'hai', 'hi', 'hello', 'selamat pagi', 'selamat siang', 'selamat sore', 'selamat malam',
        'assalamualaikum', 'assalamu\'alaikum', 'permisi', 'mohon bantuan', 'tolong', 'help',
    ];

    private $thanks = [
        'makasih', 'terima kasih', 'thank', 'thanks', 'oke', 'ok', 'sip', 'mantap',
    ];

    public function chat(Request $request): JsonResponse
    {
        $message = strtolower(trim($request->input('message', '')));
        if (empty($message)) {
            return response()->json(['reply' => 'Silakan ketik pertanyaan Anda. Saya siap membantu!']);
        }

        // Try Amazon Lex if configured
        $sessionId = $request->ip() . '-' . ($request->header('X-Session-Id', 'default'));
        $lexReply = $this->tryLex($message, $sessionId);
        if ($lexReply !== null) {
            return response()->json(['reply' => $lexReply]);
        }

        // Fallback to rule-based
        return response()->json(['reply' => $this->ruleBasedReply($message)]);
    }

    private function tryLex(string $message, string $sessionId): ?string
    {
        $botId = env('AWS_LEX_BOT_ID');
        $aliasId = env('AWS_LEX_BOT_ALIAS_ID');

        if (!$botId || !$aliasId) {
            return null;
        }

        try {
            $client = new LexRuntimeServiceClient([
                'version' => 'latest',
                'region' => env('AWS_DEFAULT_REGION', 'ap-southeast-1'),
            ]);

            $result = $client->recognizeText([
                'botId' => $botId,
                'botAliasId' => $aliasId,
                'localeId' => 'en_US',
                'sessionId' => $sessionId,
                'text' => $message,
            ]);

            $messages = $result->get('messages') ?? [];
            if (!empty($messages)) {
                return $messages[0]['content'] ?? null;
            }

            return $result->get('sessionState')['intent']['name']
                ? "Maaf, saya tidak mengerti. Coba tanyakan dengan kata lain."
                : null;
        } catch (\Throwable $e) {
            logger()->warning('Lex error: ' . $e->getMessage());
            return null;
        }
    }

    private function ruleBasedReply(string $message): string
    {
        foreach ($this->greetings as $g) {
            if (str_contains($message, $g)) {
                return "Halo! Selamat datang di Kaltim Smart Platform 👋\n\nSaya asisten virtual yang siap membantu. Anda bisa tanya tentang:\n• Pembuatan KTP, KK, Akta Kelahiran\n• Izin Usaha & Surat Pindah\n• Cara cek status permintaan\n• Cara melapor masalah\n\nSilakan ketik pertanyaan Anda!";
            }
        }

        foreach ($this->thanks as $t) {
            if (str_contains($message, $t)) {
                return "Sama-sama! 😊 Senang bisa membantu. Kalau ada pertanyaan lain, ketik aja ya.";
            }
        }

        foreach ($this->faq as $item) {
            foreach ($item['keywords'] as $keyword) {
                if (str_contains($message, $keyword)) {
                    return $item['answer'];
                }
            }
        }

        if (str_contains($message, 'layanan') || str_contains($message, 'menu')) {
            return "Layanan yang tersedia:\n\n📋 Pembuatan KTP — 14 hari\n📋 Kartu Keluarga — 7 hari\n👶 Akta Kelahiran — 7 hari\n🏪 Izin Usaha — 21 hari\n📝 Surat Pindah — 5 hari\n📢 Laporan Warga\n\nKetik nama layanan untuk info lebih detail.";
        }

        return "Maaf, saya belum mengerti. Coba tanyakan tentang:\n• Pembuatan KTP / KK / Akta Kelahiran\n• Izin Usaha / Surat Pindah\n• Cara cek status atau melapor\n• Cara daftar akun\n\nAtau ketik 'layanan' untuk lihat semua layanan.";
    }

    public function page()
    {
        return view('chatbot');
    }
}
