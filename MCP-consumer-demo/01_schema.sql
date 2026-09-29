/*=====================================================================
  Bay State Supply — demo database
  Introduction to MCP  |  Demo 1: Vendor Invoice Reconciliation
  Author: Tracey Kroll
  Repo:    https://github.com/traceykroll/IntroductionToMCP
  License: MIT

  Bay State Supply is a fictional industrial distributor. All
  vendors, items, pricing and contacts are invented sample data.   
  
  This script owns the [purchasing] schema only. It creates the
  database if it does not already exist, and never drops it, so it can
  be run alongside the other demo in this repository without either
  one disturbing the other.

  Idempotent: safe to rerun. Drops and recreates all objects.
  Run order:  01_schema.sql  ->  02_seed.sql
  Tested on SQL Server 2022 (Developer Edition, Linux container).
=====================================================================*/

USE master;
GO

IF DB_ID('BayStateSupply') IS NULL
BEGIN
    PRINT 'Creating database BayStateSupply...';
    CREATE DATABASE BayStateSupply;
END
ELSE
    PRINT 'Database BayStateSupply already exists - leaving it in place.';
GO

USE BayStateSupply;
GO

IF SCHEMA_ID('purchasing') IS NULL
    EXEC ('CREATE SCHEMA purchasing');
GO

/*---------------------------------------------------------------------
  1. Drop this demo's objects only (FK-safe order)

     Scoped to [purchasing]. Nothing outside this schema is touched.
---------------------------------------------------------------------*/
DROP VIEW  IF EXISTS purchasing.vw_POReconciliation;
DROP TABLE IF EXISTS purchasing.Invoice;
DROP TABLE IF EXISTS purchasing.ReceiptLine;
DROP TABLE IF EXISTS purchasing.ContractPrice;
DROP TABLE IF EXISTS purchasing.PurchaseOrderLine;
DROP TABLE IF EXISTS purchasing.PurchaseOrderHeader;
DROP TABLE IF EXISTS purchasing.Item;
DROP TABLE IF EXISTS purchasing.Vendor;
GO

/*---------------------------------------------------------------------
  2. Vendor
     Supplier master. ContactEmail is the vendor's accounts payable
     contact for billing correspondence and disputes.
---------------------------------------------------------------------*/
CREATE TABLE purchasing.Vendor (
    VendorID        INT           NOT NULL PRIMARY KEY,
    VendorCode      VARCHAR(10)   NOT NULL UNIQUE,
    VendorName      VARCHAR(100)  NOT NULL,
    ContactName     VARCHAR(100)  NULL,
    ContactEmail    VARCHAR(150)  NULL,
    PaymentTerms    VARCHAR(30)   NULL,
    IsActive        BIT           NOT NULL
        CONSTRAINT DF_Vendor_IsActive DEFAULT (1)
);
GO

/*---------------------------------------------------------------------
  3. Item
     Product master.

     An item is counted in one unit but is often bought in another.
     Nitrile gloves are counted one at a time in the warehouse but
     ordered by the case, so a PO line for 20 cases is really 240
     individual gloves.

     UOM is unit of measure. Two codes are used here:
         EA   each  - one individual unit
         CS   case  - a box containing a fixed number of units

     BaseUOM      the unit the warehouse counts in       always EA
     PurchaseUOM  the unit the item is bought in         EA or CS
     UOMConv      individual units per purchase unit

     A case of 12:  BaseUOM = EA, PurchaseUOM = CS, UOMConv = 12.
     Bought singly: BaseUOM = EA, PurchaseUOM = EA, UOMConv = 1.

     Quantities and prices on a PO line are stated in PurchaseUOM, so
     they must be converted with UOMConv before they can be compared
     against an invoice that bills individual units.
---------------------------------------------------------------------*/
CREATE TABLE purchasing.Item (
    ItemID          INT           NOT NULL PRIMARY KEY,
    ItemCode        VARCHAR(20)   NOT NULL UNIQUE,
    ItemDescription VARCHAR(200)  NOT NULL,
    BaseUOM         VARCHAR(10)   NOT NULL,      -- EA = each (one unit)
    PurchaseUOM     VARCHAR(10)   NOT NULL,      -- EA = each, CS = case
    UOMConv         DECIMAL(10,4) NOT NULL       -- units per purchase unit: 12 = case of 12
        CONSTRAINT DF_Item_UOMConv DEFAULT (1),
    IsActive        BIT           NOT NULL
        CONSTRAINT DF_Item_IsActive DEFAULT (1),
    CONSTRAINT CK_Item_UOMConv CHECK (UOMConv > 0)
);
GO

/*---------------------------------------------------------------------
  4. Purchase orders
     Header holds order-level facts, lines hold the per-item detail.
     Contract pricing is determined by the header's OrderDate.
---------------------------------------------------------------------*/
CREATE TABLE purchasing.PurchaseOrderHeader (
    POID            INT           NOT NULL PRIMARY KEY,
    PONumber        VARCHAR(20)   NOT NULL UNIQUE,
    VendorID        INT           NOT NULL
        CONSTRAINT FK_POHeader_Vendor REFERENCES purchasing.Vendor(VendorID),
    OrderDate       DATE          NOT NULL,
    RequiredDate    DATE          NULL,
    POStatus        VARCHAR(20)   NOT NULL
        CONSTRAINT DF_POHeader_Status DEFAULT ('Open'),
    BuyerName       VARCHAR(100)  NULL
);
GO

CREATE INDEX IX_POHeader_Vendor
    ON purchasing.PurchaseOrderHeader (VendorID, OrderDate);
GO

CREATE TABLE purchasing.PurchaseOrderLine (
    POLineID        INT           NOT NULL PRIMARY KEY,
    POID            INT           NOT NULL
        CONSTRAINT FK_POLine_Header REFERENCES purchasing.PurchaseOrderHeader(POID),
    LineNumber      INT           NOT NULL,
    ItemID          INT           NOT NULL
        CONSTRAINT FK_POLine_Item REFERENCES purchasing.Item(ItemID),
    QtyOrdered      DECIMAL(12,2) NOT NULL,
    OrderUOM        VARCHAR(10)   NOT NULL,
    UnitPrice       DECIMAL(12,4) NOT NULL,
    ExtendedAmount  AS (QtyOrdered * UnitPrice) PERSISTED,
    CONSTRAINT UQ_POLine_Line UNIQUE (POID, LineNumber)
);
GO

CREATE INDEX IX_POLine_Item
    ON purchasing.PurchaseOrderLine (ItemID);
GO

/*---------------------------------------------------------------------
  5. Receipts
     Goods received against a PO line. The quantity received may differ
     from the quantity ordered.
---------------------------------------------------------------------*/
CREATE TABLE purchasing.ReceiptLine (
    ReceiptLineID   INT           NOT NULL PRIMARY KEY,
    ReceiptNumber   VARCHAR(20)   NOT NULL,
    POLineID        INT           NOT NULL
        CONSTRAINT FK_Receipt_POLine REFERENCES purchasing.PurchaseOrderLine(POLineID),
    ReceiptDate     DATE          NOT NULL,
    QtyReceived     DECIMAL(12,2) NOT NULL,
    ReceiptUOM      VARCHAR(10)   NOT NULL,
    ReceivedBy      VARCHAR(100)  NULL
);
GO

CREATE INDEX IX_Receipt_POLine
    ON purchasing.ReceiptLine (POLineID);
GO

/*---------------------------------------------------------------------
  6. Contract pricing
     Negotiated prices under a supply agreement, effective-dated so
     price changes over the life of the contract are preserved.
---------------------------------------------------------------------*/
CREATE TABLE purchasing.ContractPrice (
    ContractPriceID INT           NOT NULL PRIMARY KEY,
    VendorID        INT           NOT NULL
        CONSTRAINT FK_ContractPrice_Vendor REFERENCES purchasing.Vendor(VendorID),
    ItemID          INT           NOT NULL
        CONSTRAINT FK_ContractPrice_Item REFERENCES purchasing.Item(ItemID),
    ContractPrice   DECIMAL(12,4) NOT NULL,
    PriceUOM        VARCHAR(10)   NOT NULL,
    EffectiveFrom   DATE          NOT NULL,
    EffectiveTo     DATE          NULL,          -- NULL = still current
    ContractRef     VARCHAR(50)   NULL,
    CONSTRAINT CK_ContractPrice_Dates
        CHECK (EffectiveTo IS NULL OR EffectiveTo >= EffectiveFrom)
);
GO

CREATE INDEX IX_ContractPrice_Lookup
    ON purchasing.ContractPrice (VendorID, ItemID, EffectiveFrom);
GO

/*---------------------------------------------------------------------
  7. Invoice
     Vendor invoices that have been entered for payment, with their
     current payment status.
---------------------------------------------------------------------*/
CREATE TABLE purchasing.Invoice (
    InvoiceID       INT           NOT NULL PRIMARY KEY,
    InvoiceNumber   VARCHAR(30)   NOT NULL,
    VendorID        INT           NOT NULL
        CONSTRAINT FK_Invoice_Vendor REFERENCES purchasing.Vendor(VendorID),
    POID            INT           NULL
        CONSTRAINT FK_Invoice_PO REFERENCES purchasing.PurchaseOrderHeader(POID),
    InvoiceDate     DATE          NOT NULL,
    InvoiceAmount   DECIMAL(12,2) NOT NULL,
    PaymentStatus   VARCHAR(20)   NOT NULL
        CONSTRAINT DF_Invoice_Status DEFAULT ('Open'),
    PaidDate        DATE          NULL,
    CheckNumber     VARCHAR(20)   NULL,
    CONSTRAINT CK_Invoice_Status
        CHECK (PaymentStatus IN ('Open','Paid','Void'))
);
GO

CREATE INDEX IX_Invoice_Vendor
    ON purchasing.Invoice (VendorID, InvoiceNumber);
GO

/*=====================================================================
  8. Reconciliation view

  One row per PO line, joined to its receipt, the contract price in
  force on the order date, and the vendor.

  Units of measure are exposed rather than normalised: UOMConv and
  both the ordered and received UOMs are returned so the caller can
  apply the conversion explicitly.
=====================================================================*/
CREATE VIEW purchasing.vw_POReconciliation
AS
SELECT
    poh.POID,
    poh.PONumber,
    poh.OrderDate,
    poh.POStatus,
    poh.BuyerName,
    v.VendorID,
    v.VendorCode,
    v.VendorName,
    v.ContactName,
    v.ContactEmail,
    v.PaymentTerms,
    pol.POLineID,
    pol.LineNumber,
    i.ItemCode,
    i.ItemDescription,
    i.BaseUOM,
    i.PurchaseUOM,
    i.UOMConv,
    pol.QtyOrdered,
    pol.OrderUOM,
    pol.UnitPrice        AS POUnitPrice,
    pol.ExtendedAmount   AS POExtendedAmount,
    r.ReceiptNumber,
    r.ReceiptDate,
    r.QtyReceived,
    r.ReceiptUOM,
    r.ReceivedBy,
    cp.ContractPrice     AS ContractUnitPrice,
    cp.PriceUOM          AS ContractPriceUOM,
    cp.EffectiveFrom     AS ContractEffectiveFrom,
    cp.EffectiveTo       AS ContractEffectiveTo,
    cp.ContractRef
FROM purchasing.PurchaseOrderLine   AS pol
JOIN purchasing.PurchaseOrderHeader AS poh ON poh.POID   = pol.POID
JOIN purchasing.Vendor              AS v   ON v.VendorID = poh.VendorID
JOIN purchasing.Item                AS i   ON i.ItemID   = pol.ItemID
LEFT JOIN purchasing.ReceiptLine    AS r   ON r.POLineID = pol.POLineID
OUTER APPLY (
    SELECT TOP (1) c.ContractPrice, c.PriceUOM,
                   c.EffectiveFrom, c.EffectiveTo, c.ContractRef
    FROM purchasing.ContractPrice AS c
    WHERE c.VendorID = poh.VendorID
      AND c.ItemID   = pol.ItemID
      AND c.EffectiveFrom <= poh.OrderDate
      AND (c.EffectiveTo IS NULL OR c.EffectiveTo >= poh.OrderDate)
    ORDER BY c.EffectiveFrom DESC
) AS cp;
GO

/*=====================================================================
  9. Column descriptions

  Stored as extended properties. These carry the business meaning that
  column names alone do not - which units apply, which date governs
  pricing, what a status value implies.
=====================================================================*/

CREATE OR ALTER PROCEDURE purchasing.usp_SetColumnDescription
    @Table  SYSNAME,
    @Column SYSNAME,
    @Text   NVARCHAR(1000)
AS
BEGIN
    SET NOCOUNT ON;

    IF EXISTS (
        SELECT 1
        FROM sys.extended_properties AS ep
        JOIN sys.columns AS c
          ON c.object_id = ep.major_id AND c.column_id = ep.minor_id
        WHERE ep.class = 1
          AND ep.name  = N'MS_Description'
          AND ep.major_id = OBJECT_ID(N'purchasing.' + QUOTENAME(@Table))
          AND c.name   = @Column
    )
        EXEC sys.sp_dropextendedproperty
             @name = N'MS_Description',
             @level0type = N'SCHEMA', @level0name = N'purchasing',
             @level1type = N'TABLE',  @level1name = @Table,
             @level2type = N'COLUMN', @level2name = @Column;

    EXEC sys.sp_addextendedproperty
         @name = N'MS_Description', @value = @Text,
         @level0type = N'SCHEMA', @level0name = N'purchasing',
         @level1type = N'TABLE',  @level1name = @Table,
         @level2type = N'COLUMN', @level2name = @Column;
END;
GO

-- Item -----------------------------------------------------------------
EXEC purchasing.usp_SetColumnDescription 'Item', 'BaseUOM',
     N'Unit of measure the warehouse counts this item in. Always EA, meaning one individual unit.';

EXEC purchasing.usp_SetColumnDescription 'Item', 'PurchaseUOM',
     N'Unit of measure the item is bought and priced in. EA means the item is bought one at a time. CS means it is bought by the case. When this is CS, the quantity and unit price on a purchase order line are per case, and must be converted with UOMConv before they can be compared against an invoice that bills individual units.';

EXEC purchasing.usp_SetColumnDescription 'Item', 'UOMConv',
     N'How many individual units make up one purchase unit. A value of 12 means one case contains 12 individual units. To compare a purchase order line against an invoice billed per individual unit, multiply the ordered quantity by this value and divide the unit price by it. A value of 1 means the item is bought individually and no conversion is needed.';

-- Purchase order -------------------------------------------------------
EXEC purchasing.usp_SetColumnDescription 'PurchaseOrderHeader', 'OrderDate',
     N'Date the purchase order was placed. This is the date that determines which contract price applies - not the receipt date and not the invoice date.';

EXEC purchasing.usp_SetColumnDescription 'PurchaseOrderLine', 'QtyOrdered',
     N'Quantity ordered, stated in OrderUOM. If OrderUOM is CS this is a number of cases, not a number of individual units.';

EXEC purchasing.usp_SetColumnDescription 'PurchaseOrderLine', 'UnitPrice',
     N'Agreed price for one OrderUOM on this line. If OrderUOM is CS this is the price of a whole case. Compare it against the contract price for the same item and vendor in force on the order date, taking care that both are expressed in the same unit.';

-- Receipts -------------------------------------------------------------
EXEC purchasing.usp_SetColumnDescription 'ReceiptLine', 'QtyReceived',
     N'Quantity actually received at the dock, stated in ReceiptUOM. This may be less than the quantity ordered on the matching purchase order line if the vendor shipped short. A short shipment should be invoiced at the quantity received, not the quantity ordered.';

-- Contract pricing -----------------------------------------------------
EXEC purchasing.usp_SetColumnDescription 'ContractPrice', 'EffectiveFrom',
     N'First date this price is valid, inclusive. The price that applies to a purchase order is the one in force on the order date.';

EXEC purchasing.usp_SetColumnDescription 'ContractPrice', 'EffectiveTo',
     N'Last date this price is valid, inclusive. NULL means the price is still current.';

EXEC purchasing.usp_SetColumnDescription 'ContractPrice', 'ContractPrice',
     N'Agreed price per PriceUOM under the supply contract named in ContractRef.';

-- Invoices -------------------------------------------------------------
EXEC purchasing.usp_SetColumnDescription 'Invoice', 'POID',
     N'Internal ID of the purchase order this invoice was billed against. Matches POID in vw_POReconciliation - look up the PONumber there to find its POID, then filter invoices on it.';

EXEC purchasing.usp_SetColumnDescription 'Invoice', 'InvoiceNumber',
     N'Vendor-supplied invoice number. Not guaranteed unique across resubmissions - vendors occasionally resubmit the same charges under a new number or a new invoice date.';

EXEC purchasing.usp_SetColumnDescription 'Invoice', 'PaymentStatus',
     N'Open, Paid or Void. An invoice already marked Paid must not be paid again. Check for an existing Paid invoice covering the same purchase order and amount before approving a new one.';

EXEC purchasing.usp_SetColumnDescription 'Invoice', 'InvoiceAmount',
     N'Total amount billed on the invoice, including any freight or surcharges.';
GO

PRINT 'Schema [purchasing] created. Next: run 02_seed.sql';
GO

/*=====================================================================
  10. OPTIONAL - read-only login for the MCP server

  The MCP server should connect with an identity that cannot write,
  and that can see only this demo's schema.

  Uncomment, set your own password, and run once.
=====================================================================*/
/*
USE master;
GO
CREATE LOGIN bss_mcp_reader
    WITH PASSWORD = N'<set-your-own-password>',
         CHECK_POLICY = ON;
GO

USE BayStateSupply;
GO
CREATE USER bss_mcp_reader FOR LOGIN bss_mcp_reader;

-- Read access to this demo's schema, and nothing else.
GRANT SELECT ON SCHEMA::purchasing TO bss_mcp_reader;
DENY INSERT, UPDATE, DELETE, ALTER, EXECUTE ON SCHEMA::purchasing TO bss_mcp_reader;
GO
*/
