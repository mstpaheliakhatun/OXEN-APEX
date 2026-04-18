# Purchase Flow (Final): Purchase Order -> Purchase Receive -> Purchase Return

This document is the finalized implementation guide for the procurement transaction flow:

1. Purchase Order
2. Purchase Receive
3. Purchase Return

It captures the final schema logic, APEX process sequencing, trigger fixes, and known troubleshooting paths.

---

## 1) End-to-End Flow and Module Dependencies

### 1.1 Functional dependency chain

1. **Purchase Order** creates commercial intent (`SUFIOUN_PURCHASE_ORDER_MASTER` + `SUFIOUN_PURCHASE_ORDER_DETAILS`).
2. **Purchase Receive** records actual received quantities against PO (`SUFIOUN_PURCHASE_RECEIVE_MASTER` + `SUFIOUN_PURCHASE_RECEIVE_DETAILS`).
3. **Purchase Return** sends received stock back to supplier (`SUFIOUN_PURCHASE_RETURN_MASTER` + `SUFIOUN_PURCHASE_RETURN_DETAILS`).

### 1.2 Data dependency chain

1. Return depends on Receive (`RECEIVE_ID`).
2. Receive depends on Purchase Order (`ORDER_ID`).
3. All detail rows depend on valid `PRODUCT_ID` from `SUFIOUN_PRODUCTS`.
4. Supplier financial rollups depend on Receive/Return master totals.

### 1.3 Stock dependency chain

1. Receive detail insert/update increases stock.
2. Return detail insert/update decreases stock.
3. Product mismatch in return detail causes FK failure before stock trigger executes.

---

## 2) Practical Implementation Order (Do This Sequence)

1. Create/confirm core tables and FK relationships.
2. Create ID generation triggers (`*_BI` triggers + sequences).
3. Create/replace total recalculation triggers.
4. Create stock movement triggers.
5. Build APEX pages (Order -> Receive -> Return).
6. Add Return IG-to-collection sync DA and on-demand process.
7. Keep only one detail persistence process (after master DML) on Return page.
8. Run correction SQL for historical bad totals (one-time).
9. Run create/update regression checklist.

---

## 3) Finalized Database Logic (SQL/PLSQL)

### 3.1 Purchase Order detail total sync trigger (compound)

```sql
CREATE OR REPLACE TRIGGER sufioun_tri_total_price_compound
FOR INSERT OR UPDATE OR DELETE ON sufioun_purchase_order_details
COMPOUND TRIGGER
  TYPE t_order_id_list IS TABLE OF sufioun_purchase_order_details.order_id%TYPE INDEX BY PLS_INTEGER;
  v_order_ids t_order_id_list;

  AFTER EACH ROW IS
  BEGIN
    IF INSERTING OR UPDATING THEN
      v_order_ids(v_order_ids.COUNT + 1) := :NEW.order_id;
    ELSIF DELETING THEN
      v_order_ids(v_order_ids.COUNT + 1) := :OLD.order_id;
    END IF;
  END AFTER EACH ROW;

  AFTER STATEMENT IS
    v_total       NUMBER;
    v_grand_total NUMBER;
  BEGIN
    FOR i IN 1 .. v_order_ids.COUNT LOOP
      SELECT NVL(SUM(purchase_price * quantity), 0)
        INTO v_total
        FROM sufioun_purchase_order_details
       WHERE order_id = v_order_ids(i);

      v_grand_total := v_total + (v_total * 0.10);

      UPDATE sufioun_purchase_order_master
         SET total_amount = v_total,
             grand_total  = v_grand_total
       WHERE order_id = v_order_ids(i);
    END LOOP;
  END AFTER STATEMENT;
END sufioun_tri_total_price_compound;
/
```

### 3.2 Purchase Receive total sync trigger

```sql
CREATE OR REPLACE TRIGGER sufioun_tri_receive_total_amount
FOR INSERT OR UPDATE OR DELETE ON sufioun_purchase_receive_details
COMPOUND TRIGGER

  TYPE t_recv_ids IS TABLE OF VARCHAR2(50) INDEX BY VARCHAR2(50);
  g_recv_ids t_recv_ids;

  PROCEDURE add_recv_id(p_recv_id VARCHAR2) IS
  BEGIN
    IF p_recv_id IS NOT NULL THEN
      g_recv_ids(p_recv_id) := p_recv_id;
    END IF;
  END;

AFTER EACH ROW IS
BEGIN
  add_recv_id(:NEW.receive_id);
  add_recv_id(:OLD.receive_id);
END AFTER EACH ROW;

AFTER STATEMENT IS
  k       VARCHAR2(50);
  v_total NUMBER;
BEGIN
  k := g_recv_ids.FIRST;
  WHILE k IS NOT NULL LOOP
    SELECT NVL(SUM(d.purchase_price * d.receive_quantity), 0)
      INTO v_total
      FROM sufioun_purchase_receive_details d
     WHERE d.receive_id = k;

    UPDATE sufioun_purchase_receive_master m
       SET m.total_amount = v_total,
           m.grand_total  = v_total + (v_total * NVL(m.vat, 0) / 100)
     WHERE m.receive_id = k;

    k := g_recv_ids.NEXT(k);
  END LOOP;
END AFTER STATEMENT;

END sufioun_tri_receive_total_amount;
/
```

### 3.3 Purchase Return total sync trigger (final mutating-safe compound trigger)

> This is the final fix pattern for `ORA-04091` on return totals.

```sql
CREATE OR REPLACE TRIGGER sufioun_tri_ret_total_price
FOR INSERT OR UPDATE OR DELETE ON sufioun_purchase_return_details
COMPOUND TRIGGER

  TYPE t_ret_ids IS TABLE OF VARCHAR2(50) INDEX BY VARCHAR2(50);
  g_ret_ids t_ret_ids;

  PROCEDURE add_ret_id(p_ret_id VARCHAR2) IS
  BEGIN
    IF p_ret_id IS NOT NULL THEN
      g_ret_ids(p_ret_id) := p_ret_id;
    END IF;
  END;

AFTER EACH ROW IS
BEGIN
  add_ret_id(:NEW.return_id);
  add_ret_id(:OLD.return_id);
END AFTER EACH ROW;

AFTER STATEMENT IS
  k       VARCHAR2(50);
  v_total NUMBER;
  v_adj   NUMBER;
BEGIN
  k := g_ret_ids.FIRST;
  WHILE k IS NOT NULL LOOP
    SELECT NVL(SUM(NVL(d.line_total,0)),0)
      INTO v_total
      FROM sufioun_purchase_return_details d
     WHERE d.return_id = k;

    SELECT NVL(m.adjusted_vat,0)
      INTO v_adj
      FROM sufioun_purchase_return_master m
     WHERE m.return_id = k
     FOR UPDATE;

    UPDATE sufioun_purchase_return_master m
       SET m.total_amount = v_total,
           m.grand_total  = v_total + v_adj
     WHERE m.return_id = k;

    k := g_ret_ids.NEXT(k);
  END LOOP;
END AFTER STATEMENT;

END sufioun_tri_ret_total_price;
/
```

### 3.4 Return detail ID trigger (keep existing)

```sql
CREATE OR REPLACE TRIGGER sufioun_trg_prod_ret_det_bi
BEFORE INSERT ON sufioun_purchase_return_details
FOR EACH ROW
BEGIN
  IF :NEW.return_detail_id IS NULL THEN
    :NEW.return_detail_id := 'PRD-' || TO_CHAR(sufioun_prod_ret_det_seq.NEXTVAL);
  END IF;
END;
/
```

### 3.5 Stock movement triggers for receive/return

```sql
CREATE OR REPLACE TRIGGER sufioun_trg_auto_stock_receive
AFTER INSERT OR UPDATE OR DELETE ON sufioun_purchase_receive_details
FOR EACH ROW
BEGIN
  IF INSERTING THEN
    sufioun_update_stock_qty(:NEW.product_id, :NEW.receive_quantity);
  ELSIF DELETING THEN
    sufioun_update_stock_qty(:OLD.product_id, -:OLD.receive_quantity);
  ELSIF UPDATING THEN
    IF :OLD.product_id != :NEW.product_id THEN
      sufioun_update_stock_qty(:OLD.product_id, -:OLD.receive_quantity);
      sufioun_update_stock_qty(:NEW.product_id, :NEW.receive_quantity);
    ELSE
      sufioun_update_stock_qty(:NEW.product_id, :NEW.receive_quantity - :OLD.receive_quantity);
    END IF;
  END IF;
END;
/
```

```sql
CREATE OR REPLACE TRIGGER sufioun_trg_auto_stk_pur_ret
AFTER INSERT OR UPDATE OR DELETE ON sufioun_purchase_return_details
FOR EACH ROW
BEGIN
  IF INSERTING THEN
    sufioun_update_stock_qty(:NEW.product_id, -NVL(:NEW.return_quantity, 0));
  ELSIF DELETING THEN
    sufioun_update_stock_qty(:OLD.product_id, NVL(:OLD.return_quantity, 0));
  ELSIF UPDATING THEN
    IF :OLD.product_id != :NEW.product_id THEN
      sufioun_update_stock_qty(:OLD.product_id, NVL(:OLD.return_quantity, 0));
      sufioun_update_stock_qty(:NEW.product_id, -NVL(:NEW.return_quantity, 0));
    ELSE
      sufioun_update_stock_qty(:NEW.product_id, -(NVL(:NEW.return_quantity, 0) - NVL(:OLD.return_quantity, 0)));
    END IF;
  END IF;
END;
/
```

---

## 4) Finalized APEX Patterns (Purchase Return)

> **Collection constant used in all return processes:** `RETURN_ITEMS`  
> Keep this value identical in DA, on-demand process, and after-master process.

### 4.1 Pattern A: Sync IG rows to collection before submit

### Dynamic Action (Execute JavaScript Code)

```javascript
apex.server.process(
  'SYNC_IG_TO_COLLECTION',
  {
    pageItems: '#P50_RETURN_ID'
  },
  {
    dataType: 'json',
    success: function(pData) {
      if (pData && pData.status === 'OK') {
        apex.message.clearErrors();
      } else {
        apex.message.showErrors([
          {
            type: 'error',
            location: ['page'],
            message: (pData && pData.message) ? pData.message : 'Failed to sync return rows to collection.',
            unsafe: false
          }
        ]);
      }
    },
    error: function(jqXHR, textStatus, errorThrown) {
      apex.message.showErrors([
        {
          type: 'error',
          location: ['page'],
          message: 'SYNC_IG_TO_COLLECTION failed: ' + textStatus + ' / ' + errorThrown,
          unsafe: false
        }
      ]);
    }
  }
);
```

### On-Demand Process: `SYNC_IG_TO_COLLECTION`

```plsql
DECLARE
  l_count NUMBER := 0;
BEGIN
  apex_collection.create_or_truncate_collection('RETURN_ITEMS');

  FOR r IN (
    SELECT
      return_detail_id,
      return_id,
      product_id,
      mrp,
      purchase_price,
      return_quantity,
      reason
    FROM sufioun_purchase_return_details
    WHERE return_id = :P50_RETURN_ID
  ) LOOP
    apex_collection.add_member(
      p_collection_name => 'RETURN_ITEMS',
      p_c001            => r.return_detail_id,
      p_c002            => r.return_id,
      p_c003            => r.product_id,
      p_c004            => TO_CHAR(r.mrp),
      p_c005            => TO_CHAR(r.purchase_price),
      p_c006            => TO_CHAR(r.return_quantity),
      p_c007            => r.reason
    );

    l_count := l_count + 1;
  END LOOP;

  apex_json.open_object;
  apex_json.write('status', 'OK');
  apex_json.write('rows_synced', l_count);
  apex_json.close_object;
EXCEPTION
  WHEN OTHERS THEN
    apex_json.open_object;
    apex_json.write('status', 'ERROR');
    apex_json.write('message', SQLERRM);
    apex_json.close_object;
END;
```

### 4.2 Pattern B: Single detail persistence process after master DML

> Keep **only one** detail-save process. Remove/disable duplicates.

### Process: `PRC_INS_RETURN_DETAILS_FROM_COLLECTION` (After Master DML)

```plsql
DECLARE
BEGIN
  -- Delete-then-insert keeps detail rows exactly aligned with current RETURN_ITEMS collection state
  -- (including removed rows from the IG).
  -- Use this pattern for small/medium transactional grids where full-row replacement is acceptable.
  -- For very large line sets, consider MERGE/upsert strategy.
  DELETE FROM sufioun_purchase_return_details
  WHERE return_id = :P50_RETURN_ID;

  FOR c IN (
    SELECT c001, c002, c003, c004, c005, c006, c007
    FROM apex_collections
    WHERE collection_name = 'RETURN_ITEMS'
  ) LOOP
    INSERT INTO sufioun_purchase_return_details (
      return_detail_id,
      return_id,
      product_id,
      mrp,
      purchase_price,
      return_quantity,
      reason
    ) VALUES (
      NVL(c.c001, 'PRD-' || TO_CHAR(sufioun_prod_ret_det_seq.NEXTVAL)),
      :P50_RETURN_ID,
      c.c003,
      TO_NUMBER(NVL(c.c004, '0')),
      TO_NUMBER(NVL(c.c005, '0')),
      TO_NUMBER(NVL(c.c006, '0')),
      c.c007
    );
  END LOOP;
END;
```

### 4.3 Process sequencing (required order)

1. `SYNC_IG_TO_COLLECTION` (DA/on-demand) before submit final DML.
2. Master form DML for `SUFIOUN_PURCHASE_RETURN_MASTER`.
3. `PRC_INS_RETURN_DETAILS_FROM_COLLECTION` (**After Master DML**).
4. Automatic trigger recalculates `TOTAL_AMOUNT` and `GRAND_TOTAL`.

---

## 5) Final Query Blocks Used by Pages

### 5.1 Purchase Order lines

```sql
SELECT order_detail_id,
       order_id,
       product_id,
       mrp,
       purchase_price,
       quantity,
       delivered_qty,
       line_total
FROM sufioun_purchase_order_details
WHERE order_id = :P710_ORDER_ID
ORDER BY order_detail_id;
```

### 5.2 Purchase Receive pending-from-order lines

```sql
SELECT d.order_detail_id,
       d.product_id,
       d.quantity                                           AS ordered_qty,
       NVL(r.received_qty, 0)                              AS total_received_qty,
       (d.quantity - NVL(r.received_qty, 0))               AS pending_qty,
       d.purchase_price,
       d.mrp
FROM sufioun_purchase_order_details d
LEFT JOIN (
  SELECT order_detail_id,
         SUM(receive_quantity) AS received_qty
  FROM sufioun_purchase_receive_details
  GROUP BY order_detail_id
) r ON r.order_detail_id = d.order_detail_id
WHERE d.order_id = :P720_ORDER_ID
  AND (d.quantity - NVL(r.received_qty, 0)) > 0;
```

### 5.3 Purchase Return returnable-from-receive lines

```sql
SELECT rd.receive_det_id,
       rd.product_id,
       rd.receive_quantity,
       NVL(rt.returned_qty, 0)                             AS already_returned_qty,
       (rd.receive_quantity - NVL(rt.returned_qty, 0))     AS returnable_qty,
       rd.purchase_price,
       rd.mrp
FROM sufioun_purchase_receive_details rd
LEFT JOIN (
  SELECT receive_det_id,
         SUM(return_quantity) AS returned_qty
  FROM sufioun_purchase_return_details
  GROUP BY receive_det_id
) rt ON rt.receive_det_id = rd.receive_det_id
WHERE rd.receive_id = :P50_RECEIVE_ID
  AND (rd.receive_quantity - NVL(rt.returned_qty, 0)) > 0;
```

---

## 6) Troubleshooting Guide

### 6.1 ORA-04091 mutating table on return total trigger

**Symptom**
- Save/update/delete return details fails with mutating table error.

**Root cause**
- Row-level style trigger queries same return detail table during row event.

**Fix**
- Replace with compound trigger pattern `SUFIOUN_TRI_RET_TOTAL_PRICE` in section 3.3.

### 6.2 Collection empty / return quantity becomes zero

**Symptom**
- Return details saved as empty rows or quantities become `0`.

**Root cause**
- `SYNC_IG_TO_COLLECTION` not executed before submit, or multiple detail processes conflict.

**Fix**
1. Ensure DA calls on-demand sync before submit.
2. Ensure only one detail insert process exists.
3. Keep detail insert process after master DML.
4. Verify collection content:

```sql
SELECT seq_id, c001, c002, c003, c004, c005, c006, c007
FROM apex_collections
WHERE collection_name = 'RETURN_ITEMS'
ORDER BY seq_id;
```

### 6.3 FK mismatch on `PRODUCT_ID`

**Symptom**
- Insert into return details fails with FK violation.

**Root cause**
- `PRODUCT_ID` in collection is not in `SUFIOUN_PRODUCTS`, or stale item mapping from IG.

**Fix**
1. Validate product exists:

```sql
SELECT product_id
FROM sufioun_products
WHERE product_id = :P_CHECK_PRODUCT_ID;
```

2. Ensure IG column maps exact `PRODUCT_ID` value, not display label.
3. Rebuild collection after correcting IG mapping.

### 6.4 Historical bad totals in return master

**Note**
- Some old rows may have inflated totals due to earlier trigger logic.

**One-time corrective SQL**

```sql
UPDATE sufioun_purchase_return_master m
SET m.total_amount = (
      SELECT NVL(SUM(NVL(d.line_total,0)),0)
      FROM sufioun_purchase_return_details d
      WHERE d.return_id = m.return_id
    ),
    m.grand_total = (
      SELECT NVL(SUM(NVL(d.line_total,0)),0)
      FROM sufioun_purchase_return_details d
      WHERE d.return_id = m.return_id
    ) + NVL(m.adjusted_vat,0)
WHERE m.return_id = :P_RETURN_ID;

COMMIT;
```

Optional bulk-safe correction:

Use a named SQL*Plus variable for the safety threshold so it is easy to tune during remediation.

```sql
DEFINE BAD_TOTAL_FACTOR = '5';
-- 5 = conservative anomaly threshold for legacy bad totals:
-- only rows with GRAND_TOTAL > 5x expected amount are corrected by this bulk script.
-- Example: expected grand_total = 100, row is corrected only when stored grand_total > 500.

UPDATE sufioun_purchase_return_master m
SET m.total_amount = (
      SELECT NVL(SUM(NVL(d.line_total,0)),0)
      FROM sufioun_purchase_return_details d
      WHERE d.return_id = m.return_id
    ),
    m.grand_total = (
      SELECT NVL(SUM(NVL(d.line_total,0)),0)
      FROM sufioun_purchase_return_details d
      WHERE d.return_id = m.return_id
    ) + NVL(m.adjusted_vat,0)
WHERE m.grand_total > (NVL(m.total_amount,0) + NVL(m.adjusted_vat,0)) * &BAD_TOTAL_FACTOR;

COMMIT;
```

---

## 7) Validation & Testing Checklist (Create + Update)

- [ ] Create Purchase Order with multiple products and verify `TOTAL_AMOUNT`/`GRAND_TOTAL`.
- [ ] Update one PO detail quantity and verify master totals recalculate.
- [ ] Create Purchase Receive from PO and verify pending quantity logic.
- [ ] Update receive quantity and verify stock increase delta is correct.
- [ ] Create Purchase Return from receive and verify returnable quantity logic.
- [ ] Confirm DA sync populates `RETURN_ITEMS` before submit.
- [ ] Confirm only one detail save process runs on submit.
- [ ] Update existing return lines and confirm no duplicate details are inserted.
- [ ] Confirm trigger updates `SUFIOUN_PURCHASE_RETURN_MASTER.TOTAL_AMOUNT` and `GRAND_TOTAL` correctly.
- [ ] Confirm no `ORA-04091` occurs on insert/update/delete of return details.
- [ ] Confirm FK integrity for `PRODUCT_ID`.
- [ ] Verify supplier financial summary/due impact after receive and return.

---

## 8) Final Notes

1. Return totals must always be detail-driven (`SUM(line_total)`) + `ADJUSTED_VAT`.
2. Keep process order stable; avoid parallel duplicate detail save processes.
3. If totals appear inconsistent after deployment, run one-time corrective SQL and then retest create/update cycle.
