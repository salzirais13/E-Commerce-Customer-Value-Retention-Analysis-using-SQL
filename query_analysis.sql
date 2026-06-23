-- 1. Hapus tabel lama (jika ada) biar bersih
DROP TABLE IF EXISTS olist_customers;
DROP TABLE IF EXISTS olist_orders;
DROP TABLE IF EXISTS olist_payments;

-- 2. Buat Tabel Customer (Sesuai olist_customers_dataset.csv)
CREATE TABLE olist_customers (
    customer_id VARCHAR(500),
    customer_unique_id VARCHAR(500),
    customer_zip_code_prefix VARCHAR(500),
    customer_city VARCHAR(500),
    customer_state VARCHAR(500)
);

-- 3. Buat Tabel Orders (Sesuai olist_orders_dataset.csv)
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

-- 4. Buat Tabel Payments (Sesuai olist_order_payments_dataset.csv)
CREATE TABLE olist_payments (
    order_id VARCHAR(500),
    payment_sequential VARCHAR(500),
    payment_type VARCHAR(500),
    payment_installments VARCHAR(500),
    payment_value VARCHAR(500)
);

SELECT * FROM olist_customers LIMIT 5;

CREATE OR REPLACE VIEW v_ecommerce_clean AS
SELECT 
    c.customer_unique_id,
    o.order_id,
    o.order_status,
    -- 1. Mengubah teks menjadi format TANGGAL & WAKTU resmi
    CAST(o.order_purchase_timestamp AS TIMESTAMP) AS order_date,
    -- 2. Mengubah teks menjadi format ANGKA DESIMAL untuk uang
    CAST(p.payment_value AS NUMERIC) AS total_payment
FROM olist_orders o
JOIN olist_customers c ON o.customer_id = c.customer_id
JOIN olist_payments p ON o.order_id = p.order_id
-- 3. Filter Bisnis: Hanya ambil pesanan yang sukses terkirim ke pelanggan
WHERE o.order_status = 'delivered';

SELECT * FROM v_ecommerce_clean LIMIT 10;

-- mulai frm --
WITH rfm_base AS (
    -- Menghitung nilai dasar Recency, Frequency, dan Monetary per pelanggan
    SELECT
        customer_unique_id,
        -- Recency: Selisih hari antara tanggal terakhir di dataset dengan tanggal belanja terakhir user
        DATE_PART('day', (SELECT MAX(order_date) FROM v_ecommerce_clean) - MAX(order_date)) AS recency,
        -- Frequency: Jumlah pesanan unik
        COUNT(DISTINCT order_id) AS frequency,
        -- Monetary: Total uang yang dikeluarkan
        SUM(total_payment) AS monetary
    FROM v_ecommerce_clean
    GROUP BY customer_unique_id
),

rfm_scores AS (
    -- Memberikan skor 1-5 menggunakan NTILE (Kuantil)
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

-- Segmentasi Akhir berdasarkan skor R dan F
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

--cohort analysis--
WITH cohort_birth AS (
    -- LANGKAH 1: Cari bulan pertama kali setiap pelanggan melakukan transaksi (Sudah diperbaiki pakai MIN)
    SELECT
        customer_unique_id,
        DATE_TRUNC('month', MIN(order_date)) AS cohort_month
    FROM v_ecommerce_clean
    GROUP BY customer_unique_id
),

customer_activities AS (
    -- LANGKAH 2: Ambil semua bulan transaksi pelanggan dan pasangkan dengan bulan pertama mereka belanja
    SELECT
        v.customer_unique_id,
        c.cohort_month,
        DATE_TRUNC('month', v.order_date) AS activity_month
    FROM v_ecommerce_clean v
    JOIN cohort_birth c ON v.customer_unique_id = c.customer_unique_id
),

cohort_sizes AS (
    -- LANGKAH 3: Hitung total pelanggan unik yang "lahir" di masing-masing Cohort Month
    SELECT
        cohort_month,
        COUNT(DISTINCT customer_unique_id) AS total_customers
    FROM cohort_birth
    GROUP BY cohort_month
),

retention_counts AS (
    -- LANGKAH 4: Hitung selisih bulan (jarak) antara bulan pertama belanja dengan bulan belanja berikutnya
    SELECT
        cohort_month,
        (DATE_PART('year', activity_month) - DATE_PART('year', cohort_month)) * 12 +
        (DATE_PART('month', activity_month) - DATE_PART('month', cohort_month)) AS period_month,
        COUNT(DISTINCT customer_unique_id) AS retained_customers
    FROM customer_activities
    GROUP BY cohort_month, period_month
)

-- LANGKAH 5: Pivot hasilnya ke samping agar membentuk tabel matriks yang rapi
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
