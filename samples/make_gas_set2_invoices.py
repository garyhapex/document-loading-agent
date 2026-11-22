# ============================================================
# Script      : samples/make_gas_set2_invoices.py
# Project     : Document Loading Agent (DLA)
# Environment : Gary's PC or Claude's workspace (not the database)
# Changes     : YES - writes six PDF files into samples/invoices-gas-set2/
# Purpose     : Second set of natural gas sample invoices, made
#               11/21/2026 at Gary's request: "I only want 2 to fail,
#               not 4." Four load clean, one has a wrong total
#               (GAS2_05, Total Due 200.00 too high), one is from a
#               vendor not on the active list (GAS2_06, Tallulah).
#               Same look as the first set: bill-to Gary Hall LLC,
#               SAMPLE ONLY in the header, disclaimer at the foot.
# Needs       : Python 3 with reportlab (pip install reportlab)
# Run         : python samples/make_gas_set2_invoices.py
#               from the repository folder
# Author      : Claude for Gary D. Hall
# Date        : 11/21/2026
# ============================================================

import os
from reportlab.lib.pagesizes import letter
from reportlab.lib import colors
from reportlab.pdfgen import canvas

OUT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "invoices-gas-set2")
NAVY = colors.HexColor("#1F3A5F")
GREY = colors.HexColor("#777777")
RULE = colors.HexColor("#BBBBBB")
BAND = colors.HexColor("#EEF1F5")

BILL_TO = ["Gary Hall LLC", "Accounts Payable", "200 Gasworks Way", "Riverbend, GA 30000"]
FOOT = "Sample document for a software demonstration. Fictional vendor, items and amounts; not a real invoice."

VENDORS = {
    "magnolia":      ("Magnolia Pipe & Polymer Supply Co.",  "1840 Extrusion Parkway | Macon, GA 31201 | (478) 555-0126"),
    "chattahoochee": ("Chattahoochee Meter & Regulator LLC", "615 Foundry Street | Columbus, GA 31901 | (706) 555-0184"),
    "pinecrest":     ("Pinecrest Odorant Services Inc.",     "77 Refinery Road | Savannah, GA 31408 | (912) 555-0153"),
    "oconee":        ("Oconee Ridge Utility Locating LLC",   "3302 Surveyor Court | Marietta, GA 30060 | (770) 555-0171"),
    "tallulah":      ("Tallulah Cathodic Protection Co.",    "9 Anode Lane | Gainesville, GA 30501 | (678) 555-0139"),
}

# (file name, vendor key, invoice number, invoice date, due date, lines, total override or None)
INVOICES = [
    ("GAS2_01_clean_magnolia_pipe.pdf", "magnolia", "MPP-48377", "11/12/2026", "12/12/2026", [
        ("1 in IPS SDR 11 MDPE gas pipe, yellow, 500 ft coil", 20, 198.00),
        ("1 in electrofusion coupling", 80, 9.65),
        ("Tracer wire 12 AWG, 500 ft spool", 6, 68.40),
    ], None),
    ("GAS2_02_clean_chattahoochee_meter.pdf", "chattahoochee", "CMR-11042", "11/13/2026", "12/13/2026", [
        ("Commercial rotary gas meter, 1000 CFH", 6, 1140.00),
        ("Service regulator, 1 in, 2 psi outlet", 6, 118.50),
        ("Meter bypass valve set, 1 in", 6, 74.20),
        ("Freight", 1, 210.00),
    ], None),
    ("GAS2_03_clean_pinecrest_odorant.pdf", "pinecrest", "POS-3418", "11/14/2026", "12/14/2026", [
        ("Mercaptan odorant blend, 55 gal drum", 4, 1285.00),
        ("Odorant level monitoring, monthly", 1, 325.00),
        ("Hazmat delivery fee", 1, 175.00),
    ], None),
    ("GAS2_04_clean_oconee_ridge_locating.pdf", "oconee", "ORL-2026-1118", "11/18/2026", "12/18/2026", [
        ("Utility locate tickets, standard", 188, 18.50),
        ("After-hours emergency locates", 5, 65.00),
        ("Mileage, miles", 260, 0.70),
    ], None),
    # Wrong total: lines add up to 3,039.60; the invoice says 3,239.60 (200.00 too high).
    ("GAS2_05_bad_total_chattahoochee_meter.pdf", "chattahoochee", "CMR-11063", "11/19/2026", "12/19/2026", [
        ("Residential diaphragm gas meter, 250 CFH", 24, 86.75),
        ("Service regulator, 3/4 in, 7 in WC outlet", 24, 39.90),
    ], 3239.60),
    # Vendor not on the active list.
    ("GAS2_06_unknown_vendor_tallulah_cathodic.pdf", "tallulah", "TCP-5588", "11/20/2026", "12/20/2026", [
        ("Magnesium anode, 32 lb, packaged", 20, 79.80),
        ("Cathodic protection test station", 8, 38.25),
        ("Pipe-to-soil potential survey, field labor hours", 16, 92.00),
    ], None),
]


def money(x):
    return "{:,.2f}".format(x)


def draw(c, vendor_key, number, inv_date, due_date, lines, total_override):
    name, addr = VENDORS[vendor_key]
    w, h = letter

    # Header band
    c.setFillColor(NAVY)
    c.rect(0, h - 95, w, 95, stroke=0, fill=1)
    c.setFillColor(colors.white)
    c.setFont("Helvetica-Bold", 17)
    c.drawString(54, h - 50, name)
    c.setFont("Helvetica", 8.5)
    c.drawString(54, h - 68, addr)
    c.setFont("Helvetica-Bold", 22)
    c.drawRightString(w - 54, h - 52, "INVOICE")
    c.setFont("Helvetica-Bold", 9)
    c.drawRightString(w - 54, h - 68, "SAMPLE ONLY")

    # Bill to
    y = h - 128
    c.setFillColor(colors.black)
    c.setFont("Helvetica-Bold", 9)
    c.drawString(54, y, "Bill To")
    c.setFont("Helvetica", 9)
    for i, t in enumerate(BILL_TO):
        c.drawString(54, y - 15 - 15 * i, t)

    # Invoice facts
    facts = [("Invoice Number:", number), ("Invoice Date:", inv_date), ("Due Date:", due_date), ("Terms:", "Net 30")]
    for i, (k, v) in enumerate(facts):
        c.setFont("Helvetica-Bold", 9)
        c.drawRightString(w - 170, y - 15 * i, k)
        c.setFont("Helvetica", 9)
        c.drawRightString(w - 54, y - 15 * i, v)

    # Table header
    ty = h - 240
    c.setFillColor(BAND)
    c.rect(54, ty - 6, w - 108, 20, stroke=0, fill=1)
    c.setFillColor(colors.black)
    c.setFont("Helvetica-Bold", 9)
    c.drawString(60, ty, "Line")
    c.drawString(96, ty, "Description")
    c.drawRightString(360, ty, "Quantity")
    c.drawRightString(450, ty, "Unit Price")
    c.drawRightString(w - 54, ty, "Amount")

    c.setFont("Helvetica", 9)
    subtotal = 0.0
    for i, (desc, qty, price) in enumerate(lines):
        ly = ty - 22 - 22 * i
        amt = round(qty * price, 2)
        subtotal += amt
        c.drawString(60, ly, str(i + 1))
        c.drawString(96, ly, desc)
        c.drawRightString(360, ly, str(qty))
        c.drawRightString(450, ly, money(price))
        c.drawRightString(w - 54, ly, money(amt))
        c.setStrokeColor(RULE)
        c.setLineWidth(0.4)
        c.line(54, ly - 7, w - 54, ly - 7)

    subtotal = round(subtotal, 2)
    tax = 0.00
    total = total_override if total_override is not None else round(subtotal + tax, 2)
    sy = ty - 22 - 22 * len(lines) - 20
    c.setFont("Helvetica", 9)
    c.drawRightString(w - 140, sy, "Subtotal:")
    c.drawRightString(w - 54, sy, money(subtotal))
    c.drawRightString(w - 140, sy - 16, "Tax:")
    c.drawRightString(w - 54, sy - 16, money(tax))
    c.setFont("Helvetica-Bold", 10)
    c.drawRightString(w - 140, sy - 34, "Total Due:")
    c.drawRightString(w - 54, sy - 34, "$" + money(total))

    # Foot
    c.setFillColor(GREY)
    c.setFont("Helvetica", 7.5)
    c.drawString(54, 40, FOOT)
    c.showPage()


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    for fname, vkey, number, inv_date, due_date, lines, override in INVOICES:
        path = os.path.join(OUT_DIR, fname)
        c = canvas.Canvas(path, pagesize=letter)
        draw(c, vkey, number, inv_date, due_date, lines, override)
        c.save()
        print("wrote", path, os.path.getsize(path), "bytes")


if __name__ == "__main__":
    main()
