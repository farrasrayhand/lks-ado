# Deployment Guide — Kaltim Smart Platform

> Deploy ke AWS menggunakan Terraform + Docker. Ikuti langkah-langkah di bawah sesuai urutan.

---

## Daftar Isi

1. [Tools yang Dibutuhkan](#1-tools-yang-dibutuhkan)
2. [Setup AWS Account](#2-setup-aws-account)
3. [Deploy dengan Terraform](#3-deploy-dengan-terraform)
4. [Verifikasi EC2 via AWS Console](#4-verifikasi-ec2-via-aws-console)
5. [Setup Amazon Lex (Chatbot)](#5-setup-amazon-lex-chatbot)
6. [Buat AMI & Update Launch Template](#6-buat-ami--update-launch-template)
7. [Cek & Test Aplikasi](#7-cek--test-aplikasi)
8. [Monitoring](#8-monitoring)
9. [Arsitektur AWS](#9-arsitektur-aws)
10. [Pengujian Mandiri dengan Postman](#10-pengujian-mandiri-dengan-postman)
11. [Checklist Pengumpulan](#11-checklist-pengumpulan)

---

## 1. Tools yang Dibutuhkan

Install semua ini sebelum mulai:

| Tool | Versi | Install |
|---|---|---|
| Terraform | >= 1.5 | [hashicorp.com](https://developer.hashicorp.com/terraform/install) |
| AWS CLI | >= 2.0 | [aws.amazon.com/cli](https://aws.amazon.com/cli/) |
| Git | any | sudah terinstall di EC2 |

---

## 2. Setup AWS Account

### Langkah 1 — Buat IAM User

1. Buka **AWS Console → IAM → Users → Create user**
2. Nama user: `kaltim-terraform`
3. Pilih **Attach policies directly** → centang `AdministratorAccess`
4. Klik **Create user**
5. Buka user yang baru dibuat → tab **Security credentials → Create access key**
6. Pilih **Command Line Interface (CLI)** → buat
7. **Catat** Access Key ID dan Secret Access Key (hanya muncul sekali!)

### Langkah 2 — Konfigurasi AWS CLI

```bash
aws configure
```

Isi saat diminta:
```
AWS Access Key ID: AKIA... (dari langkah 1)
AWS Secret Access Key: ...
Default region name: ap-southeast-1
Default output format: json
```

Verifikasi:
```bash
aws sts get-caller-identity
# Harus menampilkan Account ID dan ARN kamu
```

### Langkah 3 — Buat SSH Key Pair

1. Buka **AWS Console → EC2 → Key Pairs → Create key pair**
2. Nama: `kaltim-key`, Type: RSA, Format: `.pem`
3. File `.pem` akan terdownload otomatis
4. Simpan dan ubah permission:

```bash
mv ~/Downloads/kaltim-key.pem ~/.ssh/
chmod 400 ~/.ssh/kaltim-key.pem
```

---

## 3. Deploy dengan Terraform

### Langkah 1 — Buat File `terraform.tfvars`

Buat file ini di folder `terraform/` (tidak perlu di-commit, sudah ada di `.gitignore`):

```
terraform/terraform.tfvars
```

Isi dengan nilai berikut:

```
aws_region      = "ap-southeast-1"
project_name    = "kaltim-smart-platform"
environment     = "production"
key_name        = "kaltim-smart-key"
instance_type   = "t3.medium"
db_username     = "kaltim_admin"
db_password     = "K4lt1m#Secure2026!"
db_name         = "kaltim_smart_platform"
app_key         = "base64:..."    ← ambil dari docker/.env (APP_KEY)
jwt_secret      = "..."           ← ambil dari docker/.env (JWT_SECRET)
s3_bucket_name  = "kaltim-uploads-[kode-peserta]-2026"
github_repo_url = "https://github.com/[username]/lks-kaltim-2026-[kode-peserta].git"

# Diisi SETELAH deploy selesai (lihat Section 5 dan 6)
lex_bot_alias_id = ""
app_ami_id       = "ami-0c802847a7dd848c0"
```

> ⚠️ Nilai `app_key` dan `jwt_secret` sudah ada di file `docker/.env` — tinggal copy.
> Tidak perlu isi `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` — EC2 pakai IAM Role otomatis.

### Langkah 2 — Jalankan Terraform

```bash
cd terraform

terraform init

terraform plan   # pastikan tidak ada error sebelum lanjut

terraform apply  # ketik "yes" saat diminta konfirmasi
```

Tunggu **15–20 menit** (RDS yang paling lama). Setelah selesai, jalankan:

```bash
terraform output
```

Catat output ini — akan dipakai di langkah selanjutnya:
- `alb_dns_name` — URL aplikasi kamu (akses lewat browser)
- `rds_endpoint` — endpoint database
- `s3_bucket_name` — nama bucket S3
- `cloudfront_domain` — URL CloudFront untuk akses file upload
- `lex_bot_id` dan `lex_bot_version` — untuk setup Lex di langkah 5

---

## 4. Verifikasi EC2 via AWS Console

> Semua setup di EC2 sudah **otomatis** — Terraform mengatur git clone, Docker, dan `.env` saat instance pertama boot. Kamu tidak perlu SSH manual.

### Langkah 1 — Cek Status Instance

1. Buka **AWS Console → EC2 → Instances**
2. Cari instance bernama `kaltim-smart-platform-instance`
3. Tunggu status **Running** dan **2/2 checks passed**

### Langkah 2 — Akses Terminal via Session Manager (tanpa SSH)

1. Klik instance → klik **Connect** (tombol di atas)
2. Pilih tab **Session Manager** → klik **Connect**
3. Browser akan membuka terminal langsung

Di dalam terminal:

```bash
cd /opt/kaltim-app

# Cek apakah Docker sudah jalan
sudo docker compose -f docker/docker-compose.yml ps

# Lihat log aplikasi
sudo docker compose -f docker/docker-compose.yml logs app --tail=30
```

> Jika `kaltim-app` statusnya `Up`, deployment berhasil.

### Langkah 3 — Cek Health Check

Buka browser: `http://<alb-dns-name>/health`

Harus tampil: **All Systems Operational** dengan status database, cache, dan storage OK.

---

## 5. Setup Amazon Lex (Chatbot)

> Bot, locale, dan semua intent sudah dibuat otomatis oleh Terraform. Yang perlu dilakukan manual hanya **Build** dan **buat alias** — 5 menit via AWS Console.

### Langkah 1 — Build Bot

1. Buka **AWS Console → Amazon Lex → Bots**
2. Klik bot **kaltim-smart-platform-chatbot**
3. Pilih language **English (en_US)** — bot menggunakan locale ini karena `id_ID` tidak mendukung custom intent
4. Klik tombol **Build** → tunggu ~2 menit hingga status **Built**

### Langkah 2 — Buat Versi dan Alias

1. Di halaman bot, klik **Bot versions** → **Create version** → konfirmasi
2. Klik **Deployment → Aliases → Create alias**
3. Alias name: `prod`
4. Bot version: pilih versi yang baru dibuat → **Create**

### Langkah 3 — Ambil Alias ID

1. Klik alias `prod` yang baru dibuat
2. Catat **Alias ID** yang tertera (format: `XXXXXXXXXX`)

### Langkah 4 — Update .env di EC2

Kembali ke Session Manager (Langkah 4.2), lalu:

```bash
cd /opt/kaltim-app

# Edit .env
sudo nano docker/.env
# Cari baris AWS_LEX_BOT_ALIAS_ID= dan isi dengan Alias ID dari langkah di atas

# Restart app
sudo docker compose -f docker/docker-compose.yml up -d --force-recreate app
```

Selesai — chatbot sudah aktif menggunakan Amazon Lex.

---

## 6. Buat AMI & Update Launch Template

> Langkah ini **wajib** sebelum production. Tanpanya, kalau EC2 instance terhapus atau diganti oleh Auto Scaling, semua konfigurasi (termasuk Lex alias ID) hilang dan perlu setup ulang dari awal.
>
> Dengan AMI, instance baru boot dalam hitungan menit sudah langsung siap — tidak perlu git clone, docker build, atau update .env lagi.

### Langkah 1 — Pastikan App Sudah Sempurna

Sebelum buat AMI, verifikasi semua sudah berjalan:
- [ ] `http://<alb-dns-name>/health` → All Systems Operational
- [ ] Login admin dan warga berhasil
- [ ] Chatbot Lex aktif (ketik "cara buat KTP" → dapat respons dari Lex, bukan fallback)
- [ ] Upload file berhasil masuk ke S3

### Langkah 2 — Buat AMI (AWS Console)

1. Buka **AWS Console → EC2 → Instances**
2. Pilih instance `kaltim-smart-platform-instance`
3. Klik **Actions → Image and templates → Create image**
4. Isi:
   - **Image name:** `kaltim-smart-platform-ami`
   - **Description:** `Kaltim Smart Platform - configured with Lex, S3, RDS`
   - **No reboot:** centang (agar instance tidak restart)
5. Klik **Create image**
6. Tunggu status AMI menjadi **Available** (~5 menit) di **EC2 → AMIs**
7. **Catat AMI ID** (format: `ami-xxxxxxxxxxxxxxxxx`)

### Langkah 3 — Update `terraform.tfvars` dengan AMI Baru

Edit `terraform/terraform.tfvars`, update dua baris ini:

```
app_ami_id       = "ami-xxxxxxxxxxxxxxxxx"   ← ganti dengan AMI ID dari langkah 2
lex_bot_alias_id = "XXXXXXXXXX"              ← ganti dengan Alias ID dari Section 5
```

> Tidak perlu edit file lain — `variables.tf` dan `ec2.tf` sudah dikonfigurasi untuk membaca nilai ini otomatis.

### Langkah 4 — Apply Terraform

```bash
cd terraform
terraform apply
```

Ketik `yes`. Terraform akan update launch template dengan AMI baru. Instance yang berjalan tidak terpengaruh — hanya instance baru ke depannya yang akan boot dari AMI ini.

> Sekarang kalau Auto Scaling ganti instance, instance baru langsung siap dalam ~2 menit tanpa setup manual.

---

## 7. Cek & Test Aplikasi

### Health Check

```bash
# Cek via curl
curl http://<alb-dns-name>/health

# API Health
curl http://<alb-dns-name>/api/health
# Harus return: {"success":true,"message":"All systems operational"}
```

### Test Login via Browser

Buka `http://<alb-dns-name>`:
- Admin: `admin@kaltim.go.id` / `password`
- Warga: `budi@email.com` / `password`
- Chatbot: klik bubble 💬 di kanan bawah, ketik "cara buat KTP"

### Test Upload & CloudFront

1. Login sebagai warga → buat laporan → upload foto
2. Cek bahwa URL foto di response mengandung `cloudfront.net` (bukan `s3.amazonaws.com`)
3. Buka URL foto tersebut di browser — harus tampil gambar (bukan Access Denied)

Contoh URL yang benar:
```
https://xxxxxx.cloudfront.net/storage/uploads/reports/namafile.jpg ✅
```

Kalau masih `http://<alb-dns-name>/storage/...` berarti FILESYSTEM_DISK masih `local` — cek `.env` di EC2.

### Test API via curl

```bash
# Daftar layanan
curl http://<alb-dns-name>/api/services

# Login admin
curl -X POST http://<alb-dns-name>/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"admin@kaltim.go.id","password":"password"}'

# Gunakan token dari response login untuk endpoint lain:
curl http://<alb-dns-name>/api/dashboard/stats \
  -H "Authorization: Bearer <token>"
```

---

## 8. Monitoring

### Lihat Log Aplikasi

Akses EC2 via Session Manager (Section 4, Langkah 2), lalu:

```bash
sudo docker compose -f /opt/kaltim-app/docker/docker-compose.yml logs app -f
```

### CloudWatch di AWS Console

- **EC2:** AWS Console → EC2 → Auto Scaling Groups → tab Monitoring
- **RDS:** AWS Console → RDS → Databases → tab Monitoring
- **ALB:** AWS Console → EC2 → Load Balancers → tab Monitoring

Metrik yang perlu dipantau: CPU Utilization, Database Connections, Request Count, Response Time.

---

## 9. Arsitektur AWS

![Architecture](architecture-diagram.png)

```
                      INTERNET
                          │
              ┌───────────┴────────────┐
              ▼                        ▼
  ┌─────────────────────┐   ┌──────────────────────┐
  │  Application Load   │   │   CloudFront CDN     │
  │  Balancer (ALB)     │   │   (file uploads)     │
  │  Public Subnets     │   └──────────┬───────────┘
  └──────────┬──────────┘              │
             │                         ▼
     ┌───────┴───────┐          ┌─────────────┐
     ▼               ▼          │  S3 Uploads │  (private, OAC)
  ┌──────────┐  ┌──────────┐   └─────────────┘
  │ EC2 (AZ1)│  │ EC2 (AZ2)│   Private App Subnets
  │ Docker + │  │ Docker + │
  │ PHP+Nginx│  │ PHP+Nginx│
  └────┬─────┘  └────┬─────┘
       │              │
       ▼              ▼
  ┌─────────┐   ┌──────────────┐
  │   RDS   │   │ ElastiCache  │   Private DB Subnets
  │  MySQL  │   │   Redis      │
  └─────────┘   └──────────────┘

  ┌──────────────┐
  │ Amazon Lex   │  (managed service, di luar VPC)
  │ Chatbot      │
  └──────────────┘

  VPC 10.0.0.0/16
  ├── Public Subnets:  10.0.1.0/24, 10.0.2.0/24   (ALB)
  ├── App Subnets:     10.0.10.0/24, 10.0.11.0/24  (EC2)
  └── DB Subnets:      10.0.20.0/24, 10.0.21.0/24  (RDS + Redis)
```

| Komponen | Spesifikasi | Keterangan |
|---|---|---|
| VPC | 10.0.0.0/16 | Virtual Private Cloud |
| ALB | 1 | Application Load Balancer (public) |
| EC2 ASG | 1–2 × t3.medium | Auto Scaling, private subnet |
| RDS | db.t3.micro, MySQL 8.0 | Private subnet |
| ElastiCache | cache.t3.micro, Redis 7 | Private subnet |
| S3 | 1 bucket | Upload file, private (no public access) |
| CloudFront | 1 distribution | CDN untuk file S3, akses via OAC |
| Amazon Lex | 1 bot, en_US locale | Chatbot AI (respons bahasa Indonesia) |
| NAT Gateway | 1 | Internet untuk instance private |

---

## 10. Pengujian Mandiri dengan Postman

### Setup Postman

1. Buat **New Collection** → nama: `Kaltim Smart Platform`
2. Tambah **Collection Variables**:
   - `base_url` → `http://<alb-dns-name>` (isi dengan ALB DNS kamu)
   - `token` → (kosong, diisi setelah login)

---

### A. Test Autentikasi

**Register:**
```
POST {{base_url}}/api/auth/register
Body (JSON):
{
  "name": "Test User",
  "email": "test@example.com",
  "password": "password123",
  "phone": "08123456789",
  "address": "Jl. Test No. 1"
}
✅ status 201, success: true, data.token ada
```

**Login Admin:**
```
POST {{base_url}}/api/auth/login
Body (JSON): { "email": "admin@kaltim.go.id", "password": "password" }
✅ status 200, data.token ada
→ Copy token ke Collection variable "token"
```

**Login Warga:**
```
POST {{base_url}}/api/auth/login
Body (JSON): { "email": "budi@email.com", "password": "password" }
```

**Profile:**
```
GET {{base_url}}/api/auth/profile
Authorization: Bearer {{token}}
✅ data.role dan data.email ada
```

**Logout:**
```
POST {{base_url}}/api/auth/logout
Authorization: Bearer {{token}}
✅ success: true
```

---

### B. Test Layanan Publik

**Daftar Layanan (publik, tanpa token):**
```
GET {{base_url}}/api/services
✅ data berupa array, data[0].name ada
```

**Ajukan Layanan (sebagai warga):**
```
POST {{base_url}}/api/services/request
Authorization: Bearer <warga_token>
Body: { "service_type_id": 1, "description": "Pengajuan test" }
✅ status 201, data.status = "pending"
```

**Update Status (sebagai admin):**
```
PUT {{base_url}}/api/services/request/1/status
Authorization: Bearer <admin_token>
Body: { "status": "processing" }
✅ status 200, success: true
```

**Cek Notifikasi Warga (harus ada notif baru):**
```
GET {{base_url}}/api/notifications
Authorization: Bearer <warga_token>
✅ data.data[0].message mengandung kata "berubah"
```

---

### C. Test Laporan Warga

**Buat Laporan:**
```
POST {{base_url}}/api/reports
Authorization: Bearer <warga_token>
Body:
{
  "category": "infrastructure",
  "title": "Jalan Berlubang Test",
  "description": "Test laporan jalan berlubang",
  "location": "Jl. Test"
}
✅ status 201, data.status = "open"
```

**Lihat Laporan (admin — harus bisa lihat semua):**
```
GET {{base_url}}/api/reports
Authorization: Bearer <admin_token>
✅ data.data berisi laporan dari semua user
```

**Lihat Laporan (warga — hanya miliknya):**
```
GET {{base_url}}/api/reports
Authorization: Bearer <warga_token>
✅ semua item di data.data punya user_id yang sama
```

---

### D. Test Dashboard Admin

**Statistik:**
```
GET {{base_url}}/api/dashboard/stats
Authorization: Bearer <admin_token>
✅ data.users, data.reports, data.service_requests ada
```

**Rekapitulasi per Kategori:**
```
GET {{base_url}}/api/dashboard/reports/summary
Authorization: Bearer <admin_token>
✅ data berupa array { category, total }
```

---

### E. Test Keamanan (RBAC)

**Warga akses admin → harus 403:**
```
GET {{base_url}}/api/dashboard/stats
Authorization: Bearer <warga_token>
✅ status 403, success: false
```

**Warga update status → harus 403:**
```
PUT {{base_url}}/api/services/request/1/status
Authorization: Bearer <warga_token>
Body: { "status": "done" }
✅ status 403, success: false
```

**Tanpa token → harus 401:**
```
GET {{base_url}}/api/auth/profile
(Tanpa Authorization header)
✅ status 401
```

**S3 Block Public Access:**
```
Buka di browser: https://<s3-bucket>.s3.ap-southeast-1.amazonaws.com/
✅ Harus muncul "Access Denied"
❌ Jangan sampai muncul list file
```

**Akses via CloudFront (harus bisa):**
```
Buka URL file dari response upload, contoh:
https://xxxxxx.cloudfront.net/storage/uploads/reports/namafile.jpg
✅ File tampil di browser (gambar/PDF)
✅ URL mengandung "cloudfront.net" bukan "s3.amazonaws.com"
```

---

### F. Test Health Check

**Web Health (browser):**
```
Buka: http://<alb-dns-name>/health
✅ Tampilkan "All Systems Operational"
✅ Database: OK, Cache: OK, Storage: OK
```

**API Health:**
```
GET {{base_url}}/api/health
✅ data.database.status = "ok"
✅ data.cache.status = "ok"
✅ data.storage.status = "ok"
```

---

### G. Test Chatbot

**Via browser:**
```
Buka http://<alb-dns-name> → klik 💬 → ketik: "cara buat ktp"
✅ Bot membalas dengan panduan pembuatan KTP
```

**Via API:**
```
POST {{base_url}}/api/chatbot
Body: { "message": "cara daftar akun" }
✅ reply berisi instruksi registrasi
```

---

### H. Validasi Format Response dan Pagination

**Format JSON — semua endpoint harus punya:**
```json
{ "success": true|false, "message": "...", "data": {...} }
```

**Pagination:**
```
GET {{base_url}}/api/reports?per_page=2&page=1
✅ data.current_page = 1
✅ data.per_page = 2
✅ data.data.length <= 2
✅ data.links dan data.total ada
```

### Ekspor Postman Collection

1. Klik **...** pada collection → **Export**
2. Format: **Collection v2.1**
3. Simpan sebagai: `Kaltim-Smart-Platform.postman_collection.json`

---

## 11. Checklist Pengumpulan

> Deadline: **pukul 17.00 WITA**

### Yang harus dikumpulkan:

- [ ] **URL Live** — `http://<alb-dns-name>` aktif dan bisa diakses
  - Tulis di bagian atas `README.md`
- [ ] **Postman Collection** — file `Kaltim-Smart-Platform.postman_collection.json`
  - Semua endpoint sudah di-test, response sesuai
- [ ] **Screenshot CloudWatch Dashboard**
  - Buat dashboard baru di CloudWatch
  - Tambahkan widget: EC2 CPU, ALB Request Count, RDS Connections, Response Time
  - Screenshot semua widget dalam satu layar → simpan sebagai `cloudwatch-dashboard.png`
- [ ] **CloudTrail Presigned URL**
  - Aktifkan CloudTrail jika belum (simpan log ke S3)
  - Generate presigned URL **maksimal 1 jam sebelum deadline (sekitar 16.00 WITA):**
    ```bash
    aws s3 presign s3://<cloudtrail-bucket>/AWSLogs/<account-id>/CloudTrail/<region>/<date>/ \
      --expires-in 3600
    ```
  - Simpan URL yang dihasilkan

### Update README.md sebelum kumpul:

```markdown
## Deployment Live
- **URL:** http://<alb-dns-name>
- **Health Check:** http://<alb-dns-name>/health
- **API Docs:** http://<alb-dns-name>/api-info
```

---

## Perkiraan Biaya Bulanan

| Layanan | Spesifikasi | Estimasi |
|---|---|---|
| EC2 | 2x t3.medium | ~$60 |
| RDS | db.t3.micro | ~$15 |
| ElastiCache | cache.t3.micro | ~$12 |
| ALB | 1 | ~$20 |
| NAT Gateway | 1 | ~$32 |
| S3 | 1 GB | ~$0.02 |
| Lex | ~1000 req/hari | ~$5 |
| **Total** | | **~$144/bulan** |
