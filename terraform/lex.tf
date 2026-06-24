# Amazon Lex Bot - Layanan Publik Kaltim
resource "aws_lexv2models_bot" "kaltim" {
  name     = "${var.project_name}-chatbot"
  description = "Asisten virtual layanan publik Kaltim Smart Platform"
  role_arn = aws_iam_role.lex_bot.arn

  data_privacy {
    child_directed = false
  }

  idle_session_ttl_in_seconds = 300
}

# IAM Role for Lex
resource "aws_iam_role" "lex_bot" {
  name = "${var.project_name}-lex-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = { Service = "lexv2.amazonaws.com" }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "lex_bot" {
  name = "${var.project_name}-lex-policy"
  role = aws_iam_role.lex_bot.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["polly:SynthesizeSpeech", "comprehend:DetectSentiment"]
      Resource = "*"
    }]
  })
}

# Lex Bot Locale - English (en_US) karena id_ID tidak mendukung custom intent di Lex V2
# Bot tetap bisa membalas dalam bahasa Indonesia
resource "aws_lexv2models_bot_locale" "id" {
  bot_id      = aws_lexv2models_bot.kaltim.id
  bot_version = "DRAFT"
  locale_id   = "en_US"
  n_lu_intent_confidence_threshold = 0.4
}

# Intent - Greeting
resource "aws_lexv2models_intent" "greeting" {
  depends_on  = [aws_lexv2models_bot_locale.id]
  bot_id      = aws_lexv2models_bot.kaltim.id
  bot_version = "DRAFT"
  locale_id   = "en_US"
  name        = "GreetingIntent"

  sample_utterance {
    utterance = "halo"
  }
  sample_utterance {
    utterance = "hai"
  }
  sample_utterance {
    utterance = "selamat pagi"
  }
  sample_utterance {
    utterance = "selamat siang"
  }
  sample_utterance {
    utterance = "assalamualaikum"
  }

  fulfillment_code_hook {
    enabled = false
  }

  closing_setting {
    closing_response {
      message_group {
        message {
          plain_text_message {
            value = "Halo! Selamat datang di Kaltim Smart Platform. Ada yang bisa saya bantu?"
          }
        }
      }
    }
  }
}

# Intent - Pembuatan KTP
resource "aws_lexv2models_intent" "ktp" {
  depends_on  = [aws_lexv2models_bot_locale.id]
  bot_id      = aws_lexv2models_bot.kaltim.id
  bot_version = "DRAFT"
  locale_id   = "en_US"
  name        = "KTPIntent"

  sample_utterance { utterance = "cara buat KTP" }
  sample_utterance { utterance = "syarat KTP" }
  sample_utterance { utterance = "buat kartu tanda penduduk" }
  sample_utterance { utterance = "pengajuan e-KTP" }

  fulfillment_code_hook { enabled = false }

  closing_setting {
    closing_response {
      message_group {
        message {
          plain_text_message {
            value = "Untuk membuat KTP, daftar akun dulu lalu ajukan di menu Layanan > Pembuatan KTP. Estimasi 14 hari kerja. Syarat: KK asli, surat pengantar RT/RW, dan pas foto."
          }
        }
      }
    }
  }
}

# Intent - Kartu Keluarga
resource "aws_lexv2models_intent" "kk" {
  depends_on  = [aws_lexv2models_bot_locale.id]
  bot_id      = aws_lexv2models_bot.kaltim.id
  bot_version = "DRAFT"
  locale_id   = "en_US"
  name        = "KKIntent"

  sample_utterance { utterance = "cara buat KK" }
  sample_utterance { utterance = "syarat kartu keluarga" }
  sample_utterance { utterance = "pembuatan KK" }

  fulfillment_code_hook { enabled = false }

  closing_setting {
    closing_response {
      message_group {
        message {
          plain_text_message {
            value = "Pembuatan KK bisa diajukan online. Pilih menu Layanan > Pembuatan KK. Estimasi 7 hari kerja."
          }
        }
      }
    }
  }
}

# Intent - Laporan Warga
resource "aws_lexv2models_intent" "lapor" {
  depends_on  = [aws_lexv2models_bot_locale.id]
  bot_id      = aws_lexv2models_bot.kaltim.id
  bot_version = "DRAFT"
  locale_id   = "en_US"
  name        = "LaporIntent"

  sample_utterance { utterance = "lapor jalan rusak" }
  sample_utterance { utterance = "mau lapor masalah" }
  sample_utterance { utterance = "aduan warga" }
  sample_utterance { utterance = "sampah menumpuk" }

  fulfillment_code_hook { enabled = false }

  closing_setting {
    closing_response {
      message_group {
        message {
          plain_text_message {
            value = "Laporkan masalah di menu Laporan Warga. Pilih kategori (infrastruktur/lingkungan/sosial), isi deskripsi dan lokasi, lalu kirim."
          }
        }
      }
    }
  }
}


# Lex Bot Version — dibuat setelah semua intent selesai
resource "aws_lexv2models_bot_version" "v1" {
  depends_on = [
    aws_lexv2models_intent.greeting,
    aws_lexv2models_intent.ktp,
    aws_lexv2models_intent.kk,
    aws_lexv2models_intent.lapor,
  ]
  bot_id = aws_lexv2models_bot.kaltim.id
  locale_specification = {
    en_US = {
      source_bot_version = "DRAFT"
    }
  }
}

# Note: aws_lexv2models_bot_alias is not yet supported by the Terraform AWS provider.
# After terraform apply, go to AWS Console → Amazon Lex → KaltimServiceBot
# → Build → Deploy → Create alias "prod" → copy the Alias ID.
# Then update AWS_LEX_BOT_ALIAS_ID in docker/.env on EC2.

output "lex_bot_id" {
  description = "Lex Bot ID"
  value       = aws_lexv2models_bot.kaltim.id
}

output "lex_bot_version" {
  description = "Lex Bot Version (use this when creating alias in console)"
  value       = aws_lexv2models_bot_version.v1.bot_version
}
