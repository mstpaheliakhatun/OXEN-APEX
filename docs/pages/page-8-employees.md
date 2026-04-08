# Page 8 — Employees (Interactive Report rendered as Cards)

This document explains **exactly how Page 8 (Employees)** is built in Oracle APEX 24.2.14 (export version `2024.11.30`), including the **full SQL query**, **all JavaScript** (line-by-line), **CSS grouped by component**, and a **step-by-step rebuild guide**.

> Application: **28775 — Oxen Electronics Limited**
> Page: **8 — Employees** (Alias: `EMPLOYEES`)
> Template: APEX **Interactive Report** region whose rows are transformed into **cards** via HTML + JavaScript + CSS.

---

## 1) What the page does (functional overview)

Page 8 lists employees as modern **cards** (grid/list view toggle) while still using an Interactive Report underneath for:

- pagination
- search/actions menu
- download formats (CSV/HTML/XLSX/PDF)

Each row returns `CARD_HTML` which is the actual card markup. JavaScript then:

1. finds `.empCard` elements
2. wraps them into a grid container `.empCardsWrap`
3. injects the wrapper into the IR DOM (`.t-Report-report`)
4. supports a grid/list toggle by applying a CSS class to `<body>`

---

## 2) Page metadata (from export)

- **Page ID:** 8
- **Name:** Employees
- **Alias:** EMPLOYEES
- **Title:** Employees
- **Autocomplete:** OFF
- **Protection Level:** C
- **APEX release:** 24.2.14
- **Export version:** 2024.11.30

---

## 3) Regions (Page Designer structure)

### 3.1 Breadcrumb
- **Region Type:** Breadcrumb
- **Display Point:** `REGION_POSITION_01`
- Purpose: shows page title/breadcrumb trail.

### 3.2 Employees
- **Region Type:** Interactive Report (`NATIVE_IR`)
- **Region template options:** hides header (`t-IRR-region--hideHeader`)
- **Important:** The JavaScript expects the region Static ID to be `emp_ir` (see §5).

---

## 4) Full SQL query (verbatim from export)

The Interactive Report query returns normal columns (hidden) plus two computed columns:

- `IMG_URL` — photo URL served by Application Process `EMP_PHOTO` (On Demand)
- `CARD_HTML` — full HTML for one employee card

```sql
select
  e.employee_id,
  e.first_name,
  e.last_name,
  e.email,
  e.phone_no,
  e.hire_date,
  e.salary,
  j.job_title,
  d.department_name,

  /* Always-correct on-demand image URL (EMP_PHOTO uses g_x01) */
  case
    when dbms_lob.getlength(e.photo) > 0 then
      'f?p='||:APP_ID||':0:'||:APP_SESSION||
      ':APPLICATION_PROCESS=EMP_PHOTO:::&x01='||apex_util.url_encode(e.employee_id)
    else
      '#APP_FILES#avatar-default.png'
  end as img_url,

  /* One HTML card per row */
  '<article class="empCard" data-emp-id="'||apex_escape.html_attribute(e.employee_id)||'">'||

    '<div class="empCard__avatar">'||
      '<a class="empCard__avatarLink" href="'||
        apex_escape.html_attribute(
          apex_page.get_url(
            p_page   => 44,
            p_items  => 'P44_EMPLOYEE_ID',
            p_values => e.employee_id
          )
        )||'" aria-label="Open CV">'||

        '<img src="'||
          apex_escape.html_attribute(
            case
              when dbms_lob.getlength(e.photo) > 0 then
                'f?p='||:APP_ID||':0:'||:APP_SESSION||
                ':APPLICATION_PROCESS=EMP_PHOTO:::&x01='||apex_util.url_encode(e.employee_id)
              else
                '#APP_FILES#avatar-default.png'
            end
          )||
        '" alt="Employee photo" loading="lazy" '||
        'onerror="this.onerror=null;this.src=''''#APP_FILES#avatar-default.png'''';">'||

      '</a>'||
    '</div>'||

    '<div class="empCard__main">'||
      '<a class="empCard__name" href="'||
        apex_escape.html_attribute(
          apex_page.get_url(
            p_page   => 15,
            p_items  => 'P15_EMPLOYEE_ID',
            p_values => e.employee_id
          )
        )||'">'||
        apex_escape.html(e.first_name||' '||e.last_name)||
      '</a>'||

      '<div class="empCard__meta">'||
        apex_escape.html(nvl(j.job_title,'-'))||' • '||
        apex_escape.html(nvl(d.department_name,'-'))||
      '</div>'||

      '<div class="empCard__chips">'||
        '<span class="empChip empChip--mail">✉ '||apex_escape.html(nvl(e.email,'-'))||'</span>'||
        '<span class="empChip empChip--phone">☎ '||apex_escape.html(nvl(e.phone_no,'-'))||'</span>'||
      '</div>'||
    '</div>'||

    '<div class="empCard__side">'||
      '<div class="empCard__salary">৳ '||to_char(e.salary,'FM999G999G999')||'</div>'||
      '<div class="empCard__hire">Hired: '||to_char(e.hire_date,'DD-MON-YYYY')||'</div>'||

      '<div class="empCard__actions">'||
        '<a class="empBtn empBtn--ghost" href="'||
          apex_escape.html_attribute(
            apex_page.get_url(
              p_page   => 44,
              p_items  => 'P44_EMPLOYEE_ID',
              p_values => e.employee_id
            )
          )||'">CV</a>'||

        '<a class="empBtn empBtn--primary" href="'||
          apex_escape.html_attribute(
            apex_page.get_url(
              p_page   => 9,
              p_items  => 'P9_EMPLOYEE_ID',
              p_values => e.employee_id
            )
          )||'">Edit</a>'||
      '</div>'||
    '</div>'||

  '</article>' as card_html

from sufioun_employees e
left join sufioun_jobs j on j.job_id = e.job_id
left join sufioun_departments d on d.department_id = e.department_id
order by e.first_name, e.last_name;
```

### Notes on the SQL
- `CARD_HTML` is rendered by the IR column with **Display As = Without Modification**.
- `IMG_URL` is hidden, but used conceptually and is useful for debugging.
- BLOB check uses `dbms_lob.getlength(e.photo) > 0` which is safer than `photo is not null`.

---

## 5) JavaScript (full code + line-by-line explanation)

### 5.1 Full JavaScript (verbatim from export)

```js
(function () {
  const REGION_STATIC_ID = "emp_ir"; // set your IR region static id to this

  function applyLayout(mode){
    document.body.classList.toggle("empListMode", mode === "list");
    localStorage.setItem("empViewMode", mode);
  }

  function bindViewButtons(){
    const btnGrid = document.getElementById("empViewGrid");
    const btnList = document.getElementById("empViewList");

    if (btnGrid && !btnGrid.dataset.bound){
      btnGrid.addEventListener("click", function(){ applyLayout("grid"); });
      btnGrid.dataset.bound = "1";
    }
    if (btnList && !btnList.dataset.bound){
      btnList.addEventListener("click", function(){ applyLayout("list"); });
      btnList.dataset.bound = "1";
    }

    applyLayout(localStorage.getItem("empViewMode") || "grid");
  }

  function wrapCards(){
    const region = document.getElementById(REGION_STATIC_ID);
    if (!region) return;

    // mark region for css
    region.classList.add("empIR");

    // cards are output by CARD_HTML
    const cards = region.querySelectorAll(".empCard");
    if (!cards.length) return;

    // prevent duplicates after refresh
    region.querySelectorAll(".empCardsWrap").forEach(w => w.remove());

    const wrap = document.createElement("div");
    wrap.className = "empCardsWrap";
    cards.forEach(c => wrap.appendChild(c));

    // Interactive Report HTML usually contains .t-Report-report
    const report = region.querySelector(".t-Report-report");
    if (report) {
      report.prepend(wrap);
    }
  }

  function computeStats(){
    const empCountEl  = document.getElementById("empCount");
    const deptCountEl = document.getElementById("deptCount");

    const cards = document.querySelectorAll("#" + REGION_STATIC_ID + " .empCardsWrap .empCard");
    if (empCountEl) empCountEl.textContent = String(cards.length);

    // departments inferred from ".empCard__meta" text "Job • Department"
    const depts = new Set();
    cards.forEach(c => {
      const meta = c.querySelector(".empCard__meta")?.textContent || "";
      const parts = meta.split("•");
      if (parts.length > 1) {
        const dept = parts[1].trim();
        if (dept && dept !== "-") depts.add(dept.toLowerCase());
      }
    });
    if (deptCountEl) deptCountEl.textContent = String(depts.size);
  }

  function init(){
    wrapCards();
    bindViewButtons();
    window.setTimeout(computeStats, 80);
  }

  document.addEventListener("apexreadyend", init);
  document.addEventListener("apexafterrefresh", init);
})();
```

### 5.2 Line-by-line explanation

#### Wrapper IIFE
- `(function () { ... })();`
  - isolates variables/functions so they do not leak into global scope.

#### `REGION_STATIC_ID`
- `const REGION_STATIC_ID = "emp_ir";`
  - the code **assumes** the Interactive Report region’s Static ID is `emp_ir`.
  - if the region uses a different Static ID, card wrapping and stats won’t run.

#### `applyLayout(mode)`
- toggles a body class to switch CSS layout:
  - adds `empListMode` when mode is `list`
  - removes it when mode is `grid`
- stores the current mode in `localStorage` (`empViewMode`) so it persists across reloads.

#### `bindViewButtons()`
- reads two DOM elements:
  - `#empViewGrid` and `#empViewList`
- attaches click handlers **once** (using `dataset.bound` guard)
- applies saved mode from localStorage (defaults to `grid`)

> **Note:** This page export contains the JS for the buttons, but the export snippet you pasted does not include the HTML region that renders the buttons. If the buttons are missing in the UI, add them in a Static Content region (see rebuild guide §7).

#### `wrapCards()`
- grabs the region DOM by static id (`emp_ir`)
- finds `.empCard` elements produced by the report column `CARD_HTML`
- creates a wrapper `<div class="empCardsWrap">`
- moves each `.empCard` inside the wrapper
- injects the wrapper into `.t-Report-report` so it visually becomes a grid
- removes any previous `.empCardsWrap` first to avoid duplicates after refresh

#### `computeStats()`
- counts cards and writes totals into:
  - `#empCount` (total employees currently rendered)
  - `#deptCount` (unique depts inferred)
- department count is derived by splitting `.empCard__meta` text on `•` and taking the right side

#### `init()`
- calls `wrapCards()`
- calls `bindViewButtons()`
- calls `computeStats()` with a slight delay (80ms) to ensure DOM is ready

#### APEX events
- `apexreadyend`
  - fires when APEX finishes rendering
- `apexafterrefresh`
  - fires after partial refresh (e.g., filtering, pagination)
- both re-run `init()` so cards re-wrap after refresh.

---

## 6) CSS (grouped by component)

All CSS below is Inline CSS at the page level (Page 8 → CSS → Inline).

### 6.1 Global page background
```css
.t-Body-content{
  background: linear-gradient(180deg, #f7f9fc 0%, #ffffff 55%);
}
```

### 6.2 Hero toolbar (header area)
> The CSS defines `.empHero` / `.empStat` / `.empViewBtns`, which implies the page should have a Static Content region that renders a hero header with stats + view mode buttons.

Key classes:
- `.empHero` — container
- `.empHero__titleRow`, `.empHero__title`, `.empHero__pill`, `.empHero__sub` — title and subtitle
- `.empHero__quick` — stats row
- `.empStat`, `.empStat__label`, `.empStat__value` — stat cards
- `.empViewBtns` — button container

### 6.3 Interactive Report “chrome cleanup”
```css
#emp_ir .t-Report-report thead{ display:none !important; }
#emp_ir .t-Report-report table,
#emp_ir .t-Report-report tbody,
#emp_ir .t-Report-report tr,
#emp_ir .t-Report-report td{ display:block; }
#emp_ir .t-Report-report td{ padding:0; border:0; }
#emp_ir .t-Report-report tr{ margin:0; }
```
Purpose:
- hides the report header
- makes each row behave like a block so your `CARD_HTML` can be laid out cleanly

Optional (commented) to hide toolbar controls:
- `#emp_ir .t-IRR-controls`
- `#emp_ir .t-IRR-toolBar`

### 6.4 Cards grid wrapper
```css
.empCardsWrap{
  display:grid;
  grid-template-columns: repeat(3, minmax(310px, 1fr));
  gap: 14px;
  margin-top: 10px;
}
```
Purpose: makes the cards show as a responsive grid.

### 6.5 Employee card component
Key blocks:
- `.empCard` + hover/focus states
- `.empCard__avatar` and `.empCard__avatar img`
- `.empCard__name`
- `.empCard__meta`
- `.empCard__chips` / `.empChip`
- `.empCard__side` / `.empCard__salary` / `.empCard__hire`
- `.empCard__actions` and buttons `.empBtn`, `.empBtn--ghost`, `.empBtn--primary`

### 6.6 List mode modifier
List mode is activated by body class `empListMode` set by JS:
```css
.empListMode .empCardsWrap{
  display:flex;
  flex-direction:column;
}
.empListMode .empCard{
  grid-template-columns: 64px 1fr;
}
.empListMode .empCard__side{
  text-align:left;
  min-width:auto;
  margin-top:10px;
}
.empListMode .empCard__actions{
  justify-content:flex-start;
}
```

### 6.7 Responsive breakpoints
```css
@media (max-width: 1200px){
  .empCardsWrap{ grid-template-columns: repeat(2, minmax(310px, 1fr)); }
}
@media (max-width: 760px){
  .empHero{ align-items:flex-start; flex-direction:column; }
  .empCardsWrap{ grid-template-columns: 1fr; }
}
```

---

## 7) Page processes / components used

### 7.1 Application Process: `EMP_PHOTO` (required)
This page relies on an **On Demand** application process that streams the employee photo BLOB.

**Contract**
- Input: `apex_application.g_x01` must be employee_id
- Output: binary image response using `wpg_docload.download_file`

**Expected table columns**
- `sufioun_employees.photo` (BLOB)
- `sufioun_employees.mime_type` (VARCHAR2)

**URL format used**
```
f?p=&APP_ID.:0:&APP_SESSION.:APPLICATION_PROCESS=EMP_PHOTO:::&x01=<EMPLOYEE_ID>
```

### 7.2 Referenced pages
- **Page 9** — Edit employee (Form)
- **Page 15** — Employee CV view
- **Page 44** — CV or printable CV (as per links in SQL)

### 7.3 Static application files
- `#APP_FILES#avatar-default.png` is the fallback image.

---

## 8) How to rebuild this page from scratch (step-by-step)

Follow these steps to recreate Page 8 exactly in a new app/page.

### Step 0 — prerequisites
1. Ensure tables exist: `SUFIOUN_EMPLOYEES`, `SUFIOUN_JOBS`, `SUFIOUN_DEPARTMENTS`.
2. Create the On Demand Application Process `EMP_PHOTO` (see §7.1).
3. Upload `avatar-default.png` to **Shared Components → Static Application Files**.

### Step 1 — Create the page
1. Create a new page → **Interactive Report**
2. Page Name: **Employees**
3. Page Alias: **EMPLOYEES**

### Step 2 — Configure the IR region
1. Region name: **Employees**
2. Region type: **Interactive Report**
3. Set region **Static ID** to: `emp_ir`
4. Set the region SQL query to the query in §4.

### Step 3 — Configure IR columns
1. Keep base columns (employee fields) as Hidden (optional).
2. Set column `CARD_HTML`:
   - Type: **Plain Text** (String)
   - Display: **Without Modification** (important)
   - Heading: “Employees” (optional)
3. Hide the other columns if you only want cards visible.

### Step 4 — Add the page JavaScript
1. Page Designer → Page → **JavaScript Code**
2. Paste the code in §5.1
3. Confirm `REGION_STATIC_ID` matches the IR region static id (`emp_ir`).

### Step 5 — Add the page CSS
1. Page Designer → Page → **Inline CSS**
2. Paste the CSS blocks (from export)

### Step 6 — (Optional but recommended) Add the hero header region
The CSS/JS expects stats elements (`#empCount`, `#deptCount`) and view buttons (`#empViewGrid`, `#empViewList`). Add a Static Content region above the IR with something like:

```html
<div class="empHero">
  <div>
    <div class="empHero__titleRow">
      <h2 class="empHero__title">Employees</h2>
      <span class="empHero__pill">Directory</span>
    </div>
    <div class="empHero__sub">Browse employees. Switch grid/list view. Open CV or edit.</div>

    <div class="empHero__quick">
      <div class="empStat">
        <div class="empStat__label">Employees</div>
        <div class="empStat__value" id="empCount">0</div>
      </div>
      <div class="empStat">
        <div class="empStat__label">Departments</div>
        <div class="empStat__value" id="deptCount">0</div>
      </div>
    </div>
  </div>

  <div class="empViewBtns">
    <button type="button" class="t-Button t-Button--small" id="empViewGrid">Grid</button>
    <button type="button" class="t-Button t-Button--small" id="empViewList">List</button>
  </div>
</div>
```

### Step 7 — Test
1. Open Page 8 → confirm cards appear in a grid (3 columns).
2. Click **List** button → should switch to list mode.
3. Verify photo loads by opening in browser devtools network:
   - request URL contains `APPLICATION_PROCESS=EMP_PHOTO` and `&x01=<employee_id>`
4. Click CV/Edit buttons to ensure page links work.

---

## 9) Troubleshooting checklist (common issues)

### Photos not showing
- Confirm `EMP_PHOTO` uses the correct column names: `photo` and `mime_type` (not `image_mime_type`).
- Confirm the image URL contains `&x01=` (because the process reads `apex_application.g_x01`).
- Confirm `dbms_lob.getlength(photo)` is > 0 for affected employees.

### Cards show as raw HTML text
- Ensure IR column `CARD_HTML` is **Without Modification** (export uses `p_display_text_as=>'WITHOUT_MODIFICATION'`).

### Cards don’t wrap into grid after refresh
- Ensure IR region Static ID is exactly `emp_ir`.
- Ensure the IR rows actually output `.empCard` elements (check the `CARD_HTML` output).

