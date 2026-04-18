# Purchase Flow — Order / Receive / Return (Page 52 / Page 53)

This page captures the latest validated implementation fixes and troubleshooting notes for Purchase Order and Purchase Receive detail modals.

## Page 52 — Purchase Order Details modal: detail rows appear fewer than DB rows

### Symptom
For some orders, `SUFIOUN_PURCHASE_ORDER_DETAILS` contained 4 rows but the Page 52 modal showed only 2 rows.

### Root cause
Data was present in DB. The Interactive Grid (IG) was opening with persisted report state (pagination/filter/report state), so visible rows were limited by prior IG state.

### Validation SQL (confirm data before UI troubleshooting)
```sql
SELECT COUNT(*) AS detail_row_count,
       SUM(NVL(QUANTITY, 0)) AS detail_total_quantity
  FROM SUFIOUN_PURCHASE_ORDER_DETAILS
 WHERE ORDER_ID = :P52_ORDER_ID;
```

```sql
SELECT d.ORDER_DETAIL_ID,
       d.ORDER_ID,
       d.PRODUCT_ID,
       p.PRODUCT_NAME,
       d.QUANTITY,
       d.PURCHASE_PRICE,
       (NVL(d.QUANTITY, 0) * NVL(d.PURCHASE_PRICE, 0)) AS LINE_TOTAL
  FROM SUFIOUN_PURCHASE_ORDER_DETAILS d
  LEFT JOIN SUFIOUN_PRODUCTS p
    ON p.PRODUCT_ID = d.PRODUCT_ID
 WHERE d.ORDER_ID = :P52_ORDER_ID
 ORDER BY d.ORDER_DETAIL_ID;
```

### Final fix (open modal with report reset)
Use the modal link URL with `RP` so Page 52 opens with reset report state:

```text
f?p=&APP_ID.:52:&APP_SESSION.::NO:RP,52:P52_ORDER_ID:#ORDER_ID#
```

### Pagination guidance
- If **Pagination Type = Scroll**, the IG expands with scroll behavior and avoids page-based row hiding confusion.
- If page-based pagination is kept, ensure page size/state is appropriate or users may see fewer rows by default.

## Page 52 — UI polish notes (horizontal scroll + bottom strip blocking buttons)

In modal IG layouts, unnecessary horizontal scrollbar area and IG status/footer strips can visually overlap or push action buttons out of easy reach.

### CSS recommendation
> Replace `#Order_Details` with the actual Page 52 IG region Static ID.

```css
/* Page 52: keep modal action area usable */
#Order_Details .a-GV-footer,
#Order_Details .a-GV-status,
#Order_Details .a-IG-status,
#Order_Details .a-GV-bottom {
  display: none !important;
}

#Order_Details .a-GV-w-scroll {
  overflow-y: auto !important;
  overflow-x: hidden !important;
}

#Order_Details .a-GV-table {
  width: 100% !important;
  table-layout: fixed !important;
}
```

## Page 53 — Purchase Receive Details modal: missing Product Name and Ordered Quantity

### Symptom
IG did not show Product Name and Ordered Quantity.

### Root cause
The IG query selected only `SUFIOUN_PURCHASE_RECEIVE_DETAILS` columns, so display-only values from related tables were unavailable.

### Corrected SQL (final)
```sql
SELECT d.RECEIVE_DET_ID,
       d.RECEIVE_ID,
       d.PRODUCT_ID,
       p.PRODUCT_NAME,
       od.QUANTITY AS ORDER_QUANTITY,
       d.MRP,
       d.PURCHASE_PRICE,
       d.RECEIVE_QUANTITY,
       (NVL(d.PURCHASE_PRICE, 0) * NVL(d.RECEIVE_QUANTITY, 0)) AS LINE_TOTAL,
       d.ORDER_DETAIL_ID
  FROM SUFIOUN_PURCHASE_RECEIVE_DETAILS d
  LEFT JOIN SUFIOUN_PRODUCTS p
    ON p.PRODUCT_ID = d.PRODUCT_ID
  LEFT JOIN SUFIOUN_PURCHASE_ORDER_DETAILS od
    ON od.ORDER_DETAIL_ID = d.ORDER_DETAIL_ID
 WHERE d.RECEIVE_ID = :P53_RECEIVE_ID
 ORDER BY d.RECEIVE_DET_ID;
```

### Recommended IG columns
- **Visible**: `PRODUCT_NAME`, `ORDER_QUANTITY`, `RECEIVE_QUANTITY`, `PURCHASE_PRICE`, `LINE_TOTAL`
- **Hidden (technical)**: `RECEIVE_DET_ID`, `RECEIVE_ID`, `PRODUCT_ID`, `ORDER_DETAIL_ID`

## Page 53 — CSS selector correction (wrong page selector used previously)

Prior CSS used a Page 52 selector (`#R156250216129047487131`) on Page 53, so rules did not apply.

Use the actual Page 53 IG region Static ID (current example: `#Receive_Details`).

```css
/* Page 53: hide blocking IG strips + remove unnecessary horizontal scroll */
#Receive_Details .a-GV-footer,
#Receive_Details .a-GV-status,
#Receive_Details .a-IG-status,
#Receive_Details .a-GV-bottom {
  display: none !important;
}

#Receive_Details .a-GV-w-scroll {
  overflow-y: auto !important;
  overflow-x: hidden !important;
}

#Receive_Details .a-GV-table {
  width: 100% !important;
  table-layout: fixed !important;
}

#Receive_Details .a-GV-header th,
#Receive_Details .a-GV-cell {
  white-space: nowrap !important;
  overflow: hidden !important;
  text-overflow: ellipsis !important;
}

.t-Dialog-footer {
  position: sticky;
  bottom: 0;
  z-index: 20;
  background: #fff;
}
```

## Troubleshooting checklist (Order/Receive detail modal)

1. Verify DB detail row count first (`SUFIOUN_PURCHASE_ORDER_DETAILS` / `SUFIOUN_PURCHASE_RECEIVE_DETAILS`).
2. If DB rows are correct but IG shows fewer rows, reset report state (`RP`) and review pagination behavior.
3. Confirm IG SQL includes required joins for display-only fields (`PRODUCT_NAME`, `ORDER_QUANTITY`).
4. Confirm CSS selectors use the correct current page region Static ID (Page 52 vs Page 53).
5. Re-test modal open flow from source page after URL reset fix:
   - `f?p=&APP_ID.:52:&APP_SESSION.::NO:RP,52:P52_ORDER_ID:#ORDER_ID#`
