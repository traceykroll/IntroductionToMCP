/*=====================================================================
  Bay State Supply — demo data
  Introduction to MCP  |  Demo 2: Customer Credit Decision
  Author: Tracey Kroll
  Repo:    https://github.com/traceykroll/IntroductionToMCP
  License: MIT

  All data is invented. Customers, contacts, orders and issues are
  fictional and any resemblance to real companies is coincidental.

  Idempotent: deletes and reloads the [service] tables.
  Run after 01_schema.sql.

  ServiceCredit is left empty. It fills up only when the demo runs.
=====================================================================*/

USE BayStateSupply;
GO

SET NOCOUNT ON;

DELETE FROM service.ServiceCredit;
DELETE FROM service.OrderIssue;
DELETE FROM service.SalesOrder;
DELETE FROM service.Customer;
GO

/*---------------------------------------------------------------------
  Customers
---------------------------------------------------------------------*/
INSERT INTO service.Customer
    (CustomerID, AccountNumber, CustomerName, ContactName, ContactEmail, CustomerSince, IsActive)
VALUES
    (1, 'C-10041', 'Granite Ridge Mechanical',      'Alicia Moreau',  'amoreau@graniteridgemech.example.com',  '2019-03-11', 1),
    (2, 'C-10077', 'Pemberton Facilities Group',    'Doug Farrow',    'dfarrow@pembertonfacilities.example.com','2021-08-02', 1),
    (3, 'C-10102', 'Whitcombe Industrial Services', 'Renata Vieira',  'rvieira@whitcombeind.example.com',       '2017-06-19', 1),
    (4, 'C-10118', 'Ellery Building Supply',        'Marcus Doyle',   'mdoyle@ellerybuilding.example.com',      '2020-01-27', 1),
    (5, 'C-10133', 'Norfolk County Facilities',     'Priya Raghavan', 'praghavan@norfolkcf.example.com',        '2018-11-05', 1),
    (6, 'C-10149', 'Bergeron Mechanical',           'Yvette Bergeron','ybergeron@bergeronmech.example.com',     '2022-04-14', 1),
    (7, 'C-10164', 'Ashland Fabrication',           'Tom Kessler',    'tkessler@ashlandfab.example.com',        '2016-09-30', 1);
GO

/*---------------------------------------------------------------------
  Sales orders

  Orders 1-3 belong to Granite Ridge, 4-6 to Pemberton. The rest are
  the ordinary run of business.
---------------------------------------------------------------------*/
INSERT INTO service.SalesOrder
    (SalesOrderID, OrderNumber, CustomerID, OrderDate, PromisedDate, DeliveredDate, OrderTotal, OrderStatus)
VALUES
    -- Granite Ridge Mechanical
    ( 1, 'SO-77120', 1, '2026-04-14', '2026-04-24', '2026-04-23', 2180.00, 'Completed'),
    ( 2, 'SO-77455', 1, '2026-06-02', '2026-06-12', '2026-06-12',  660.00, 'Completed'),
    ( 3, 'SO-77890', 1, '2026-07-09', '2026-07-20', '2026-07-28', 1240.00, 'Completed'),

    -- Pemberton Facilities Group
    ( 4, 'SO-77008', 2, '2026-03-17', '2026-03-27', '2026-03-26', 1410.00, 'Completed'),
    ( 5, 'SO-77512', 2, '2026-05-19', '2026-05-29', '2026-05-29',  840.00, 'Completed'),
    ( 6, 'SO-77934', 2, '2026-07-21', '2026-07-31', '2026-08-05', 2050.00, 'Completed'),

    -- Whitcombe Industrial Services
    ( 7, 'SO-77201', 3, '2026-04-28', '2026-05-08', '2026-05-07', 3420.00, 'Completed'),
    ( 8, 'SO-77604', 3, '2026-06-16', '2026-06-26', '2026-06-25', 1890.00, 'Completed'),
    ( 9, 'SO-78010', 3, '2026-08-04', '2026-08-14', '2026-08-13',  975.00, 'Completed'),

    -- Ellery Building Supply
    (10, 'SO-77166', 4, '2026-04-21', '2026-05-01', '2026-05-04', 1120.00, 'Completed'),
    (11, 'SO-77588', 4, '2026-06-09', '2026-06-19', '2026-06-19', 2640.00, 'Completed'),
    (12, 'SO-77976', 4, '2026-07-27', '2026-08-06', '2026-08-06',  530.00, 'Completed'),

    -- Norfolk County Facilities
    (13, 'SO-77243', 5, '2026-05-05', '2026-05-15', '2026-05-14', 4310.00, 'Completed'),
    (14, 'SO-77702', 5, '2026-06-30', '2026-07-10', '2026-07-09', 1755.00, 'Completed'),
    (15, 'SO-78044', 5, '2026-08-11', '2026-08-21', NULL,         2280.00, 'Shipped'),

    -- Bergeron Mechanical
    (16, 'SO-77338', 6, '2026-05-12', '2026-05-22', '2026-05-21',  690.00, 'Completed'),
    (17, 'SO-77815', 6, '2026-07-14', '2026-07-24', '2026-07-24', 1465.00, 'Completed'),

    -- Ashland Fabrication
    (18, 'SO-77074', 7, '2026-03-31', '2026-04-10', '2026-04-09', 5120.00, 'Completed'),
    (19, 'SO-77649', 7, '2026-06-23', '2026-07-03', '2026-07-02', 2940.00, 'Completed'),
    (20, 'SO-78098', 7, '2026-08-18', '2026-08-28', NULL,         1610.00, 'Open');
GO

/*---------------------------------------------------------------------
  Order issues

  Not every issue counts. IsQualifying = 0 means the problem was
  recorded for history but does not entitle the customer to a credit.
---------------------------------------------------------------------*/
INSERT INTO service.OrderIssue
    (OrderIssueID, SalesOrderID, IssueType, IssueDate, ReportedBy, IsQualifying, Resolution, IssueNotes)
VALUES
    -- Granite Ridge Mechanical
    (1, 2, 'Damaged item',  '2026-06-15', 'Alicia Moreau', 1,
     'Replacement shipped 17 June at no charge.',
     'Two of six enclosures arrived with crushed corners. Photographs supplied. Carrier damage confirmed.'),

    (2, 3, 'Late delivery', '2026-07-28', 'Alicia Moreau', 1,
     'Delivered 8 days after the promised date.',
     'Order held at the distribution centre awaiting a backordered line. Customer was not notified of the delay.'),

    -- Pemberton Facilities Group
    (3, 4, 'Reported late', '2026-05-12', 'Doug Farrow',   0,
     'Claim closed. Reported outside the 30 day window.',
     'Customer reported a damaged carton on 12 May for an order delivered 26 March, 47 days earlier. The reporting window is 30 days from delivery.'),

    (4, 5, 'Damaged item',  '2026-06-01', 'Doug Farrow',   1,
     'Credit note issued for the damaged unit.',
     'One pallet arrived with water damage. Carrier accepted responsibility.'),

    (5, 6, 'Customer error','2026-08-05', 'Doug Farrow',   0,
     'Redelivered at no charge to the customer.',
     'Delivery attempted 30 July to the address on the order. That address was a closed site; the correct address was supplied by the customer on 3 August. The five day delay follows from the address given at the time of order.'),

    -- Ellery Building Supply
    (6, 10, 'Late delivery','2026-05-04', 'Marcus Doyle',  1,
     'Delivered 3 days after the promised date.',
     'Carrier delay during a regional weather event.');
GO

PRINT 'Seed data loaded.';
GO

/*=====================================================================
  Verification
=====================================================================*/

-- 7 customers, 20 orders, 6 issues, 0 credits.
SELECT 'Customer' AS TableName, COUNT(*) AS Rows FROM service.Customer
UNION ALL SELECT 'SalesOrder',    COUNT(*) FROM service.SalesOrder
UNION ALL SELECT 'OrderIssue',    COUNT(*) FROM service.OrderIssue
UNION ALL SELECT 'ServiceCredit', COUNT(*) FROM service.ServiceCredit;
GO

-- Granite Ridge is eligible: 2 of the last 3 completed orders carry a
-- qualifying issue. Maximum credit 285.00.
EXEC service.usp_GetAccountStanding @AccountNumber = 'C-10041';
GO

-- Pemberton is not eligible: three issues on file, only one qualifies.
EXEC service.usp_GetAccountStanding @AccountNumber = 'C-10077';
GO

-- The two accounts side by side.
SELECT CustomerName, OrderNumber, OrderDate, OrderTotal,
       DaysLate, QualifyingIssueCount, TotalIssueCount, IssueSummary
FROM   service.vw_CustomerOrderHistory
WHERE  AccountNumber IN ('C-10041','C-10077')
  AND  OrderStatus = 'Completed'
ORDER BY CustomerName, OrderDate DESC;
GO