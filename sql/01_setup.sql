-- 1. Create Schema
DROP SCHEMA IF EXISTS olist CASCADE;
CREATE SCHEMA olist;

SELECT 'Schema olist created.' AS status;

-- 2. Create Tables

-- customer_unique_id is the stable per-person key; customer_id changes per order
CREATE TABLE olist.customers (
    customer_id              VARCHAR(32)  PRIMARY KEY,
    customer_unique_id       VARCHAR(32)  NOT NULL,
    customer_zip_code_prefix VARCHAR(10)  NOT NULL,
    customer_city            VARCHAR(100) NOT NULL,
    customer_state           CHAR(2)      NOT NULL
);

CREATE INDEX idx_customers_unique_id ON olist.customers (customer_unique_id);

CREATE TABLE olist.orders (
    order_id                      VARCHAR(32)  PRIMARY KEY,
    customer_id                   VARCHAR(32)  NOT NULL REFERENCES olist.customers(customer_id),
    order_status                  VARCHAR(20)  NOT NULL,
    order_purchase_timestamp      TIMESTAMP    NOT NULL,
    order_approved_at             TIMESTAMP,
    order_delivered_carrier_date  TIMESTAMP,
    order_delivered_customer_date TIMESTAMP,
    order_estimated_delivery_date TIMESTAMP
);

CREATE INDEX idx_orders_customer_id ON olist.orders (customer_id);
CREATE INDEX idx_orders_purchase_ts ON olist.orders (order_purchase_timestamp);

CREATE TABLE olist.products (
    product_id                 VARCHAR(32)  PRIMARY KEY,
    product_category_name      VARCHAR(100),
    product_name_lenght        INT,
    product_description_lenght INT,
    product_photos_qty         INT,
    product_weight_g           INT,
    product_length_cm          INT,
    product_height_cm          INT,
    product_width_cm           INT
);

CREATE TABLE olist.sellers (
    seller_id              VARCHAR(32)  PRIMARY KEY,
    seller_zip_code_prefix VARCHAR(10)  NOT NULL,
    seller_city            VARCHAR(100) NOT NULL,
    seller_state           CHAR(2)      NOT NULL
);

CREATE TABLE olist.order_items (
    order_id            VARCHAR(32)    NOT NULL REFERENCES olist.orders(order_id),
    order_item_id       INT            NOT NULL,
    product_id          VARCHAR(32)    NOT NULL REFERENCES olist.products(product_id),
    seller_id           VARCHAR(32)    NOT NULL REFERENCES olist.sellers(seller_id),
    shipping_limit_date TIMESTAMP      NOT NULL,
    price               NUMERIC(10,2)  NOT NULL,
    freight_value       NUMERIC(10,2)  NOT NULL,
    PRIMARY KEY (order_id, order_item_id)
);

CREATE INDEX idx_order_items_product_id ON olist.order_items (product_id);
CREATE INDEX idx_order_items_seller_id  ON olist.order_items (seller_id);

CREATE TABLE olist.order_payments (
    order_id             VARCHAR(32)    NOT NULL REFERENCES olist.orders(order_id),
    payment_sequential   INT            NOT NULL,
    payment_type         VARCHAR(30)    NOT NULL,
    payment_installments INT            NOT NULL,
    payment_value        NUMERIC(10,2)  NOT NULL
);

CREATE INDEX idx_order_payments_order_id ON olist.order_payments (order_id);

-- surrogate PK — review_id has ~814 real duplicates in the raw CSV
CREATE TABLE olist.order_reviews (
    review_pk               SERIAL       PRIMARY KEY,
    review_id               VARCHAR(32)  NOT NULL,
    order_id                VARCHAR(32)  NOT NULL REFERENCES olist.orders(order_id),
    review_score            INT          NOT NULL,
    review_comment_title    TEXT,
    review_comment_message  TEXT,
    review_creation_date    TIMESTAMP    NOT NULL,
    review_answer_timestamp TIMESTAMP    NOT NULL
);

CREATE INDEX idx_order_reviews_review_id ON olist.order_reviews (review_id);
CREATE INDEX idx_order_reviews_order_id  ON olist.order_reviews (order_id);

CREATE TABLE olist.product_category_translation (
    product_category_name         VARCHAR(100) PRIMARY KEY,
    product_category_name_english VARCHAR(100) NOT NULL
);

SELECT 'All tables created.' AS status;

-- 3. Load Data from CSVs

\COPY olist.customers (customer_id, customer_unique_id, customer_zip_code_prefix, customer_city, customer_state) FROM 'data/olist_customers_dataset.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8');
\COPY olist.products (product_id, product_category_name, product_name_lenght, product_description_lenght, product_photos_qty, product_weight_g, product_length_cm, product_height_cm, product_width_cm) FROM 'data/olist_products_dataset.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8');
\COPY olist.sellers (seller_id, seller_zip_code_prefix, seller_city, seller_state) FROM 'data/olist_sellers_dataset.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8');
\COPY olist.orders (order_id, customer_id, order_status, order_purchase_timestamp, order_approved_at, order_delivered_carrier_date, order_delivered_customer_date, order_estimated_delivery_date) FROM 'data/olist_orders_dataset.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8');
\COPY olist.order_items (order_id, order_item_id, product_id, seller_id, shipping_limit_date, price, freight_value) FROM 'data/olist_order_items_dataset.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8');
\COPY olist.order_payments (order_id, payment_sequential, payment_type, payment_installments, payment_value) FROM 'data/olist_order_payments_dataset.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8');
\COPY olist.order_reviews (review_id, order_id, review_score, review_comment_title, review_comment_message, review_creation_date, review_answer_timestamp) FROM 'data/olist_order_reviews_dataset.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8');
\COPY olist.product_category_translation (product_category_name, product_category_name_english) FROM 'data/product_category_name_translation.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8');

SELECT 'All data loaded.' AS status;

-- 4. Validate Row Counts
-- Expected counts (from actual CSV record counts):
--   customers:                   99,441
--   orders:                      99,441
--   order_items:                112,650
--   order_payments:             103,886
--   order_reviews:               99,224  (CSV has multiline comment fields;
--                                         raw line count is higher, but true
--                                         record count is 99,224)
--   products:                    32,951
--   sellers:                      3,095
--   product_category_translation:    71

SELECT 'Row count validation:' AS status;

SELECT
    'customers'                    AS table_name, COUNT(*) AS row_count, 99441  AS expected FROM olist.customers
UNION ALL SELECT
    'orders',                                     COUNT(*),              99441           FROM olist.orders
UNION ALL SELECT
    'order_items',                                COUNT(*),              112650          FROM olist.order_items
UNION ALL SELECT
    'order_payments',                             COUNT(*),              103886          FROM olist.order_payments
UNION ALL SELECT
    'order_reviews',                              COUNT(*),              99224           FROM olist.order_reviews
UNION ALL SELECT
    'products',                                   COUNT(*),              32951           FROM olist.products
UNION ALL SELECT
    'sellers',                                    COUNT(*),              3095            FROM olist.sellers
UNION ALL SELECT
    'product_category_translation',               COUNT(*),              71              FROM olist.product_category_translation
ORDER BY table_name;
