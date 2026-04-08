-- 007_media_api.sql
-- Media streaming package used by APEX on-demand application processes.
-- This script externalizes image/blob streaming from page/app process SQL.

CREATE OR REPLACE PACKAGE sufioun_media_api AS
  PROCEDURE emp_photo;
  PROCEDURE emp_photo(p_employee_id IN sufioun_employees.employee_id%TYPE);
  PROCEDURE brand_logo;
  PROCEDURE brand_logo(p_brand_id IN sufioun_brand.brand_id%TYPE);
  PROCEDURE supplier_logo;
  PROCEDURE supplier_logo(p_supplier_id IN sufioun_suppliers.supplier_id%TYPE);
  PROCEDURE product_image;
  PROCEDURE product_image(p_product_id IN sufioun_products.product_id%TYPE);
  PROCEDURE stream_blob(
    p_table_name  IN VARCHAR2,
    p_pk_value    IN VARCHAR2,
    p_blob_column IN VARCHAR2 DEFAULT NULL,
    p_mime_column IN VARCHAR2 DEFAULT NULL,
    p_pk_column   IN VARCHAR2 DEFAULT NULL
  );
END sufioun_media_api;
/

CREATE OR REPLACE PACKAGE BODY sufioun_media_api AS
  FUNCTION one_px_png RETURN BLOB IS
    l_blob BLOB;
    l_raw  RAW(32767);
  BEGIN
    l_raw := HEXTORAW('89504E470D0A1A0A0000000D49484452000000010000000108060000001F15C4890000000A49444154789C6360000002000154A24F5D0000000049454E44AE426082');
    DBMS_LOB.CREATETEMPORARY(l_blob, TRUE);
    DBMS_LOB.WRITEAPPEND(l_blob, UTL_RAW.LENGTH(l_raw), l_raw);
    RETURN l_blob;
  END one_px_png;

  FUNCTION has_column(
    p_table_name  IN VARCHAR2,
    p_column_name IN VARCHAR2
  ) RETURN BOOLEAN IS
    l_cnt NUMBER;
  BEGIN
    SELECT COUNT(*)
      INTO l_cnt
      FROM user_tab_columns
     WHERE table_name = UPPER(TRIM(p_table_name))
       AND column_name = UPPER(TRIM(p_column_name));
    RETURN l_cnt > 0;
  END has_column;

  FUNCTION resolve_pk_column(
    p_table_name IN VARCHAR2,
    p_pk_column  IN VARCHAR2
  ) RETURN VARCHAR2 IS
    l_pk_col VARCHAR2(128);
  BEGIN
    IF p_pk_column IS NOT NULL THEN
      l_pk_col := UPPER(TRIM(p_pk_column));
      IF NOT has_column(p_table_name, l_pk_col) THEN
        RAISE_APPLICATION_ERROR(-20014, 'Invalid PK column for table ' || UPPER(TRIM(p_table_name)));
      END IF;
      RETURN l_pk_col;
    END IF;

    SELECT cc.column_name
      INTO l_pk_col
      FROM user_constraints c
      JOIN user_cons_columns cc
        ON cc.constraint_name = c.constraint_name
       AND cc.table_name = c.table_name
     WHERE c.table_name = UPPER(TRIM(p_table_name))
       AND c.constraint_type = 'P'
       AND cc.position = 1;

    RETURN l_pk_col;
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      RAISE_APPLICATION_ERROR(-20015, 'Primary key column not found for table ' || UPPER(TRIM(p_table_name)));
  END resolve_pk_column;

  PROCEDURE emit_blob(
    p_blob     IN BLOB,
    p_mimetype IN VARCHAR2
  ) IS
    l_blob BLOB;
  BEGIN
    l_blob := p_blob;
    SYS.HTP.INIT;
    OWA_UTIL.MIME_HEADER(NVL(p_mimetype, 'image/jpeg'), FALSE);
    HTP.P('Cache-Control: no-store');
    OWA_UTIL.HTTP_HEADER_CLOSE;
    WPG_DOCLOAD.DOWNLOAD_FILE(l_blob);
  END emit_blob;

  PROCEDURE stream_blob(
    p_table_name  IN VARCHAR2,
    p_pk_value    IN VARCHAR2,
    p_blob_column IN VARCHAR2 DEFAULT NULL,
    p_mime_column IN VARCHAR2 DEFAULT NULL,
    p_pk_column   IN VARCHAR2 DEFAULT NULL
  ) IS
    l_table_name VARCHAR2(128);
    l_blob_col   VARCHAR2(128);
    l_mime_col   VARCHAR2(128);
    l_pk_col     VARCHAR2(128);
    l_sql        VARCHAR2(32767);
    l_photo      BLOB;
    l_mimetype   VARCHAR2(100);
    l_exists     NUMBER;
  BEGIN
    l_table_name := UPPER(TRIM(p_table_name));

    IF l_table_name IS NULL OR l_table_name NOT LIKE 'SUFIOUN_%' THEN
      RAISE_APPLICATION_ERROR(-20010, 'Invalid table name for media streaming');
    END IF;

    SELECT COUNT(*)
      INTO l_exists
      FROM user_tables
     WHERE table_name = l_table_name;

    IF l_exists = 0 THEN
      RAISE_APPLICATION_ERROR(-20011, 'Table not found: ' || l_table_name);
    END IF;

    IF p_blob_column IS NOT NULL THEN
      l_blob_col := UPPER(TRIM(p_blob_column));
    ELSIF has_column(l_table_name, 'PHOTO') THEN
      l_blob_col := 'PHOTO';
    ELSIF has_column(l_table_name, 'IMAGE_BLOB') THEN
      l_blob_col := 'IMAGE_BLOB';
    ELSE
      RAISE_APPLICATION_ERROR(-20012, 'No BLOB column found for table ' || l_table_name);
    END IF;

    IF NOT has_column(l_table_name, l_blob_col) THEN
      RAISE_APPLICATION_ERROR(-20013, 'Invalid BLOB column for table ' || l_table_name);
    END IF;

    IF p_mime_column IS NOT NULL THEN
      l_mime_col := UPPER(TRIM(p_mime_column));
      IF NOT has_column(l_table_name, l_mime_col) THEN
        l_mime_col := NULL;
      END IF;
    ELSIF has_column(l_table_name, 'IMAGE_MIME_TYPE') THEN
      l_mime_col := 'IMAGE_MIME_TYPE';
    ELSE
      l_mime_col := NULL;
    END IF;

    l_pk_col := resolve_pk_column(l_table_name, p_pk_column);

    l_sql := 'SELECT ' || DBMS_ASSERT.SIMPLE_SQL_NAME(l_blob_col) ||
             ', ' || CASE
                       WHEN l_mime_col IS NOT NULL THEN DBMS_ASSERT.SIMPLE_SQL_NAME(l_mime_col)
                       ELSE 'CAST(NULL AS VARCHAR2(100))'
                     END ||
             ' FROM ' || DBMS_ASSERT.SIMPLE_SQL_NAME(l_table_name) ||
             ' WHERE ' || DBMS_ASSERT.SIMPLE_SQL_NAME(l_pk_col) || ' = :1';

    BEGIN
      EXECUTE IMMEDIATE l_sql INTO l_photo, l_mimetype USING p_pk_value;
    EXCEPTION
      WHEN NO_DATA_FOUND THEN
        l_photo := one_px_png;
        l_mimetype := 'image/png';
    END;

    IF l_photo IS NULL THEN
      l_photo := one_px_png;
      l_mimetype := 'image/png';
    END IF;

    emit_blob(l_photo, NVL(l_mimetype, 'image/jpeg'));
  END stream_blob;

  PROCEDURE emp_photo IS
  BEGIN
    emp_photo(apex_application.g_x01);
  END emp_photo;

  PROCEDURE emp_photo(p_employee_id IN sufioun_employees.employee_id%TYPE) IS
  BEGIN
    stream_blob(
      p_table_name  => 'SUFIOUN_EMPLOYEES',
      p_pk_value    => p_employee_id,
      p_blob_column => 'PHOTO',
      p_mime_column => 'IMAGE_MIME_TYPE',
      p_pk_column   => 'EMPLOYEE_ID'
    );
  END emp_photo;

  PROCEDURE brand_logo IS
  BEGIN
    brand_logo(apex_application.g_x01);
  END brand_logo;

  PROCEDURE brand_logo(p_brand_id IN sufioun_brand.brand_id%TYPE) IS
  BEGIN
    stream_blob(
      p_table_name  => 'SUFIOUN_BRAND',
      p_pk_value    => p_brand_id,
      p_blob_column => 'IMAGE_BLOB',
      p_mime_column => 'IMAGE_MIME_TYPE',
      p_pk_column   => 'BRAND_ID'
    );
  END brand_logo;

  PROCEDURE supplier_logo IS
  BEGIN
    supplier_logo(apex_application.g_x01);
  END supplier_logo;

  PROCEDURE supplier_logo(p_supplier_id IN sufioun_suppliers.supplier_id%TYPE) IS
  BEGIN
    stream_blob(
      p_table_name  => 'SUFIOUN_SUPPLIERS',
      p_pk_value    => p_supplier_id,
      p_blob_column => 'IMAGE_BLOB',
      p_mime_column => 'IMAGE_MIME_TYPE',
      p_pk_column   => 'SUPPLIER_ID'
    );
  END supplier_logo;

  PROCEDURE product_image IS
  BEGIN
    product_image(apex_application.g_x01);
  END product_image;

  PROCEDURE product_image(p_product_id IN sufioun_products.product_id%TYPE) IS
  BEGIN
    stream_blob(
      p_table_name  => 'SUFIOUN_PRODUCTS',
      p_pk_value    => p_product_id,
      p_blob_column => 'IMAGE_BLOB',
      p_mime_column => 'IMAGE_MIME_TYPE',
      p_pk_column   => 'PRODUCT_ID'
    );
  END product_image;
END sufioun_media_api;
/
