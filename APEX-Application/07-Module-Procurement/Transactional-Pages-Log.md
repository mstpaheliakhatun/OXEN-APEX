## Module: Procurement (Transactional)

This file is the running log and implementation guide for all procurement transaction pages.
Use this document whenever a new transactional page is created or changed.

## Page Register

| Page ID | Page Name | Key Table(s) | Status |
|---|---|---|---|
| 710 | Purchase Order | sufioun_purchase_order_mst, sufioun_purchase_order_det | Planned |
| 720 | Purchase Receive | sufioun_purchase_receive_mst, sufioun_purchase_receive_det | Planned |
| 730 | Purchase Return | sufioun_purchase_return_mst, sufioun_purchase_return_det | Planned |

---

## Page 710: Purchase Order

### 1) Page Summary
- Purpose: Create and manage supplier purchase orders.
- User story: Purchasing user creates PO header and line items, then submits for approval.
- Roles: ADMIN, INVENTORY_MANAGER, STOREKEEPER (based on policy).

### 2) UX and Regions
- RGN_PO_HEADER (Form region)
- RGN_PO_LINES (Editable IG)
- RGN_PO_TOTALS (Display region)
- RGN_PO_ACTIONS (Buttons region)

Core items:
- P710_PO_ID (hidden PK)
- P710_PO_NO (display/readonly)
- P710_PO_DATE
- P710_SUPPLIER_ID
- P710_WAREHOUSE_ID
- P710_STATUS

### 3) HTML Notes
```html
<div class="po-layout">
  <section class="po-header">Purchase Order Header</section>
  <section class="po-lines">Purchase Order Lines</section>
  <aside class="po-totals">Totals</aside>
</div>
```

### 4) CSS Notes
```css
.po-layout{display:grid;grid-template-columns:2fr 1fr;gap:12px}
.po-header,.po-lines,.po-totals{background:#fff;border-radius:12px;padding:12px}
.po-totals{position:sticky;top:12px}
```

### 5) SQL Query Documentation
PO header source:
```sql
SELECT po_id, po_no, po_date, supplier_id, warehouse_id,
       subtotal_amount, tax_amount, discount_amount,
       net_amount, status, remarks, created_by, created_dt
FROM sufioun_purchase_order_mst
WHERE po_id = :P710_PO_ID;
```

PO lines source:
```sql
SELECT po_det_id, po_id, product_id, uom_id,
       order_qty, unit_cost, tax_pct, line_amount, notes
FROM sufioun_purchase_order_det
WHERE po_id = :P710_PO_ID;
```

Supplier LOV:
```sql
SELECT supplier_name display_value, supplier_id return_value
FROM sufioun_suppliers
WHERE status = 1
ORDER BY supplier_name;
```

Product LOV:
```sql
SELECT product_name||' ('||product_code||')' display_value, product_id return_value
FROM sufioun_products
WHERE status = 1
ORDER BY product_name;
```

### 6) Process and Validation Notes
- Form DML for `sufioun_purchase_order_mst`.
- IG row processing for `sufioun_purchase_order_det`.
- Validate `order_qty > 0` and `unit_cost >= 0`.
- Recompute totals after line save.

---

## Page 720: Purchase Receive

### 1) Page Summary
- Purpose: Receive goods against approved purchase orders.
- User story: Storekeeper receives full or partial quantities and posts inventory increase.
- Roles: ADMIN, INVENTORY_MANAGER, STOREKEEPER.

### 2) UX and Regions
- RGN_RECEIVE_HEADER
- RGN_RECEIVE_LINES
- RGN_RECEIVE_SUMMARY
- RGN_RECEIVE_ACTIONS

Core items:
- P720_RECEIVE_ID (hidden PK)
- P720_RECEIVE_NO
- P720_RECEIVE_DATE
- P720_PO_ID
- P720_SUPPLIER_ID
- P720_STATUS

### 3) HTML Notes
```html
<div class="receive-layout">
  <section class="receive-header">Receive Header</section>
  <section class="receive-lines">Receive Lines</section>
</div>
```

### 4) CSS Notes
```css
.receive-layout{display:grid;grid-template-columns:1fr;gap:12px}
.receive-header,.receive-lines{background:#fff;border-radius:12px;padding:12px}
.receive-ok{color:#2e7d32;font-weight:700}
```

### 5) SQL Query Documentation
Receive header source:
```sql
SELECT receive_id, receive_no, receive_date, po_id, supplier_id,
       warehouse_id, total_received_amount, status, remarks,
       created_by, created_dt
FROM sufioun_purchase_receive_mst
WHERE receive_id = :P720_RECEIVE_ID;
```

Receive lines source:
```sql
SELECT receive_det_id, receive_id, po_det_id, product_id,
       ordered_qty, received_qty, accepted_qty, rejected_qty,
       unit_cost, line_amount
FROM sufioun_purchase_receive_det
WHERE receive_id = :P720_RECEIVE_ID;
```

Approved PO LOV:
```sql
SELECT po_no display_value, po_id return_value
FROM sufioun_purchase_order_mst
WHERE status IN ('APPROVED','PARTIAL_RECEIVED')
ORDER BY po_date DESC;
```

Pending PO lines (for selected PO):
```sql
SELECT d.po_det_id,
       d.product_id,
       d.order_qty,
       NVL(r.received_qty,0) total_received_qty,
       (d.order_qty - NVL(r.received_qty,0)) pending_qty,
       d.unit_cost
FROM sufioun_purchase_order_det d
LEFT JOIN (
  SELECT po_det_id, SUM(accepted_qty) received_qty
  FROM sufioun_purchase_receive_det
  GROUP BY po_det_id
) r ON r.po_det_id = d.po_det_id
WHERE d.po_id = :P720_PO_ID
  AND (d.order_qty - NVL(r.received_qty,0)) > 0;
```

### 6) Process and Validation Notes
- Validate `accepted_qty + rejected_qty = received_qty`.
- Prevent receipt quantity from exceeding pending quantity.
- Posting process updates stock ledger and stock-on-hand.

---

## Page 730: Purchase Return

### 1) Page Summary
- Purpose: Return damaged or wrong goods to supplier after receipt.
- User story: Storekeeper/manager creates supplier return and posts stock decrease.
- Roles: ADMIN, INVENTORY_MANAGER, STOREKEEPER.

### 2) UX and Regions
- RGN_RETURN_HEADER
- RGN_RETURN_LINES
- RGN_RETURN_REASON
- RGN_RETURN_ACTIONS

Core items:
- P730_RETURN_ID (hidden PK)
- P730_RETURN_NO
- P730_RETURN_DATE
- P730_SUPPLIER_ID
- P730_RECEIVE_ID
- P730_STATUS

### 3) HTML Notes
```html
<div class="return-layout">
  <section class="return-header">Return Header</section>
  <section class="return-lines">Return Lines</section>
  <section class="return-reason">Reason and Notes</section>
</div>
```

### 4) CSS Notes
```css
.return-layout{display:grid;grid-template-columns:1fr;gap:12px}
.return-header,.return-lines,.return-reason{background:#fff;border-radius:12px;padding:12px}
.return-warning{color:#b26a00;font-weight:700}
```

### 5) SQL Query Documentation
Return header source:
```sql
SELECT return_id, return_no, return_date, supplier_id,
       receive_id, total_return_amount, status, reason_code,
       remarks, created_by, created_dt
FROM sufioun_purchase_return_mst
WHERE return_id = :P730_RETURN_ID;
```

Return lines source:
```sql
SELECT return_det_id, return_id, receive_det_id, product_id,
       return_qty, unit_cost, line_amount, reason_code
FROM sufioun_purchase_return_det
WHERE return_id = :P730_RETURN_ID;
```

Receipts LOV:
```sql
SELECT receive_no display_value, receive_id return_value
FROM sufioun_purchase_receive_mst
WHERE status IN ('POSTED','COMPLETED')
ORDER BY receive_date DESC;
```

Returnable lines (for selected receipt):
```sql
SELECT rd.receive_det_id,
       rd.product_id,
       rd.accepted_qty,
       NVL(rt.returned_qty,0) already_returned_qty,
       (rd.accepted_qty - NVL(rt.returned_qty,0)) returnable_qty,
       rd.unit_cost
FROM sufioun_purchase_receive_det rd
LEFT JOIN (
  SELECT receive_det_id, SUM(return_qty) returned_qty
  FROM sufioun_purchase_return_det
  GROUP BY receive_det_id
) rt ON rt.receive_det_id = rd.receive_det_id
WHERE rd.receive_id = :P730_RECEIVE_ID
  AND (rd.accepted_qty - NVL(rt.returned_qty,0)) > 0;
```

### 6) Process and Validation Notes
- Validate `return_qty > 0`.
- Prevent return quantity from exceeding returnable quantity.
- Posting process creates negative stock movement and supplier debit note reference.

---

## Reusable Logging Template (For Next Transaction Pages)

Copy this section whenever adding a new transactional page:

```md
## Page XXX: <Page Name>
### 1) Page Summary
### 2) UX and Regions
### 3) HTML Notes
### 4) CSS Notes
### 5) SQL Query Documentation
### 6) Process and Validation Notes
```
