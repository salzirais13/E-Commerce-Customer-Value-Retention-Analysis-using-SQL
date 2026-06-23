# E-Commerce Customer Value & Retention Analysis using SQL

Proyek ini berfokus pada analisis perilaku pelanggan (*Customer Behavior*) menggunakan data transaksi riil dari platform e-commerce Olist (Brasil). Pendekatan yang digunakan adalah **Segmentasi RFM (Recency, Frequency, Monetary)** untuk memahami nilai kontribusi pelanggan saat ini, serta **Cohort Analysis** untuk mengevaluasi tingkat retensi (kesetiaan) pelanggan dari bulan ke bulan.

---

## 1. Latar Belakang & Problem Statement

Di industri e-commerce, biaya untuk mendapatkan pelanggan baru (*Customer Acquisition Cost* atau CAC) cenderung terus meningkat. Oleh karena itu, mengoptimalkan interaksi dengan pelanggan yang sudah ada untuk meningkatkan *Customer Lifetime Value* (LTV) menjadi sangat krusial.

**Problem Statement:**
* Perusahaan tidak memiliki visibilitas terhadap pengelompokan pelanggan berdasarkan kontribusi finansial dan keaktifan mereka.
* Perusahaan mendeteksi adanya indikasi penurunan jumlah pelanggan aktif namun belum tahu secara pasti seberapa ekstrem pelanggan cenderung berhenti berbelanja (*churn*).

**Tujuan Proyek:**
1. Mengelompokkan pelanggan ke dalam segmen perilaku yang jelas (seperti *Champions*, *Loyal*, *At Risk*) menggunakan metode RFM berbasis kuantil.
2. Melacak metrik retensi bulanan menggunakan analisis kohort untuk mengetahui seberapa cepat pelanggan meninggalkan platform.
3. Menghasilkan rekomendasi strategi pemasaran berbasis data (*data-driven marketing*) untuk meningkatkan retensi.

---

## 2. Dataset & Hubungan Data (ERD)

Dataset yang digunakan berasal dari data publik Olist di Kaggle. Proyek ini menghubungkan tiga tabel utama:
* **`olist_customers`**: Menyediakan `customer_unique_id` (identitas asli unik pelanggan yang tidak berubah lintas transaksi).
* **`olist_orders`**: Menyediakan waktu pembelian (`order_purchase_timestamp`) dan status akhir transaksi (`order_status`).
* **`olist_payments`**: Menyediakan nilai total uang yang dibayarkan per transaksi (`payment_value`).

---

## 3. Implementasi SQL (Step-by-Step)

### Langkah 3.1: Data Ingestion (Membuat Tabel Kosong)
Untuk memastikan seluruh data dari file CSV masuk tanpa terkendala kesalahan format atau nilai kosong (*null*), semua kolom diimpor sebagai tipe teks (`VARCHAR`) terlebih dahulu.

```sql
-- 1. Wadah untuk olist_customers_dataset.csv
CREATE TABLE olist_customers (
    customer_id VARCHAR(500),
    customer_unique_id VARCHAR(500),
    customer_zip_code_prefix VARCHAR(500),
    customer_city VARCHAR(500),
    customer_state VARCHAR(500)
);

-- 2. Wadah untuk olist_orders_dataset.csv
CREATE TABLE olist_orders (
    order_id VARCHAR(500),
    customer_id VARCHAR(500),
    order_status VARCHAR(500),
    order_purchase_timestamp VARCHAR(500),
    order_approved_at VARCHAR(500),
    order_delivered_carrier_date VARCHAR(500),
    order_delivered_customer_date VARCHAR(500),
    order_estimated_delivery_date VARCHAR(500)
);

-- 3. Wadah untuk olist_order_payments_dataset.csv
CREATE TABLE olist_payments (
    order_id VARCHAR(500),
    payment_sequential VARCHAR(500),
    payment_type VARCHAR(500),
    payment_installments VARCHAR(500),
    payment_value VARCHAR(500)
);
```

### Langkah 3.2: Data Cleaning & Transformasi (Pembuatan View)
Menggabungkan ketiga tabel utama, menyaring data hanya untuk pesanan yang berhasil sampai ke pelanggan (`delivered`), serta mengubah format teks menjadi tipe `TIMESTAMP` dan `NUMERIC`.

```sql
CREATE OR REPLACE VIEW v_ecommerce_clean AS
SELECT 
    c.customer_unique_id,
    o.order_id,
    o.order_status,
    CAST(o.order_purchase_timestamp AS TIMESTAMP) AS order_date,
    CAST(p.payment_value AS NUMERIC) AS total_payment
FROM olist_orders o
JOIN olist_customers c ON o.customer_id = c.customer_id
JOIN olist_payments p ON o.order_id = p.order_id
WHERE o.order_status = 'delivered';
```

### Langkah 3.3: Segmentasi Pelanggan Menggunakan RFM
Query di bawah ini merangkum nilai transaksi per pelanggan, memberikan skor kuantil 1 hingga 5 (`NTILE(5)`), dan mengelompokkannya ke dalam beberapa segmen bisnis utama.

```sql
WITH rfm_base AS (
    SELECT
        customer_unique_id,
        DATE_PART('day', (SELECT MAX(order_date) FROM v_ecommerce_clean) - MAX(order_date)) AS recency,
        COUNT(DISTINCT order_id) AS frequency,
        SUM(total_payment) AS monetary
    FROM v_ecommerce_clean
    GROUP BY customer_unique_id
),
rfm_scores AS (
    SELECT
        customer_unique_id,
        recency,
        frequency,
        monetary,
        NTILE(5) OVER (ORDER BY recency DESC) AS r_score,
        NTILE(5) OVER (ORDER BY frequency ASC) AS f_score,
        NTILE(5) OVER (ORDER BY monetary ASC) AS m_score
    FROM rfm_base
)
SELECT
    customer_unique_id,
    recency,
    frequency,
    monetary,
    r_score,
    f_score,
    m_score,
    CASE
        WHEN r_score >= 4 AND f_score >= 4 THEN 'Champions (Pelanggan Terbaik)'
        WHEN r_score >= 3 AND f_score >= 3 THEN 'Loyal Customers'
        WHEN r_score >= 4 AND f_score <= 2 THEN 'New / Recent Customers'
        WHEN r_score <= 2 AND f_score >= 3 THEN 'At Risk / Can''t Lose Them'
        WHEN r_score <= 2 AND f_score <= 2 THEN 'Lost / Hibernating'
        ELSE 'About to Sleep / General'
    END AS customer_segment
FROM rfm_scores
ORDER BY monetary DESC;
```

### Langkah 3.4: Analisis Kohort Retensi Bulanan
Query ini melacak bulan pertama kali tiap pelanggan bertransaksi (*Cohort Birth Month*) dan mengukur aktivitas belanja kembali mereka pada bulan pertama hingga bulan keenam berikutnya.

```sql
WITH cohort_birth AS (
    SELECT
        customer_unique_id,
        DATE_TRUNC('month', MIN(order_date)) AS cohort_month
    FROM v_ecommerce_clean
    GROUP BY customer_unique_id
),
customer_activities AS (
    SELECT
        v.customer_unique_id,
        c.cohort_month,
        DATE_TRUNC('month', v.order_date) AS activity_month
    FROM v_ecommerce_clean v
    JOIN cohort_birth c ON v.customer_unique_id = c.customer_unique_id
),
cohort_sizes AS (
    SELECT
        cohort_month,
        COUNT(DISTINCT customer_unique_id) AS total_customers
    FROM cohort_birth
    GROUP BY cohort_month
),
retention_counts AS (
    SELECT
        cohort_month,
        (DATE_PART('year', activity_month) - DATE_PART('year', cohort_month)) * 12 +
        (DATE_PART('month', activity_month) - DATE_PART('month', cohort_month)) AS period_month,
        COUNT(DISTINCT customer_unique_id) AS retained_customers
    FROM customer_activities
    GROUP BY cohort_month, period_month
)
SELECT
    r.cohort_month,
    s.total_customers AS month_0_awal,
    MAX(CASE WHEN r.period_month = 1 THEN r.retained_customers ELSE 0 END) AS month_1,
    MAX(CASE WHEN r.period_month = 2 THEN r.retained_customers ELSE 0 END) AS month_2,
    MAX(CASE WHEN r.period_month = 3 THEN r.retained_customers ELSE 0 END) AS month_3,
    MAX(CASE WHEN r.period_month = 4 THEN r.retained_customers ELSE 0 END) AS month_4,
    MAX(CASE WHEN r.period_month = 5 THEN r.retained_customers ELSE 0 END) AS month_5,
    MAX(CASE WHEN r.period_month = 6 THEN r.retained_customers ELSE 0 END) AS month_6
FROM retention_counts r
JOIN cohort_sizes s ON r.cohort_month = s.cohort_month
GROUP BY r.cohort_month, s.total_customers
ORDER BY r.cohort_month;
```

---

## 4. Temuan Utama (Key Insights Berdasarkan Data Riil)

### A. Analisis Distribusi Segmen RFM
Berdasarkan data riil yang diproses dari `olist_rfm_segments.csv`, didapatkan fakta-fakta kritis berikut:
* **Goldmine di Segmen "At Risk / Can't Lose Them":** Kelompok ini berjumlah **21.868 pelanggan (23,42% dari total user)** namun menyumbang kontribusi pendapatan terbesar bagi perusahaan, yaitu mencapai **34,34% dari total revenue ($5.296.571,39)**. Kelompok ini adalah pelanggan berharga tinggi yang sudah lama tidak aktif berbelanja.
* **Inti Bisnis (Champions & Loyal):** Kombinasi segmen *Champions* (16,42% user) dan *Loyal Customers* (20,16% user) menguasai total **52,28% dari seluruh perputaran uang** di platform. Menjaga kedua kelompok ini tetap bahagia adalah harga mati bagi stabilitas finansial perusahaan.

### B. Analisis Retensi (Cohort Retention Matrix)
Analisis mendalam dari file `olist_cohort_retention.csv` menunjukkan sebuah anomali bisnis yang sangat besar:
* **Krisis Akut One-Time Buyers:** Dari total akumulasi **93.357 pelanggan unik** lintas waktu, tingkat retensi pada bulan pertama setelah pembelian (`Month 1`) langsung anjlok drastis ke angka **0,45% (Hanya 421 pelanggan yang kembali)**.
* **Tren Akhir (Month 6):** Kesetiaan pelanggan terus terkikis hingga tersisa **0,14% (129 pelanggan)** pada bulan keenam. Fakta ini membuktikan bahwa pertumbuhan bisnis Olist murni ditopang oleh bakar duit pemasaran untuk menjaring pengguna baru (*New User Acquisition*), bukan karena loyalitas organik pelanggan.

---

## 5. Rekomendasi Strategi Bisnis

| Nama Segmen / Kasus | Karakteristik Data Riil | Strategi Tindakan Bisnis (*Data-Driven Marketing*) |
| :--- | :--- | :--- |
| **At Risk / Can't Lose Them** | 23,42% Populasi, **34,34% Revenue** | **Fokus Utama:** Alokasikan sebagian besar *budget* pemasaran untuk mengaktifkan kembali segmen ini lewat kampanye pemulihan (*win-back*) via email/WhatsApp bertarget tinggi menggunakan penawaran potongan harga agresif yang bersifat personal. |
| **Champions** | 16,42% Populasi, **30,09% Revenue** | Jaga kepuasan mereka lewat program keanggotaan eksklusif (*VIP Program*), berikan akses lebih cepat untuk peluncuran produk baru, dan manfaatkan testimoni mereka untuk program referal. |
| **Krisis Retensi Kohort** | `Month 1` langsung drop ke **0,45%** | **Perbaikan Sistemik:** Lakukan audit kepuasan pelanggan pasca-pembelian pertama. Masalah kemungkinan besar ada pada durasi pengiriman logistik Brasil yang lama atau kualitas barang. Buat program otomatisasi pemberian voucher belanja kedua (*Next Purchase Coupon*) yang berlaku 14–30 hari setelah pesanan pertama selesai diterima. |
