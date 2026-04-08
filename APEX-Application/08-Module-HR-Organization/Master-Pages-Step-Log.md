## Module: HR and Organization Setup

This file is the central place to keep every step log and implementation documentation for:
1. Company page
2. Employee page
3. Employee CV page
4. Jobs page
5. Branch page

Update this document each time a requirement, SQL query, process, or UI behavior changes.

## Page Register

| Page ID | Page Name | Main Table(s) | Status |
|---|---|---|---|
| 810 | Company Master | sufioun_company | Planned |
| 820 | Employee Master | sufioun_employees | Planned |
| 830 | Employee CV | sufioun_employee_cv | Planned |
| 840 | Jobs Master | sufioun_jobs | Planned |
| 850 | Branch Master | sufioun_branches | Planned |

---

## Page 810: Company Master

### 1) Page Summary
- Purpose: Maintain company profile, registration, tax, and contact information.
- Intended roles: ADMIN, HR_MANAGER.

### 2) Step Log
| Date | Step No | Change Type | Description | Owner | Status |
|---|---|---|---|---|---|
| 2026-04-08 | 1 | Init | Created page documentation skeleton | System | Done |
| 2026-04-08 | 2 | UI | Added Employees page JavaScript view toggle/card wrapper/stats and full card CSS theme | User | Done |
| 2026-04-08 | 2 | SQL | Added Employees card region SQL with photo process URL and page links (Edit/CV) | User | Done |
| 2026-04-08 | 3 | Process | Moved EMP_PHOTO logic to schema procedure (`sufioun_media_api.emp_photo`) and documented APEX on-demand bridge | User | Done |

### 3) UX and Regions
- RGN_COMPANY_PROFILE (Form)
- RGN_COMPANY_CONTACT (Form)
- RGN_COMPANY_ADDRESS (Form)
- RGN_COMPANY_FILES (Attachments, optional)

### 4) SQL Query Documentation
Form source:
```sql
SELECT company_id, company_code, company_name, legal_name,
       tax_no, registration_no, email, phone_no,
       website_url, status, created_by, created_dt, upd_by, upd_dt
FROM sufioun_company
WHERE company_id = :P810_COMPANY_ID;
```

### 5) HTML Notes
```html
<div class="company-page">
  <section class="company-profile">Company Profile</section>
  <section class="company-contact">Contact and Address</section>
</div>
```

### 6) CSS Notes
```css
.company-page{display:grid;grid-template-columns:1fr;gap:12px}
.company-profile,.company-contact{background:#fff;border-radius:12px;padding:12px}
```

### 7) Validations and Processes
- Validate company name is required.
- Validate email format and uniqueness if needed.
- Form DML process for sufioun_company.

---

## Page 820: Employee Master

### 1) Page Summary
- Purpose: Maintain employee records, role, joining info, and active status.
- Intended roles: ADMIN, HR_MANAGER.

### 2) Step Log
| Date | Step No | Change Type | Description | Owner | Status |
|---|---|---|---|---|---|
| 2026-04-08 | 1 | Init | Created page documentation skeleton | System | Done |

### 3) UX and Regions
- RGN_EMPLOYEE_CORE (Form)
- RGN_EMPLOYEE_OFFICIAL (Form)
- RGN_EMPLOYEE_ACCESS (Form)
- RGN_EMPLOYEE_AUDIT (Display)

### 4) SQL Query Documentation
Form source:
```sql
SELECT employee_id, employee_code, full_name, father_name,
       cnic_no, gender, date_of_birth, join_date,
       email, mobile_no, job_id, branch_id, department_id,
       manager_employee_id, status, created_by, created_dt, upd_by, upd_dt
FROM sufioun_employees
WHERE employee_id = :P820_EMPLOYEE_ID;
```

Jobs LOV:
```sql
SELECT job_title display_value, job_id return_value
FROM sufioun_jobs
WHERE status = 1
ORDER BY job_title;
```

Branch LOV:
```sql
SELECT branch_name display_value, branch_id return_value
FROM sufioun_branches
WHERE status = 1
ORDER BY branch_name;
```

Employees region SQL (card view):
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

  /* Correct on-demand image URL (EMP_PHOTO uses g_x01) */
  case
    when dbms_lob.getlength(e.photo) > 0 then
      apex_page.get_url(
        p_page    => 0,
        p_request => 'APPLICATION_PROCESS=EMP_PHOTO'
      ) || '&x01=' || apex_util.url_encode(e.employee_id)
    else
      '#APP_FILES#avatar-default.png'
  end as img_url,

  /* One HTML card per row */
  '<article class="empCard" data-emp-id="'||e.employee_id||'">'||

    '<div class="empCard__avatar">'||
      '<a class="empCard__avatarLink" href="'||
        apex_page.get_url(
          p_page   => 44,
          p_items  => 'P44_EMPLOYEE_ID',
          p_values => e.employee_id
        )||'" aria-label="Open CV">'||

        '<img src="'||
          apex_escape.html_attribute(
            case
              when dbms_lob.getlength(e.photo) > 0 then
                apex_page.get_url(
                  p_page    => 0,
                  p_request => 'APPLICATION_PROCESS=EMP_PHOTO'
                ) || '&x01=' || apex_util.url_encode(e.employee_id)
              else
                '#APP_FILES#avatar-default.png'
            end
          )||
        '" alt="Employee photo" loading="lazy">'||

      '</a>'||
    '</div>'||

    '<div class="empCard__main">'||
      '<a class="empCard__name" href="'||
        apex_page.get_url(
          p_page   => 15,
          p_items  => 'P15_EMPLOYEE_ID',
          p_values => e.employee_id
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
          apex_page.get_url(
            p_page   => 44,
            p_items  => 'P44_EMPLOYEE_ID',
            p_values => e.employee_id
          )||'">CV</a>'||

        '<a class="empBtn empBtn--primary" href="'||
          apex_page.get_url(
            p_page   => 9,
            p_items  => 'P9_EMPLOYEE_ID',
            p_values => e.employee_id
          )||'">Edit</a>'||
      '</div>'||
    '</div>'||

  '</article>' as card_html

from sufioun_employees e
left join sufioun_jobs j on j.job_id = e.job_id
left join sufioun_departments d on d.department_id = e.department_id
order by e.first_name, e.last_name;
```

Required APEX Application Process (On Demand):
```plsql
-- Name: EMP_PHOTO
BEGIN
  sufioun_media_api.emp_photo(apex_application.g_x01);
END;
```

Recommended photo URL pattern in page SQL:
```sql
apex_page.get_url(
  p_page    => 0,
  p_request => 'APPLICATION_PROCESS=EMP_PHOTO'
) || '&x01=' || apex_util.url_encode(e.employee_id)
```

Employee page JavaScript:
```javascript
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

### 5) HTML Notes
```html
<div class="employee-page">
  <section class="employee-core">Employee Core Info</section>
  <section class="employee-official">Official Details</section>
</div>
```

### 6) CSS Notes
```css
/* ===== Page background polish ===== */
.t-Body-content{
  background: linear-gradient(180deg, #f7f9fc 0%, #ffffff 55%);
}

/* ===== Hero toolbar ===== */
.empHero{
  display:flex;
  justify-content:space-between;
  align-items:flex-end;
  gap:16px;
  padding: 18px 18px;
  border: 1px solid #e6eaf2;
  border-radius: 16px;
  background:
    radial-gradient(900px 280px at 20% 10%, rgba(37,99,235,.16), transparent 60%),
    radial-gradient(900px 280px at 85% 10%, rgba(16,185,129,.10), transparent 55%),
    #ffffff;
  box-shadow: 0 14px 30px rgba(15,23,42,.06);
  margin: 8px 0 16px;
}

.empHero__titleRow{ display:flex; align-items:center; gap:10px; }
.empHero__title{
  margin:0;
  font-size:22px;
  font-weight:900;
  letter-spacing:.2px;
  color:#0f172a;
}
.empHero__pill{
  display:inline-flex;
  align-items:center;
  height:22px;
  padding:0 10px;
  border-radius:999px;
  font-size:12px;
  font-weight:800;
  color:#1e40af;
  background:#e8f0ff;
  border:1px solid #d7e5ff;
}
.empHero__sub{
  margin-top:4px;
  font-size:12px;
  color:#64748b;
}

.empHero__quick{
  margin-top:12px;
  display:flex;
  gap:10px;
  flex-wrap:wrap;
}
.empStat{
  min-width: 140px;
  padding:10px 12px;
  border-radius:14px;
  border:1px solid #edf1f7;
  background:#ffffff;
}
.empStat__label{
  font-size:11px;
  text-transform:uppercase;
  letter-spacing:.10em;
  color:#64748b;
}
.empStat__value{
  margin-top:3px;
  font-size:18px;
  font-weight:900;
  color:#0f172a;
}

.empViewBtns{ display:flex; gap:8px; }

/* ===== IR chrome cleanup ===== */
#emp_ir .t-Report-report thead{ display:none !important; }
#emp_ir .t-Report-report table,
#emp_ir .t-Report-report tbody,
#emp_ir .t-Report-report tr,
#emp_ir .t-Report-report td{ display:block; }
#emp_ir .t-Report-report td{ padding:0; border:0; }
#emp_ir .t-Report-report tr{ margin:0; }

/* If you want to hide IR toolbar (search/actions/create), uncomment:
#emp_ir .t-IRR-controls,
#emp_ir .t-IRR-toolBar{ display:none !important; }
*/

/* ===== Grid wrapper ===== */
.empCardsWrap{
  display:grid;
  grid-template-columns: repeat(3, minmax(310px, 1fr));
  gap: 14px;
  margin-top: 10px;
}

/* ===== Card ===== */
.empCard{
  display:grid;
  grid-template-columns: 64px 1fr auto;
  gap: 14px;
  padding: 16px;
  border: 1px solid #e7e9ee;
  border-radius: 16px;
  background:#fff;
  box-shadow: 0 16px 34px rgba(15,23,42,.07);
  transition: transform .12s ease, box-shadow .12s ease, border-color .12s ease;
}
.empCard:hover{
  transform: translateY(-1px);
  border-color: #dbe3f2;
  box-shadow: 0 18px 44px rgba(15,23,42,.10);
}
.empCard:focus-within{
  outline: 3px solid rgba(37,99,235,.20);
  outline-offset: 2px;
}

/* Avatar */
.empCard__avatar{ line-height:0; }
.empCard__avatarLink{
  display:inline-block;
  border-radius:18px;
  overflow:hidden;
  line-height:0;
}
.empCard__avatarLink:focus{
  outline:3px solid rgba(37,99,235,.25);
  outline-offset:3px;
}
.empCard__avatar img{
  width:64px;
  height:64px;
  border-radius:18px;
  object-fit:cover;
  display:block;
  border:1px solid #eef0f4;
  background:#f8fafc;
  transition: transform .12s ease;
}
.empCard__avatarLink:hover img{ transform: scale(1.03); }

/* Name + meta */
.empCard__name{
  font-size:16px;
  font-weight:950;
  color:#0b1220;
  text-decoration:none;
}
.empCard__name:hover{ text-decoration:underline; }

.empCard__meta{
  margin-top:3px;
  font-size:12px;
  color:#475569;
}

/* Chips */
.empCard__chips{
  margin-top:10px;
  display:flex;
  flex-wrap:wrap;
  gap:8px;
}
.empChip{
  font-size:12px;
  padding:7px 10px;
  border-radius:999px;
  background:#f1f5f9;
  border:1px solid #e2e8f0;
  color:#0f172a;
}

/* Side panel */
.empCard__side{
  text-align:right;
  min-width: 190px;
}
.empCard__salary{
  font-weight:950;
  color:#0f172a;
  font-size:14px;
}
.empCard__hire{
  margin-top:6px;
  font-size:12px;
  color:#64748b;
}

/* Actions */
.empCard__actions{
  margin-top:12px;
  display:flex;
  justify-content:flex-end;
  gap:8px;
}

.empBtn{
  display:inline-flex;
  align-items:center;
  justify-content:center;
  height: 32px;
  padding: 0 12px;
  border-radius: 12px;
  font-size:12px;
  font-weight:900;
  text-decoration:none;
  border:1px solid transparent;
}
.empBtn--ghost{
  background:#fff;
  border-color:#e2e8f0;
  color:#0f172a;
}
.empBtn--primary{
  background:#2563eb;
  border-color:#2563eb;
  color:#fff;
}
.empBtn--primary:hover{ filter: brightness(.96); }
.empBtn--ghost:hover{ background:#f8fafc; }

/* ===== List mode ===== */
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

/* ===== Responsive ===== */
@media (max-width: 1200px){
  .empCardsWrap{ grid-template-columns: repeat(2, minmax(310px, 1fr)); }
}
@media (max-width: 760px){
  .empHero{ align-items:flex-start; flex-direction:column; }
  .empCardsWrap{ grid-template-columns: 1fr; }
}
```

### 7) Validations and Processes
- Validate employee code uniqueness.
- Validate email and mobile format.
- Form DML process for sufioun_employees.

---

## Page 830: Employee CV

### 1) Page Summary
- Purpose: Store employee CV details: education, certifications, experience, and skills.
- Intended roles: ADMIN, HR_MANAGER.

### 2) Step Log
| Date | Step No | Change Type | Description | Owner | Status |
|---|---|---|---|---|---|
| 2026-04-08 | 1 | Init | Created page documentation skeleton | System | Done |

### 3) UX and Regions
- RGN_CV_HEADER (Form)
- RGN_CV_EDUCATION (Editable IG)
- RGN_CV_EXPERIENCE (Editable IG)
- RGN_CV_SKILLS (Editable IG)
- RGN_CV_ATTACHMENTS (optional)

### 4) SQL Query Documentation
CV header source:
```sql
SELECT cv_id, employee_id, profile_summary, total_experience_years,
       current_salary, expected_salary, notice_period_days,
       created_by, created_dt, upd_by, upd_dt
FROM sufioun_employee_cv
WHERE cv_id = :P830_CV_ID;
```

Education source:
```sql
SELECT edu_id, cv_id, institute_name, degree_name,
       start_year, end_year, grade, status
FROM sufioun_employee_cv_education
WHERE cv_id = :P830_CV_ID;
```

Experience source:
```sql
SELECT exp_id, cv_id, company_name, designation,
       start_date, end_date, is_current, responsibilities
FROM sufioun_employee_cv_experience
WHERE cv_id = :P830_CV_ID;
```

### 5) HTML Notes
```html
<div class="cv-page">
  <section class="cv-header">CV Summary</section>
  <section class="cv-details">Education, Experience, Skills</section>
</div>
```

### 6) CSS Notes
```css
.cv-page{display:grid;grid-template-columns:1fr;gap:12px}
.cv-header,.cv-details{background:#fff;border-radius:12px;padding:12px}
```

### 7) Validations and Processes
- Employee is required for CV.
- Validate education year range and experience dates.
- Form + IG row processing.

---

## Page 840: Jobs Master

### 1) Page Summary
- Purpose: Maintain jobs/positions and map job to department and grade.
- Intended roles: ADMIN, HR_MANAGER.

### 2) Step Log
| Date | Step No | Change Type | Description | Owner | Status |
|---|---|---|---|---|---|
| 2026-04-08 | 1 | Init | Created page documentation skeleton | System | Done |

### 3) UX and Regions
- RGN_JOBS_MASTER (Editable IG or Form)

### 4) SQL Query Documentation
Jobs source:
```sql
SELECT job_id, job_code, job_title, department_id,
       grade_level, min_salary, max_salary, status,
       created_by, created_dt, upd_by, upd_dt
FROM sufioun_jobs;
```

### 5) HTML Notes
```html
<div class="jobs-page">
  <section class="jobs-grid">Jobs Master Grid</section>
</div>
```

### 6) CSS Notes
```css
.jobs-page{background:#fff;border-radius:12px;padding:12px}
```

### 7) Validations and Processes
- Validate job code and title uniqueness.
- Validate min salary is less than or equal to max salary.
- IG automatic row processing.

---

## Page 850: Branch Master

### 1) Page Summary
- Purpose: Maintain branch list, location, and branch-level contact details.
- Intended roles: ADMIN, HR_MANAGER.

### 2) Step Log
| Date | Step No | Change Type | Description | Owner | Status |
|---|---|---|---|---|---|
| 2026-04-08 | 1 | Init | Created page documentation skeleton | System | Done |

### 3) UX and Regions
- RGN_BRANCH_MASTER (Form)
- RGN_BRANCH_ADDRESS (Form)
- RGN_BRANCH_CONTACT (Form)

### 4) SQL Query Documentation
Branch source:
```sql
SELECT branch_id, branch_code, branch_name, company_id,
       branch_type, city_name, address_line,
       email, phone_no, manager_employee_id,
       status, created_by, created_dt, upd_by, upd_dt
FROM sufioun_branches
WHERE branch_id = :P850_BRANCH_ID;
```

Company LOV:
```sql
SELECT company_name display_value, company_id return_value
FROM sufioun_company
WHERE status = 1
ORDER BY company_name;
```

Manager LOV:
```sql
SELECT full_name display_value, employee_id return_value
FROM sufioun_employees
WHERE status = 1
ORDER BY full_name;
```

### 5) HTML Notes
```html
<div class="branch-page">
  <section class="branch-master">Branch Master</section>
  <section class="branch-address">Address and Contact</section>
</div>
```

### 6) CSS Notes
```css
.branch-page{display:grid;grid-template-columns:1fr;gap:12px}
.branch-master,.branch-address{background:#fff;border-radius:12px;padding:12px}
```

### 7) Validations and Processes
- Validate branch code uniqueness.
- Validate company is required.
- Form DML process for sufioun_branches.

---

## How to Use This File for Every Step Log

For each update on any page, add one row in that page Step Log table.

Required fields to log:
1. Date
2. Step No
3. Change Type (Requirement, UI, SQL, Validation, Process, Fix)
4. Description (what changed)
5. Owner
6. Status (Planned, In Progress, Done, Blocked)

## Reusable Section Template

```md
## Page XXX: <Page Name>
### 1) Page Summary
### 2) Step Log
### 3) UX and Regions
### 4) SQL Query Documentation
### 5) HTML Notes
### 6) CSS Notes
### 7) Validations and Processes
```
