/*=====================================================================
  Bay State Supply — demo database
  Introduction to MCP  |  Demo 2: Customer Credit Decision
  Author: Tracey Kroll
  Repo:    https://github.com/traceykroll/IntroductionToMCP
  License: MIT

  Bay State Supply is a fictional industrial distributor. All
  customers, orders, contacts and issues are invented sample data.

  This script owns the [service] schema only. It creates the database
  if it does not already exist, and never drops it, so it can be run
  alongside the other demo in this repository without either one
  disturbing the other.

  Idempotent: safe to rerun. Drops and recreates all objects.
  Run order:  01_schema.sql  ->  02_seed.sql
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

IF SCHEMA_ID('service') IS NULL
    EXEC ('CREATE SCHEMA service');
GO

/*---------------------------------------------------------------------
  1. Drop this demo's objects only (FK-safe order)
---------------------------------------------------------------------*/
DROP PROCEDURE IF EXISTS service.usp_IssueServiceCredit;
DROP PROCEDURE IF EXISTS service.usp_GetAccountStanding;
DROP PROCEDURE IF EXISTS service.usp_SetColumnDescription;
DROP VIEW      IF EXISTS service.vw_CustomerOrderHistory;
DROP TABLE     IF EXISTS service.ServiceCredit;
DROP TABLE     IF EXISTS service.OrderIssue;
DROP TABLE     IF EXISTS service.SalesOrder;
DROP TABLE     IF EXISTS service.Customer;
GO

/*---------------------------------------------------------------------
  2. Customer
     Account master. ContactEmail is where correspondence is sent.
---------------------------------------------------------------------*/
CREATE TABLE service.Customer (
    CustomerID      INT           NOT NULL PRIMARY KEY,
    AccountNumber   VARCHAR(20)   NOT NULL UNIQUE,
    CustomerName    VARCHAR(100)  NOT NULL,
    ContactName     VARCHAR(100)  NULL,
    ContactEmail    VARCHAR(150)  NULL,
    CustomerSince   DATE          NULL,
    IsActive        BIT           NOT NULL
        CONSTRAINT DF_Customer_IsActive DEFAULT (1)
);
GO

/*---------------------------------------------------------------------
  3. SalesOrder
     One row per order. PromisedDate and DeliveredDate together
     determine whether an order arrived late.
---------------------------------------------------------------------*/
CREATE TABLE service.SalesOrder (
    SalesOrderID    INT           NOT NULL PRIMARY KEY,
    OrderNumber     VARCHAR(20)   NOT NULL UNIQUE,
    CustomerID      INT           NOT NULL
        CONSTRAINT FK_SalesOrder_Customer REFERENCES service.Customer(CustomerID),
    OrderDate       DATE          NOT NULL,
    PromisedDate    DATE          NOT NULL,
    DeliveredDate   DATE          NULL,
    OrderTotal      DECIMAL(12,2) NOT NULL,
    OrderStatus     VARCHAR(20)   NOT NULL
        CONSTRAINT DF_SalesOrder_Status DEFAULT ('Open'),
    CONSTRAINT CK_SalesOrder_Status
        CHECK (OrderStatus IN ('Open','Shipped','Completed','Cancelled'))
);
GO

CREATE INDEX IX_SalesOrder_Customer
    ON service.SalesOrder (CustomerID, OrderDate DESC);
GO

/*---------------------------------------------------------------------
  4. OrderIssue
     Problems reported against an order.

     IsQualifying is the distinction the credit policy turns on. Not
     every complaint qualifies: an issue caused by the customer, or
     reported after the reporting window has closed, is recorded but
     does not count toward a credit.
---------------------------------------------------------------------*/
CREATE TABLE service.OrderIssue (
    OrderIssueID    INT           NOT NULL PRIMARY KEY,
    SalesOrderID    INT           NOT NULL
        CONSTRAINT FK_OrderIssue_Order REFERENCES service.SalesOrder(SalesOrderID),
    IssueType       VARCHAR(40)   NOT NULL,
    IssueDate       DATE          NOT NULL,
    ReportedBy      VARCHAR(100)  NULL,
    IsQualifying    BIT           NOT NULL
        CONSTRAINT DF_OrderIssue_Qualifying DEFAULT (1),
    Resolution      VARCHAR(200)  NULL,
    IssueNotes      VARCHAR(400)  NULL,
    CONSTRAINT CK_OrderIssue_Type
        CHECK (IssueType IN ('Late delivery','Damaged item','Incorrect item',
                             'Short shipment','Billing error','Customer error',
                             'Reported late'))
);
GO

CREATE INDEX IX_OrderIssue_Order
    ON service.OrderIssue (SalesOrderID);
GO

/*---------------------------------------------------------------------
  5. ServiceCredit
     Every credit issued, and every attempt that was refused.
     Empty until the demo runs.
---------------------------------------------------------------------*/
CREATE TABLE service.ServiceCredit (
    ServiceCreditID INT           NOT NULL IDENTITY(1,1) PRIMARY KEY,
    CustomerID      INT           NOT NULL
        CONSTRAINT FK_ServiceCredit_Customer REFERENCES service.Customer(CustomerID),
    CreditAmount    DECIMAL(12,2) NOT NULL,
    ReasonCode      VARCHAR(40)   NOT NULL,
    Justification   VARCHAR(400)  NULL,
    IssuedByRole    VARCHAR(40)   NOT NULL,
    IssuedAt        DATETIME2(0)  NOT NULL
        CONSTRAINT DF_ServiceCredit_IssuedAt DEFAULT (SYSDATETIME()),
    OverrideReason  VARCHAR(400)  NULL
);
GO

CREATE INDEX IX_ServiceCredit_Customer
    ON service.ServiceCredit (CustomerID, IssuedAt DESC);
GO

/*=====================================================================
  6. Order history view

  The last completed orders for a customer, with the number of
  qualifying issues on each. This is what an agent reads before
  proposing a credit.
=====================================================================*/
CREATE VIEW service.vw_CustomerOrderHistory
AS
SELECT
    so.SalesOrderID,
    so.OrderNumber,
    c.CustomerID,
    c.AccountNumber,
    c.CustomerName,
    c.ContactName,
    c.ContactEmail,
    so.OrderDate,
    so.PromisedDate,
    so.DeliveredDate,
    so.OrderTotal,
    so.OrderStatus,
    DATEDIFF(DAY, so.PromisedDate, so.DeliveredDate) AS DaysLate,
    iss.QualifyingIssueCount,
    iss.TotalIssueCount,
    iss.IssueSummary
FROM service.SalesOrder AS so
JOIN service.Customer   AS c ON c.CustomerID = so.CustomerID
OUTER APPLY (
    SELECT
        COUNT(CASE WHEN oi.IsQualifying = 1 THEN 1 END) AS QualifyingIssueCount,
        COUNT(*)                                        AS TotalIssueCount,
        STRING_AGG(
            CONCAT(oi.IssueType,
                   CASE WHEN oi.IsQualifying = 0 THEN ' (does not qualify)' ELSE '' END),
            '; ') AS IssueSummary
    FROM service.OrderIssue AS oi
    WHERE oi.SalesOrderID = so.SalesOrderID
) AS iss;
GO

/*=====================================================================
  7. usp_GetAccountStanding

  Applies the credit policy to a customer's recent order history and
  reports whether they are eligible. Read-only: it decides nothing and
  changes nothing.

  Policy: of the last three completed orders, two or more must carry
  at least one qualifying issue.
=====================================================================*/
CREATE PROCEDURE service.usp_GetAccountStanding
    @AccountNumber VARCHAR(20)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @CustomerID INT;

    SELECT @CustomerID = CustomerID
    FROM   service.Customer
    WHERE  AccountNumber = @AccountNumber;

    IF @CustomerID IS NULL
    BEGIN
        RAISERROR('No customer found with account number %s.', 16, 1, @AccountNumber);
        RETURN;
    END

    ;WITH LastThree AS (
        SELECT TOP (3)
               SalesOrderID, OrderNumber, OrderDate, PromisedDate,
               DeliveredDate, OrderTotal, DaysLate,
               QualifyingIssueCount, TotalIssueCount, IssueSummary
        FROM   service.vw_CustomerOrderHistory
        WHERE  CustomerID  = @CustomerID
          AND  OrderStatus = 'Completed'
        ORDER BY OrderDate DESC
    )
    SELECT
        c.AccountNumber,
        c.CustomerName,
        c.ContactName,
        c.ContactEmail,
        OrdersReviewed          = (SELECT COUNT(*) FROM LastThree),
        OrdersWithIssues        = (SELECT COUNT(*) FROM LastThree
                                   WHERE QualifyingIssueCount > 0),
        ValueOfAffectedOrders   = (SELECT ISNULL(SUM(OrderTotal), 0) FROM LastThree
                                   WHERE QualifyingIssueCount > 0),
        MaximumCredit           = CAST(
                                   (SELECT ISNULL(SUM(OrderTotal), 0) FROM LastThree
                                    WHERE QualifyingIssueCount > 0) * 0.15
                                   AS DECIMAL(12,2)),
        IsEligibleForCredit     = CASE WHEN (SELECT COUNT(*) FROM LastThree
                                             WHERE QualifyingIssueCount > 0) >= 2
                                       THEN CAST(1 AS BIT) ELSE CAST(0 AS BIT) END,
        PolicyStatement         = 'A credit may be issued when two or more of the '
                                + 'last three completed orders carried a qualifying '
                                + 'issue. The credit may not exceed 15 percent of '
                                + 'the value of the affected orders.'
    FROM service.Customer AS c
    WHERE c.CustomerID = @CustomerID;

    ;WITH LastThree AS (
        SELECT TOP (3)
               OrderNumber, OrderDate, PromisedDate, DeliveredDate,
               OrderTotal, DaysLate, QualifyingIssueCount,
               TotalIssueCount, IssueSummary
        FROM   service.vw_CustomerOrderHistory
        WHERE  CustomerID  = @CustomerID
          AND  OrderStatus = 'Completed'
        ORDER BY OrderDate DESC
    )
    SELECT OrderNumber, OrderDate, PromisedDate, DeliveredDate,
           OrderTotal, DaysLate, QualifyingIssueCount,
           TotalIssueCount, IssueSummary
    FROM   LastThree
    ORDER BY OrderDate DESC;
END;
GO

/*=====================================================================
  8. usp_IssueServiceCredit

  Issues a credit, or refuses. The policy is enforced here, not by the
  caller.

  Two independent checks:
    - eligibility: two or more of the last three completed orders must
      carry a qualifying issue
    - amount: the credit may not exceed 15 percent of the value of the
      affected orders

  A supervisor may override the eligibility check by supplying an
  override reason, which is recorded. The amount cap applies to every
  role, including supervisors.

  The role is not a parameter. It is derived from the login on the
  connection, so a caller cannot assert a role it does not hold.
=====================================================================*/
CREATE PROCEDURE service.usp_IssueServiceCredit
    @AccountNumber   VARCHAR(20),
    @CreditAmount    DECIMAL(12,2),
    @Justification   VARCHAR(400),
    @OverrideReason  VARCHAR(400)  = NULL
AS
BEGIN
    SET NOCOUNT ON;

    /*  The caller does not state its role. The role is taken from the
        login that opened the connection, so a caller cannot claim an
        authority it does not hold.  */
    DECLARE @Role VARCHAR(40) =
        CASE SUSER_SNAME()
             WHEN 'bss_support_supervisor' THEN 'support_supervisor'
             ELSE 'support_rep'
        END;

    DECLARE @CustomerID       INT,
            @OrdersWithIssues INT,
            @AffectedValue    DECIMAL(12,2),
            @MaximumCredit    DECIMAL(12,2),
            @MaxText          VARCHAR(20),
            @NewCreditID      INT;

    SELECT @CustomerID = CustomerID
    FROM   service.Customer
    WHERE  AccountNumber = @AccountNumber;

    IF @CustomerID IS NULL
    BEGIN
        RAISERROR('No customer found with account number %s.', 16, 1, @AccountNumber);
        RETURN;
    END

    IF @CreditAmount <= 0
    BEGIN
        RAISERROR('Credit amount must be greater than zero.', 16, 1);
        RETURN;
    END

    ;WITH LastThree AS (
        SELECT TOP (3) OrderTotal, QualifyingIssueCount
        FROM   service.vw_CustomerOrderHistory
        WHERE  CustomerID  = @CustomerID
          AND  OrderStatus = 'Completed'
        ORDER BY OrderDate DESC
    )
    SELECT @OrdersWithIssues = COUNT(CASE WHEN QualifyingIssueCount > 0 THEN 1 END),
           @AffectedValue    = ISNULL(SUM(CASE WHEN QualifyingIssueCount > 0
                                               THEN OrderTotal END), 0)
    FROM LastThree;

    SET @MaximumCredit = CAST(@AffectedValue * 0.15 AS DECIMAL(12,2));
    SET @MaxText       = CONVERT(VARCHAR(20), @MaximumCredit);

    /* --- Check 1: eligibility ------------------------------------ */
    IF @OrdersWithIssues < 2
    BEGIN
        IF @Role <> 'support_supervisor'
        BEGIN
            RAISERROR(
                'Credit declined. Policy requires a qualifying issue on at least two of the last three completed orders; this account has %d. A supervisor may override this with a recorded reason.',
                16, 1, @OrdersWithIssues);
            RETURN;
        END

        IF @OverrideReason IS NULL OR LTRIM(RTRIM(@OverrideReason)) = ''
        BEGIN
            RAISERROR(
                'Credit declined. A supervisor override requires a reason to be recorded.',
                16, 1);
            RETURN;
        END
    END

    /* --- Check 2: amount cap, applies to every role --------------- */
    IF @CreditAmount > @MaximumCredit
    BEGIN
        RAISERROR(
            'Credit declined. The requested amount exceeds the maximum of %s, being 15 percent of the value of the affected orders. This limit applies to all roles.',
            16, 1, @MaxText);
        RETURN;
    END

    INSERT INTO service.ServiceCredit
        (CustomerID, CreditAmount, ReasonCode, Justification,
         IssuedByRole, OverrideReason)
    VALUES
        (@CustomerID, @CreditAmount,
         CASE WHEN @OrdersWithIssues >= 2 THEN 'SERVICE_FAILURE'
              ELSE 'SUPERVISOR_OVERRIDE' END,
         @Justification, @Role, @OverrideReason);

    SET @NewCreditID = SCOPE_IDENTITY();

    SELECT ServiceCreditID, CustomerID, CreditAmount, ReasonCode,
           Justification, IssuedByRole, IssuedAt, OverrideReason,
           Outcome = 'Credit issued and recorded.'
    FROM   service.ServiceCredit
    WHERE  ServiceCreditID = @NewCreditID;
END;
GO

/*=====================================================================
  9. Column descriptions
=====================================================================*/

CREATE PROCEDURE service.usp_SetColumnDescription
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
          AND ep.major_id = OBJECT_ID(N'service.' + QUOTENAME(@Table))
          AND c.name   = @Column
    )
        EXEC sys.sp_dropextendedproperty
             @name = N'MS_Description',
             @level0type = N'SCHEMA', @level0name = N'service',
             @level1type = N'TABLE',  @level1name = @Table,
             @level2type = N'COLUMN', @level2name = @Column;

    EXEC sys.sp_addextendedproperty
         @name = N'MS_Description', @value = @Text,
         @level0type = N'SCHEMA', @level0name = N'service',
         @level1type = N'TABLE',  @level1name = @Table,
         @level2type = N'COLUMN', @level2name = @Column;
END;
GO

EXEC service.usp_SetColumnDescription 'OrderIssue', 'IsQualifying',
     N'Whether this issue counts toward a service credit. An issue caused by the customer, or reported after the reporting window closed, is recorded for history but does not qualify. Only qualifying issues are counted by the credit policy.';

EXEC service.usp_SetColumnDescription 'OrderIssue', 'IssueType',
     N'What went wrong. Late delivery, damaged item, incorrect item and short shipment are service failures. Customer error and reported late describe issues that were logged but do not qualify for a credit.';

EXEC service.usp_SetColumnDescription 'SalesOrder', 'PromisedDate',
     N'Date the order was promised to the customer. An order delivered after this date is late.';

EXEC service.usp_SetColumnDescription 'SalesOrder', 'DeliveredDate',
     N'Date the order was actually delivered. NULL means it has not been delivered yet.';

EXEC service.usp_SetColumnDescription 'SalesOrder', 'OrderStatus',
     N'Open, Shipped, Completed or Cancelled. The credit policy considers only Completed orders.';

EXEC service.usp_SetColumnDescription 'ServiceCredit', 'IssuedByRole',
     N'The role that issued the credit. Recorded on every credit so it is always possible to say who authorised it.';

EXEC service.usp_SetColumnDescription 'ServiceCredit', 'OverrideReason',
     N'Populated only when a supervisor issued a credit to an account that did not meet the eligibility policy. NULL on an ordinary credit.';
GO

PRINT 'Schema [service] created. Next: run 02_seed.sql';
GO

/*=====================================================================
  10. OPTIONAL - logins for the MCP server

  Two roles, so the same server can be connected as either. Neither
  can read or write outside this schema.
=====================================================================*/
/*
USE master;
GO
CREATE LOGIN bss_support_rep
    WITH PASSWORD = N'<set-your-own-password>', CHECK_POLICY = ON;
CREATE LOGIN bss_support_supervisor
    WITH PASSWORD = N'<set-your-own-password>', CHECK_POLICY = ON;
GO

USE BayStateSupply;
GO
CREATE USER bss_support_rep        FOR LOGIN bss_support_rep;
CREATE USER bss_support_supervisor FOR LOGIN bss_support_supervisor;

GRANT SELECT  ON SCHEMA::service TO bss_support_rep, bss_support_supervisor;
GRANT EXECUTE ON service.usp_GetAccountStanding
      TO bss_support_rep, bss_support_supervisor;
GRANT EXECUTE ON service.usp_IssueServiceCredit
      TO bss_support_rep, bss_support_supervisor;

-- Required by Data API builder, which reads a procedure's parameter list
-- before it can expose it. EXECUTE alone does not permit this.
GRANT VIEW DEFINITION ON SCHEMA::service
      TO bss_support_rep, bss_support_supervisor;

DENY INSERT, UPDATE, DELETE ON SCHEMA::service
      TO bss_support_rep, bss_support_supervisor;
GO
*/