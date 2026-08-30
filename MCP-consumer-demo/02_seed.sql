/*=====================================================================
  Bay State Supply — demo database
  Introduction to MCP  |  Demo 1: Vendor Invoice Reconciliation
  Author: Tracey Kroll
  Repo:    https://github.com/traceykroll/IntroductionToMCP
  License: MIT

  All data is invented. Vendors, contacts, items and pricing are
  fictional and any resemblance to real companies is coincidental.

  Idempotent: deletes and reloads the [purchasing] tables.
  Run after 01_schema.sql.

  The four vendor invoices being reconciled are NOT in this data -  they arrive
  as files. What is here is what Bay State Supply already knows:  what was ordered, 
  what arrived, what was agreed, and what has already been paid.
=====================================================================*/

USE BayStateSupply;
GO

SET NOCOUNT ON;

/*---------------------------------------------------------------------
  Clear existing rows (child to parent)
---------------------------------------------------------------------*/
DELETE FROM purchasing.Invoice;
DELETE FROM purchasing.ReceiptLine;
DELETE FROM purchasing.ContractPrice;
DELETE FROM purchasing.PurchaseOrderLine;
DELETE FROM purchasing.PurchaseOrderHeader;
DELETE FROM purchasing.Item;
DELETE FROM purchasing.Vendor;
GO

/*---------------------------------------------------------------------
  Vendors
---------------------------------------------------------------------*/
INSERT INTO purchasing.Vendor
    (VendorID, VendorCode, VendorName, ContactName, ContactEmail, PaymentTerms, IsActive)
VALUES
    (1, 'HOLLIS', 'Hollis Fasteners',     'Marta Reyes',   'ar@hollisfasteners.example.com', 'Net 30', 1),
    (2, 'SUDBRY', 'Sudbury Packaging',    'Dev Patel',     'billing@sudburypack.example.com', 'Net 30', 1),
    (3, 'TILTON', 'Tilton Metals',        'Joanne Kirby',  'ar@tiltonmetals.example.com',      'Net 45', 1),
    (4, 'BRADDK', 'Braddock Components',  'Sean Whitaker', 'invoices@braddock.example.com',    'Net 30', 1);
GO

/*---------------------------------------------------------------------
  Items

  Items 4, 5, 6, 7 and 14 are bought by the case. Their PO quantities
  and prices are per case and need UOMConv applied before they can be
  compared with an invoice that bills individual units.
---------------------------------------------------------------------*/
INSERT INTO purchasing.Item
    (ItemID, ItemCode, ItemDescription, BaseUOM, PurchaseUOM, UOMConv, IsActive)
VALUES
    ( 1, 'HB-0500-G5', 'Hex Bolt 1/2-13 x 2in, Grade 5, Zinc',      'EA', 'EA',   1, 1),
    ( 2, 'WS-0500-G8', 'Flat Washer 1/2in, Grade 8, Zinc',          'EA', 'EA',   1, 1),
    ( 3, 'NT-0500-NY', 'Nylon Lock Nut 1/2-13, Zinc',               'EA', 'EA',   1, 1),
    ( 4, 'GL-NIT-LG',  'Nitrile Gloves, Blue, Large',               'EA', 'CS', 100, 1),
    ( 5, 'GL-NIT-MD',  'Nitrile Gloves, Blue, Medium',              'EA', 'CS', 100, 1),
    ( 6, 'BX-1206-KR', 'Corrugated Box 12x12x6in, Kraft',           'EA', 'CS',  25, 1),
    ( 7, 'TP-0200-CL', 'Packing Tape 2in Clear, 110yd',             'EA', 'CS',  36, 1),
    ( 8, 'SA-0202-25', 'Steel Angle 2x2x1/4in, 20ft',               'EA', 'EA',   1, 1),
    ( 9, 'SF-0250-20', 'Steel Flat Bar 1/4x2in, 20ft',              'EA', 'EA',   1, 1),
    (10, 'ST-1000-16', 'Steel Tube 1in Square, 16ga, 24ft',         'EA', 'EA',   1, 1),
    (11, 'BR-6205-2R', 'Ball Bearing 6205-2RS',                     'EA', 'EA',   1, 1),
    (12, 'BR-6206-2R', 'Ball Bearing 6206-2RS',                     'EA', 'EA',   1, 1),
    (13, 'CH-0040-10', 'Roller Chain #40, 10ft',                    'EA', 'EA',   1, 1),
    (14, 'SG-CLR-AF',  'Safety Glasses, Clear, Anti-Fog',           'EA', 'CS',  12, 1);
GO

/*---------------------------------------------------------------------
  Contract pricing

  Most items have held one price all year. Two Hollis items have
  had a price change mid-contract, so their history is split into
  two effective-dated rows.
---------------------------------------------------------------------*/
INSERT INTO purchasing.ContractPrice
    (ContractPriceID, VendorID, ItemID, ContractPrice, PriceUOM, EffectiveFrom, EffectiveTo, ContractRef)
VALUES
    -- Hollis Fasteners: hex bolt, increased 1 July 2026
    ( 1, 1,  1,  3.8500, 'EA', '2026-01-01', '2026-06-30', 'BSS-HF-2026'),
    ( 2, 1,  1,  4.1000, 'EA', '2026-07-01', NULL,         'BSS-HF-2026'),

    -- Hollis Fasteners: flat washer, increased 1 May 2026
    ( 3, 1,  2,  0.9300, 'EA', '2026-01-01', '2026-04-30', 'BSS-HF-2026'),
    ( 4, 1,  2,  0.9600, 'EA', '2026-05-01', NULL,         'BSS-HF-2026'),

    -- Hollis Fasteners: unchanged
    ( 5, 1,  3,  0.6200, 'EA', '2026-01-01', NULL,         'BSS-HF-2026'),

    -- Sudbury Packaging: priced by the case
    ( 6, 2,  4, 48.0000, 'CS', '2026-01-01', NULL,         'BSS-SP-2026'),
    ( 7, 2,  5, 48.0000, 'CS', '2026-01-01', NULL,         'BSS-SP-2026'),
    ( 8, 2,  6, 31.2500, 'CS', '2026-01-01', NULL,         'BSS-SP-2026'),
    ( 9, 2,  7, 52.8000, 'CS', '2026-01-01', NULL,         'BSS-SP-2026'),
    (10, 2, 14, 38.4000, 'CS', '2026-01-01', NULL,         'BSS-SP-2026'),

    -- Tilton Metals
    (11, 3,  8, 46.2000, 'EA', '2026-01-01', NULL,         'BSS-TM-2026'),
    (12, 3,  9, 31.7500, 'EA', '2026-01-01', NULL,         'BSS-TM-2026'),
    (13, 3, 10, 58.4000, 'EA', '2026-01-01', NULL,         'BSS-TM-2026'),

    -- Braddock Components
    (14, 4, 11, 84.5000, 'EA', '2026-01-01', NULL,         'BSS-BC-2026'),
    (15, 4, 12, 96.7500, 'EA', '2026-01-01', NULL,         'BSS-BC-2026'),
    (16, 4, 13, 41.9000, 'EA', '2026-01-01', NULL,         'BSS-BC-2026');
GO

/*---------------------------------------------------------------------
  Purchase orders

  POID 1-4 are the orders the four invoices on Sam's desk relate to.
  POID 10-23 are the rest of the quarter's ordering activity.
---------------------------------------------------------------------*/
INSERT INTO purchasing.PurchaseOrderHeader
    (POID, PONumber, VendorID, OrderDate, RequiredDate, POStatus, BuyerName)
VALUES
    ( 1, 'PO-4462', 4, '2026-05-12', '2026-05-29', 'Closed',   'Ray Colburn'),
    ( 2, 'PO-4468', 2, '2026-06-11', '2026-07-01', 'Received', 'Ray Colburn'),
    ( 3, 'PO-4471', 1, '2026-06-18', '2026-07-08', 'Received', 'Ray Colburn'),
    ( 4, 'PO-4475', 3, '2026-06-24', '2026-07-16', 'Received', 'Nadia Okonkwo'),

    (10, 'PO-4440', 1, '2026-04-07', '2026-04-24', 'Closed',   'Ray Colburn'),
    (11, 'PO-4443', 2, '2026-04-14', '2026-05-01', 'Closed',   'Ray Colburn'),
    (12, 'PO-4447', 3, '2026-04-21', '2026-05-12', 'Closed',   'Nadia Okonkwo'),
    (13, 'PO-4451', 4, '2026-04-28', '2026-05-15', 'Closed',   'Ray Colburn'),
    (14, 'PO-4455', 1, '2026-05-05', '2026-05-22', 'Closed',   'Ray Colburn'),
    (15, 'PO-4458', 2, '2026-05-08', '2026-05-27', 'Closed',   'Nadia Okonkwo'),
    (16, 'PO-4460', 3, '2026-05-11', '2026-06-01', 'Closed',   'Nadia Okonkwo'),
    (17, 'PO-4465', 4, '2026-05-19', '2026-06-05', 'Closed',   'Ray Colburn'),
    (18, 'PO-4470', 2, '2026-06-15', '2026-07-02', 'Closed',   'Ray Colburn'),
    (19, 'PO-4473', 3, '2026-06-22', '2026-07-14', 'Closed',   'Nadia Okonkwo'),
    (20, 'PO-4477', 4, '2026-06-29', '2026-07-16', 'Closed',   'Ray Colburn'),
    (21, 'PO-4480', 1, '2026-07-06', '2026-07-23', 'Received', 'Ray Colburn'),
    (22, 'PO-4483', 2, '2026-07-13', '2026-07-30', 'Received', 'Nadia Okonkwo'),
    (23, 'PO-4486', 3, '2026-07-20', '2026-08-10', 'Received', 'Nadia Okonkwo');
GO

/*---------------------------------------------------------------------
  Purchase order lines

  Prices are the contract price in force on the order date.
---------------------------------------------------------------------*/
INSERT INTO purchasing.PurchaseOrderLine
    (POLineID, POID, LineNumber, ItemID, QtyOrdered, OrderUOM, UnitPrice)
VALUES
    -- PO-4462  Braddock, ordered 12 May
    (  1,  1, 1, 11,   60.00, 'EA', 84.5000),

    -- PO-4468  Sudbury, ordered 11 June
    (  2,  2, 1,  4,   40.00, 'CS', 48.0000),
    (  3,  2, 2,  6,   30.00, 'CS', 31.2500),

    -- PO-4471  Hollis, ordered 18 June
    (  4,  3, 1,  1, 2000.00, 'EA',  3.8500),
    (  5,  3, 2,  2, 3000.00, 'EA',  0.9600),

    -- PO-4475  Tilton, ordered 24 June
    (  6,  4, 1,  8,  150.00, 'EA', 46.2000),
    (  7,  4, 2, 10,   60.00, 'EA', 58.4000),

    -- Remaining activity
    (100, 10, 1,  3, 5000.00, 'EA',  0.6200),
    (101, 11, 1,  7,   24.00, 'CS', 52.8000),
    (102, 12, 1,  9,  120.00, 'EA', 31.7500),
    (103, 13, 1, 13,   45.00, 'EA', 41.9000),
    (104, 14, 1,  3, 3200.00, 'EA',  0.6200),
    (105, 15, 1, 14,   60.00, 'CS', 38.4000),
    (106, 16, 1,  8,   90.00, 'EA', 46.2000),
    (107, 17, 1, 12,   35.00, 'EA', 96.7500),
    (108, 18, 1,  5,   25.00, 'CS', 48.0000),
    (109, 19, 1, 10,   40.00, 'EA', 58.4000),
    (110, 20, 1, 11,   25.00, 'EA', 84.5000),
    (111, 21, 1,  3, 4000.00, 'EA',  0.6200),
    (112, 22, 1,  6,   45.00, 'CS', 31.2500),
    (113, 23, 1,  9,  175.00, 'EA', 31.7500);
GO

/*---------------------------------------------------------------------
  Receipts

  Every line above was received complete.
---------------------------------------------------------------------*/
INSERT INTO purchasing.ReceiptLine
    (ReceiptLineID, ReceiptNumber, POLineID, ReceiptDate, QtyReceived, ReceiptUOM, ReceivedBy)
VALUES
    (  1, 'RCV-20514',   1, '2026-05-28',   60.00, 'EA', 'T. Alvarez'),
    (  2, 'RCV-20661',   2, '2026-06-29',   40.00, 'CS', 'T. Alvarez'),
    (  3, 'RCV-20661',   3, '2026-06-29',   30.00, 'CS', 'T. Alvarez'),
    (  4, 'RCV-20718',   4, '2026-07-06', 2000.00, 'EA', 'M. Doyle'),
    (  5, 'RCV-20718',   5, '2026-07-06', 3000.00, 'EA', 'M. Doyle'),
    (  6, 'RCV-20779',   6, '2026-07-14',  150.00, 'EA', 'T. Alvarez'),
    (  7, 'RCV-20779',   7, '2026-07-14',   60.00, 'EA', 'T. Alvarez'),

    (100, 'RCV-20233', 100, '2026-04-23', 5000.00, 'EA', 'M. Doyle'),
    (101, 'RCV-20287', 101, '2026-04-30',   24.00, 'CS', 'T. Alvarez'),
    (102, 'RCV-20341', 102, '2026-05-11',  120.00, 'EA', 'T. Alvarez'),
    (103, 'RCV-20390', 103, '2026-05-14',   45.00, 'EA', 'M. Doyle'),
    (104, 'RCV-20428', 104, '2026-05-21', 3200.00, 'EA', 'M. Doyle'),
    (105, 'RCV-20470', 105, '2026-05-26',   60.00, 'CS', 'T. Alvarez'),
    (106, 'RCV-20495', 106, '2026-05-29',   90.00, 'EA', 'T. Alvarez'),
    (107, 'RCV-20548', 107, '2026-06-04',   35.00, 'EA', 'M. Doyle'),
    (108, 'RCV-20690', 108, '2026-07-01',   25.00, 'CS', 'T. Alvarez'),
    (109, 'RCV-20744', 109, '2026-07-13',   40.00, 'EA', 'T. Alvarez'),
    (110, 'RCV-20802', 110, '2026-07-15',   25.00, 'EA', 'M. Doyle'),
    (111, 'RCV-20846', 111, '2026-07-22', 4000.00, 'EA', 'M. Doyle'),
    (112, 'RCV-20881', 112, '2026-07-29',   45.00, 'CS', 'T. Alvarez'),
    (113, 'RCV-20934', 113, '2026-08-07',  175.00, 'EA', 'T. Alvarez');
GO

/*---------------------------------------------------------------------
  Invoices already entered for payment

  This is Bay State Supply's payables history. The four invoices Sam
  is working through today are not here yet - they are still files.
---------------------------------------------------------------------*/
INSERT INTO purchasing.Invoice
    (InvoiceID, InvoiceNumber, VendorID, POID, InvoiceDate, InvoiceAmount, PaymentStatus, PaidDate, CheckNumber)
VALUES
    (  1, 'BC-77120',      4,  1, '2026-06-01',  5070.00, 'Paid', '2026-06-30', '104882'),

    ( 10, 'HF-2026-0902',  1, 10, '2026-04-27',  3100.00, 'Paid', '2026-05-27', '104611'),
    ( 11, 'SP-87004',      2, 11, '2026-05-04',  1267.20, 'Paid', '2026-06-03', '104638'),
    ( 12, 'TM-5312',       3, 12, '2026-05-15',  3810.00, 'Paid', '2026-06-29', '104795'),
    ( 13, 'BC-76840',      4, 13, '2026-05-18',  1885.50, 'Paid', '2026-06-17', '104702'),
    ( 14, 'HF-2026-1015',  1, 14, '2026-05-26',  1984.00, 'Paid', '2026-06-25', '104744'),
    ( 15, 'SP-87466',      2, 15, '2026-05-29',  2304.00, 'Paid', '2026-06-28', '104778'),
    ( 16, 'TM-5408',       3, 16, '2026-06-02',  4158.00, 'Paid', '2026-07-17', '104903'),
    ( 17, 'BC-77038',      4, 17, '2026-06-08',  3386.25, 'Paid', '2026-07-08', '104861'),
    ( 18, 'SP-87921',      2, 18, '2026-07-06',  1200.00, 'Paid', '2026-08-05', '105027'),
    ( 19, 'TM-5501',       3, 19, '2026-07-16',  2336.00, 'Paid', '2026-08-30', '105114'),
    ( 20, 'BC-77245',      4, 20, '2026-07-20',  2112.50, 'Open', NULL,         NULL),
    ( 21, 'HF-2026-1290',  1, 21, '2026-07-27',  2480.00, 'Open', NULL,         NULL),
    ( 22, 'SP-88490',      2, 22, '2026-08-03',  1406.25, 'Open', NULL,         NULL);
GO

PRINT 'Seed data loaded.';
GO

/*=====================================================================
  Verification

  Run these to confirm the data loaded as intended before a demo.
  Each should return the row counts noted in the comment.
=====================================================================*/

-- Row counts: 4 vendors, 14 items, 18 POs, 21 PO lines, 21 receipts,
-- 16 contract prices, 14 invoices.
SELECT 'Vendor' AS TableName, COUNT(*) AS Rows FROM purchasing.Vendor
UNION ALL SELECT 'Item',            COUNT(*) FROM purchasing.Item
UNION ALL SELECT 'ContractPrice',   COUNT(*) FROM purchasing.ContractPrice
UNION ALL SELECT 'POHeader',        COUNT(*) FROM purchasing.PurchaseOrderHeader
UNION ALL SELECT 'POLine',          COUNT(*) FROM purchasing.PurchaseOrderLine
UNION ALL SELECT 'ReceiptLine',     COUNT(*) FROM purchasing.ReceiptLine
UNION ALL SELECT 'Invoice',         COUNT(*) FROM purchasing.Invoice;
GO

-- Every PO line should resolve to exactly one contract price, and the
-- PO unit price should equal it. No rows means everything ties out.
SELECT PONumber, LineNumber, ItemCode, OrderDate,
       POUnitPrice, ContractUnitPrice, ContractEffectiveFrom
FROM purchasing.vw_POReconciliation
WHERE ContractUnitPrice IS NULL
   OR POUnitPrice <> ContractUnitPrice;
GO

-- The two Hollis items on PO-4471 should resolve to different
-- contract rows: the bolt to the price that ended 30 June, the washer
-- to the price that began 1 May.
SELECT PONumber, OrderDate, ItemCode, POUnitPrice,
       ContractUnitPrice, ContractEffectiveFrom, ContractEffectiveTo
FROM purchasing.vw_POReconciliation
WHERE PONumber = 'PO-4471'
ORDER BY LineNumber;
GO

-- Case-priced lines and their per-unit equivalents.
SELECT PONumber, ItemCode, PurchaseUOM, UOMConv,
       QtyOrdered, QtyOrdered * UOMConv          AS QtyIndividualUnits,
       POUnitPrice, POUnitPrice / UOMConv        AS PricePerIndividualUnit
FROM purchasing.vw_POReconciliation
WHERE PurchaseUOM = 'CS'
ORDER BY PONumber, LineNumber;
GO

-- Payment history for PO-4462.
SELECT InvoiceNumber, InvoiceDate, InvoiceAmount, PaymentStatus, PaidDate, CheckNumber
FROM purchasing.Invoice
WHERE POID = 1;
GO
