# Deployment Guide — Kaltim Smart Platform

> Deploy ke AWS menggunakan Terraform + Docker. Ikuti langkah-langkah di bawah sesuai urutan.

---

## Daftar Isi

1. [Tools yang Dibutuhkan](#1-tools-yang-dibutuhkan)
2. [Setup AWS Account](#2-setup-aws-account)
3. [Deploy Infrastruktur dengan Terraform](#3-deploy-infrastruktur-dengan-terraform)
4. [Launch EC2 Instance](#4-launch-ec2-instance)
5. [Setup Aplikasi di EC2](#5-setup-aplikasi-di-ec2)
6. [Setup Amazon Lex (Chatbot)](#6-setup-amazon-lex-chatbot)
7. [Buat AMI dari EC2](#7-buat-ami-dari-ec2)
8. [Setup Auto Scaling Group](#8-setup-auto-scaling-group)
9. [Cek & Test Aplikasi](#9-cek--test-aplikasi)
10. [Monitoring](#10-monitoring)
11. [Arsitektur AWS](#11-arsitektur-aws)
12. [Pengujian Mandiri dengan Postman](#12-pengujian-mandiri-dengan-postman)
13. [Checklist Pengumpulan](#13-checklist-pengumpulan)

---

## 1. Tools yang Dibutuhkan

Install semua ini sebelum mulai:

| Tool | Versi | Install |
|---|---|---|
| Terraform | >= 1.5 | [hashicorp.com](https://developer.hashicorp.com/terraform/install) |
| AWS CLI | >= 2.0 | [aws.amazon.com/cli](https://aws.amazon.com/cli/) |
| Git | any | sudah ada di sistem |

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

---

## 3. Deploy Infrastruktur dengan Terraform

Terraform akan membuat semua infrastruktur AWS yang dibutuhkan: VPC, RDS, Redis, S3, CloudFront, Lex, ALB, dan IAM Role. **EC2 dibuat manual di Section 4.**

### Langkah 1 — Buat File `terraform.tfvars`

Buat file ini di folder `terraform/` (sudah ada di `.gitignore`, jangan di-commit):

```
terraform/terraform.tfvars
```

Isi:

```
aws_region   = "ap-southeast-1"
project_name = "kaltim-smart-platform"
environment  = "production"

db_username  = "kaltim_admin"
db_password  = "K4lt1m#Secure2026!"
db_name      = "kaltim_smart_platform"

s3_bucket_name = "kaltim-uploads-[kode-peserta]-2026"
```

> Ganti `[kode-peserta]` dengan kode tim kamu agar nama bucket unik di seluruh AWS.

### Langkah 2 — Jalankan Terraform

```bash
cd terraform

terraform init

terraform plan   # pastikan tidak ada error sebelum lanjut

terraform apply  # ketik "yes" saat diminta
```

Tunggu **15–20 menit** (RDS yang paling lama).

### Langkah 3 — Catat Output

Setelah selesai, jalankan:

```bash
terraform output
```

**Catat semua nilai ini** — akan dipakai di langkah berikutnya:

| Output | Dipakai untuk |
|---|---|
| `alb_dns_name` | URL aplikasi |
| `rds_endpoint` | DB_HOST di .env |
| `redis_endpoint` | REDIS_HOST di .env |
| `s3_bucket_name` | AWS_BUCKET di .env |
| `cloudfront_domain` | AWS_URL di .env |
| `lex_bot_id` | AWS_LEX_BOT_ID di .env |
| `lex_bot_version` | untuk buat alias Lex di Section 6 |
| `ec2_security_group_id` | pilih saat launch EC2 |
| `iam_instance_profile_name` | attach ke EC2 saat launch |
| `app_private_subnet_id` | subnet untuk EC2 |

---

## 4. Launch EC2 Instance

Buat satu EC2 instance secara manual menggunakan resource yang sudah dibuat Terraform.

### Langkah 1 — Launch Instance

1. Buka **AWS Console → EC2 → Instances → Launch instances**

2. Isi konfigurasi:

   | Setting | Nilai |
   |---|---|
   | **Name** | `kaltim-app-instance` |
   | **AMI** | Amazon Linux 2023 AMI (pilih yang `x86_64`) |
   | **Instance type** | `t3.medium` |
   | **Key pair** | pilih key pair yang ada, atau buat baru (tidak wajib karena pakai Session Manager) |

3. **Network settings** → klik **Edit**:
   - **VPC:** pilih `kaltim-smart-platform-vpc`
   - **Subnet:** pilih subnet dengan ID dari `app_private_subnet_id` (output Terraform)
   - **Auto-assign public IP:** `Disable` (instance ada di private subnet)
   - **Security groups:** pilih `kaltim-smart-platform-app-sg`

4. **Advanced details:**
   - **IAM instance profile:** pilih `kaltim-smart-platform-ec2-profile` (dari `iam_instance_profile_name`)

5. Klik **Launch instance**

### Langkah 2 — Tunggu Instance Ready

1. Buka **EC2 → Instances**
2. Tunggu instance `kaltim-app-instance` statusnya **Running** dan **2/2 checks passed** (~2 menit)

---

## 5. Setup Aplikasi di EC2

Akses instance via Session Manager (browser), lalu install Docker, clone repo, dan jalankan aplikasi.

### Langkah 1 — Buka Session Manager

1. Di **EC2 → Instances**, pilih instance `kaltim-app-instance`
2. Klik tombol **Connect** → pilih tab **Session Manager** → klik **Connect**
3. Browser membuka terminal langsung (tidak perlu SSH)

### Langkah 2 — Install Docker dan Git

Di terminal Session Manager:

```bash
sudo su - ec2-user

# Install Docker dan Git
sudo yum install -y docker git

# Install Docker Compose plugin
sudo mkdir -p /usr/local/lib/docker/cli-plugins
sudo curl -SL "https://github.com/docker/compose/releases/download/v2.27.0/docker-compose-linux-x86_64" \
    -o /usr/local/lib/docker/cli-plugins/docker-compose
sudo chmod +x /usr/local/lib/docker/cli-plugins/docker-compose

# Start Docker
sudo systemctl enable docker
sudo systemctl start docker
sudo usermod -aG docker ec2-user

# Refresh group (agar bisa pakai docker tanpa sudo)
newgrp docker
```

Verifikasi:
```bash
docker --version
docker compose version
```

### Langkah 3 — Clone Repository

```bash
git clone https://github.com/[username]/[nama-repo].git /opt/kaltim-app
cd /opt/kaltim-app
```

> Ganti URL dengan repo kamu.

### Langkah 4 — Buat File `.env`

```bash
cp docker/.env.example docker/.env
```

Generate `APP_KEY` dan `JWT_SECRET`:

```bash
# APP_KEY
echo "base64:$(openssl rand -base64 32)"
# Contoh output: base64:AbCdEfGhIjKlMnOpQrStUvWxYz012345678=

# JWT_SECRET
openssl rand -hex 64
# Contoh output: a1b2c3d4e5f6... (panjang 128 karakter)
```

Salin kedua nilai di atas, lalu edit `.env`:

```bash
nano docker/.env
```

Isi `.env` dengan nilai berikut (sesuaikan dengan `terraform output` dari Section 3):

```env
# ── App ──────────────────────────────────────
APP_KEY=base64:...        ← ambil dari docker/.env.example
JWT_SECRET=...            ← ambil dari docker/.env.example
APP_PORT=80
APP_URL=http://<alb_dns_name>      ← dari terraform output alb_dns_name
APP_ENV=production
APP_DEBUG=false

# ── Database (RDS) ───────────────────────────
DB_CONNECTION=mysql
DB_HOST=<rds_endpoint>            ← dari terraform output rds_endpoint
DB_PORT=3306
DB_DATABASE=kaltim_smart_platform
DB_USERNAME=kaltim_admin
DB_PASSWORD=K4lt1m#Secure2026!
DB_ROOT_PASSWORD=K4lt1m#Secure2026!

# ── Redis (ElastiCache) ──────────────────────
REDIS_HOST=<redis_endpoint>       ← dari terraform output redis_endpoint
REDIS_PORT=6379
CACHE_STORE=redis
SESSION_DRIVER=redis
QUEUE_CONNECTION=redis

# ── S3 + CloudFront ──────────────────────────
AWS_DEFAULT_REGION=ap-southeast-1
AWS_BUCKET=<s3_bucket_name>       ← dari terraform output s3_bucket_name
AWS_URL=<cloudfront_domain>       ← dari terraform output cloudfront_domain
FILESYSTEM_DISK=s3

# ── Amazon Lex ───────────────────────────────
AWS_LEX_BOT_ID=<lex_bot_id>       ← dari terraform output lex_bot_id
AWS_LEX_BOT_ALIAS_ID=             ← kosong dulu, diisi setelah Section 6
```

> Simpan dengan `Ctrl+O → Enter → Ctrl+X`.

### Langkah 5 — Jalankan Aplikasi

```bash
cd /opt/kaltim-app
docker compose -f docker/docker-compose.yml up -d --build
```

Build pertama kali memakan waktu **5–10 menit**. Pantau progressnya:

```bash
docker compose -f docker/docker-compose.yml logs -f
```

Setelah selesai, cek status container:

```bash
docker compose -f docker/docker-compose.yml ps
```

Semua container harus `Up`:
```
kaltim-app     Up
kaltim-nginx   Up
```

> Container `db` dan `cache` tidak akan muncul karena sudah menggunakan RDS dan ElastiCache.

### Langkah 6 — Verifikasi Health Check

Buka browser: `http://<alb_dns_name>/health`

Harus tampil **All Systems Operational** dengan database, cache, dan storage OK.

> Jika belum muncul, ALB perlu waktu 1–2 menit untuk register instance ke target group.

---

## 6. Setup Amazon Lex (Chatbot)

> Bot dan semua intent sudah dibuat otomatis oleh Terraform. Yang perlu dilakukan manual: **Build** dan **buat alias**.

### Langkah 1 — Build Bot

1. Buka **AWS Console → Amazon Lex → Bots**
2. Klik bot **kaltim-smart-platform-chatbot**
3. Pilih language **English (en_US)** — bot menggunakan locale ini karena `id_ID` tidak mendukung custom intent
4. Klik tombol **Build** → tunggu ~2 menit hingga status **Built**

### Langkah 2 — Buat Alias

1. Di halaman bot, klik **Deployments → Aliases → Create alias**
2. Alias name: `prod`
3. Bot version: pilih versi dari `lex_bot_version` (terraform output) → **Create**

### Langkah 3 — Ambil Alias ID

1. Klik alias `prod` yang baru dibuat
2. Catat **Alias ID** (format: `XXXXXXXXXX`)

### Langkah 4 — Update `.env` di EC2

Kembali ke Session Manager, lalu:

```bash
nano /opt/kaltim-app/docker/.env
# Isi baris AWS_LEX_BOT_ALIAS_ID dengan Alias ID dari langkah di atas
```

Restart app container:

```bash
docker compose -f /opt/kaltim-app/docker/docker-compose.yml up -d --force-recreate app
```

Test chatbot:
```bash
curl -X POST http://<alb_dns_name>/api/chatbot \
  -H "Content-Type: application/json" \
  -d '{"message": "cara buat KTP"}'
# Harus ada reply dari Lex, bukan fallback
```

---

## 7. Buat AMI dari EC2

> AMI = foto snapshot EC2 yang sudah jadi. Kalau instance mati atau Auto Scaling ganti instance baru, instance baru langsung boot dari AMI ini — sudah ada Docker, repo, dan `.env`.

### Langkah 1 — Pastikan Semua Sudah Jalan

Sebelum buat AMI, verifikasi:
- [ ] `http://<alb_dns_name>/health` → All Systems Operational
- [ ] Login admin dan warga berhasil
- [ ] Chatbot Lex aktif (ada reply dari Lex)
- [ ] Upload file berhasil dan URL-nya menggunakan `cloudfront.net`

### Langkah 2 — Buat AMI

1. Buka **AWS Console → EC2 → Instances**
2. Pilih instance `kaltim-app-instance`
3. Klik **Actions → Image and templates → Create image**
4. Isi:
   - **Image name:** `kaltim-smart-platform-ami`
   - **Description:** `Kaltim Smart Platform - Docker + app configured`
   - **No reboot:** centang ✓ (agar instance tidak restart)
5. Klik **Create image**
6. Tunggu status AMI menjadi **Available** (~5 menit) di **EC2 → AMIs**
7. **Catat AMI ID** (format: `ami-xxxxxxxxxxxxxxxxx`)

---

## 8. Setup Auto Scaling Group

Buat Launch Template dan Auto Scaling Group via AWS Console menggunakan AMI yang baru dibuat.

### Langkah 1 — Buat Launch Template

1. Buka **EC2 → Launch Templates → Create launch template**

2. Isi:

   | Setting | Nilai |
   |---|---|
   | **Launch template name** | `kaltim-smart-platform-lt` |
   | **AMI** | AMI ID dari Section 7 (`ami-xxxxxxxxx`) |
   | **Instance type** | `t3.medium` |
   | **Key pair** | pilih yang ada (opsional) |

3. **Network settings:**
   - **Security groups:** pilih `kaltim-smart-platform-app-sg`

4. **Advanced details:**
   - **IAM instance profile:** `kaltim-smart-platform-ec2-profile`
   - **Metadata version:** pilih `V2 only (token required)`
   - **Metadata response hop limit:** `2` ← **penting** agar Docker bisa akses IAM role

5. Klik **Create launch template**

### Langkah 2 — Buat Auto Scaling Group

1. Buka **EC2 → Auto Scaling Groups → Create Auto Scaling group**

2. **Step 1 — Name and template:**
   - Name: `kaltim-smart-platform-asg`
   - Launch template: pilih `kaltim-smart-platform-lt`

3. **Step 2 — Network:**
   - VPC: `kaltim-smart-platform-vpc`
   - Availability Zones: pilih kedua subnet dari `app_private_subnet_id` (AZ1 dan AZ2)

4. **Step 3 — Load balancing:**
   - Pilih **Attach to an existing load balancer**
   - Pilih **Choose from your load balancer target groups**
   - Target group: `kaltim-smart-platform-tg`
   - Health check: centang **Turn on Elastic Load Balancing health checks**

5. **Step 4 — Group size:**
   - Desired: `1`
   - Minimum: `1`
   - Maximum: `2`

6. **Step 5 — Scaling policies:** pilih **No scaling policies** (opsional, bisa tambah nanti)

7. Review → **Create Auto Scaling group**

### Langkah 3 — Verifikasi

1. Buka **EC2 → Auto Scaling Groups → `kaltim-smart-platform-asg`**
2. Tab **Instance management** → tunggu instance status **InService**
3. Buka ALB DNS: `http://<alb_dns_name>/health` — harus tetap **All Systems Operational**

---

## 9. Cek & Test Aplikasi

### Health Check

```bash
curl http://<alb_dns_name>/health
# Tampilkan: All Systems Operational

curl http://<alb_dns_name>/api/health
# Return: {"success":true,"message":"All systems operational"}
```

### Test Upload & CloudFront

1. Login sebagai warga → buat laporan → upload foto
2. Cek bahwa URL foto di response menggunakan `cloudfront.net`

```
https://xxxxxx.cloudfront.net/storage/uploads/reports/namafile.jpg ✅
```

> Kalau masih pakai URL ALB atau path `/storage/...`, cek `FILESYSTEM_DISK=s3` dan `AWS_URL` di `.env`.

### Test API via curl

```bash
# Login admin
curl -X POST http://<alb_dns_name>/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"admin@kaltim.go.id","password":"password"}'

# Gunakan token dari response:
curl http://<alb_dns_name>/api/dashboard/stats \
  -H "Authorization: Bearer <token>"
```

### Test Chatbot

```bash
curl -X POST http://<alb_dns_name>/api/chatbot \
  -H "Content-Type: application/json" \
  -d '{"message": "cara buat KTP"}'
# Reply harus berisi instruksi pembuatan KTP (dari Lex, bukan fallback)
```

---

## 10. Monitoring

### Lihat Log Aplikasi

Akses EC2 via Session Manager, lalu:

```bash
sudo docker compose -f /opt/kaltim-app/docker/docker-compose.yml logs app -f
```

### CloudWatch di AWS Console

- **EC2:** AWS Console → EC2 → Auto Scaling Groups → tab Monitoring
- **RDS:** AWS Console → RDS → Databases → tab Monitoring
- **ALB:** AWS Console → EC2 → Load Balancers → tab Monitoring

Metrik penting: CPU Utilization, Database Connections, Request Count, Response Time.

---

## 11. Arsitektur AWS

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
  ├── App Subnets:     10.0.10.0/24, 10.0.11.0/24  (EC2 + ASG)
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

## 12. Pengujian Mandiri dengan Postman

### Setup Postman

1. Buat **New Collection** → nama: `Kaltim Smart Platform`
2. Tambah **Collection Variables**:
   - `base_url` → `http://<alb_dns_name>`
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
✅ File tampil di browser
✅ URL mengandung "cloudfront.net" bukan "s3.amazonaws.com"
```

---

### F. Test Health Check

**Web Health (browser):**
```
Buka: http://<alb_dns_name>/health
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
Buka http://<alb_dns_name> → klik 💬 → ketik: "cara buat ktp"
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

## 13. Checklist Pengumpulan

> Deadline: **pukul 17.00 WITA**

### Yang harus dikumpulkan:

- [ ] **URL Live** — `http://<alb_dns_name>` aktif dan bisa diakses
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

### Update README.md sebelum kumpul:

```markdown
## Deployment Live
- **URL:** http://<alb_dns_name>
- **Health Check:** http://<alb_dns_name>/health
- **API Docs:** http://<alb_dns_name>/api-info
```

---

## Perkiraan Biaya Bulanan

| Layanan | Spesifikasi | Estimasi |
|---|---|---|
| EC2 | 1–2x t3.medium | ~$30–60 |
| RDS | db.t3.micro | ~$15 |
| ElastiCache | cache.t3.micro | ~$12 |
| ALB | 1 | ~$20 |
| NAT Gateway | 1 | ~$32 |
| S3 | 1 GB | ~$0.02 |
| CloudFront | ~100 GB transfer | ~$8 |
| Lex | ~1000 req/hari | ~$5 |
| **Total** | | **~$122–152/bulan** |
