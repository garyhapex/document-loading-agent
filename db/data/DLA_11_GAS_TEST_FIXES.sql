/* ============================================================
   Script      : DLA_11_GAS_TEST_FIXES.sql
   Project     : Document Loading Agent (DLA) - Phase 3
   Environment : DEV (GHAPEXAPPS_ATP_DEV) - do NOT run on PRD
   Changes     : YES
                 1. DLA_SETTINGS: replaces EXTRACTION_PROMPT, the
                    instruction sent to the AI model.
                 2. DLA_INVOICES: sets LOADED_BY to the approver
                    on invoices already loaded.
   Purpose     : Two fixes from the natural gas invoice test.
                 1. GAS_04 has no invoice date. The model put the
                    due date (12/12/2026) in the invoice date
                    field, so the agent saw a date and loaded the
                    invoice. The new prompt tells the model the
                    invoice date is only the date beside the
                    Invoice Date label, and never another date.
                    It also tells the model to copy names letter
                    by letter: it read "Cathodic" as "Catholic"
                    on GAS_06.
                    Second version, same evening: the first
                    version made the model return dates the way
                    the invoice prints them (12/12/2026). The
                    prompt now says to write every date as
                    YYYY-MM-DD.
                 2. LOADED_BY showed the database user instead of
                    AGENT. DLA_PKG.LOAD_INVOICE now stores the
                    approver; this corrects the rows loaded
                    before that change.
   Schema      : WKSP_WKSPPRDWORKSPACE (workspace DEV_WORKSPACE)
   Run as      : WKSP_WKSPPRDWORKSPACE or ADMIN, SQL Developer,
                 F5 (Run Script)
   Run after   : DLA_02_PACKAGE.sql
   Re-runnable : yes
   Author      : Claude for Gary D. Hall
   Date        : 11/19/2026
   ============================================================ */

SET DEFINE OFF
SET LINESIZE 220
SET PAGESIZE 200
SET SERVEROUTPUT ON
COLUMN setting_name   FORMAT A20
COLUMN setting_value  FORMAT A120 WORD_WRAPPED
COLUMN vendor_name    FORMAT A36
COLUMN invoice_number FORMAT A14
COLUMN loaded_by      FORMAT A22

ALTER SESSION SET CURRENT_SCHEMA = WKSP_WKSPPRDWORKSPACE;

/* ------------------------------------------------------------
   Step 1  : Replace the instruction sent to the AI model
   Purpose : Uses DLA_PKG.SET_SETTING so the change is logged in
             DLA_AUDIT_LOG. Rolls back and re-raises on failure.
   ------------------------------------------------------------ */
BEGIN
    dla_pkg.set_setting(
        p_setting_name  => 'EXTRACTION_PROMPT',
        p_setting_value => q'[You are reading a vendor invoice. Return only one JSON object, with no other text, using exactly these keys: vendor_name (string), invoice_number (string), invoice_date (string, YYYY-MM-DD), due_date (string, YYYY-MM-DD), subtotal (number), tax (number), total (number), line_items (array of objects with these keys: line_number (number), description (string), quantity (number), unit_price (number), amount (number)). Use null for any value that is not printed on the invoice. Do not calculate or guess missing values. invoice_date is only the date printed beside the label Invoice Date or Date. If that label has no date beside it, invoice_date must be null. Never use the due date, a ship date, a service date or an order date as the invoice date. Write every date as YYYY-MM-DD, even when the invoice prints it another way. Copy the vendor name and the invoice number exactly as printed, letter by letter. Copy numbers exactly as printed, without currency symbols or thousands separators.]'
    );
    COMMIT;
    DBMS_OUTPUT.PUT_LINE('EXTRACTION_PROMPT replaced.');
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        DBMS_OUTPUT.PUT_LINE('FAILED: ' || SQLERRM);
        RAISE;
END;
/

/* ------------------------------------------------------------
   Step 2  : LOADED_BY = the approver, on invoices already loaded
   Purpose : Only rows where the two differ are changed.
   ------------------------------------------------------------ */
DECLARE
    l_rows  NUMBER;
BEGIN
    UPDATE dla_invoices i
    SET    i.loaded_by = (SELECT h.reviewed_by
                          FROM   dla_stg_headers h
                          WHERE  h.stg_header_id = i.stg_header_id)
    WHERE  EXISTS (SELECT 1
                   FROM   dla_stg_headers h
                   WHERE  h.stg_header_id = i.stg_header_id
                   AND    h.reviewed_by IS NOT NULL
                   AND    h.reviewed_by <> i.loaded_by);

    l_rows := SQL%ROWCOUNT;

    dla_pkg.log_audit(
        p_action  => 'DATA_FIX',
        p_details => 'DLA_11: LOADED_BY set to the approver on ' || l_rows || ' loaded invoice(s).'
    );

    COMMIT;
    DBMS_OUTPUT.PUT_LINE(l_rows || ' loaded invoice(s) corrected.');
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        dla_pkg.log_audit(
            p_action  => 'DATA_FIX_ERROR',
            p_details => 'DLA_11 step 2 failed: ' || SQLERRM
        );
        DBMS_OUTPUT.PUT_LINE('FAILED: ' || SQLERRM);
        RAISE;
END;
/

/* ------------------------------------------------------------
   Check 1 : The prompt now in use
   Purpose : Expect the text to include "letter by letter".
   ------------------------------------------------------------ */
SELECT s.setting_name,
       s.setting_value
FROM   dla_settings s
WHERE  s.setting_name = 'EXTRACTION_PROMPT';

/* ------------------------------------------------------------
   Check 2 : Loaded invoices
   Purpose : Expect LOADED_BY = AGENT on every row.
   ------------------------------------------------------------ */
SELECT i.invoice_id,
       v.vendor_name,
       i.invoice_number,
       i.invoice_date,
       i.total,
       i.loaded_by
FROM   dla_invoices i,
       dla_vendors  v
WHERE  v.vendor_id = i.vendor_id
ORDER  BY i.invoice_id;
