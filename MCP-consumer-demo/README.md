# Demo 1 — Vendor Invoice Reconciliation

**MCP as a consumer.** An AI application with two connections — one to a folder of
files, one to a SQL Server database — reconciles vendor invoices against purchase
orders, receipts and contract pricing.

No code is written in this demo. It runs on two off-the-shelf MCP servers, a JSON
configuration file, and a read-only database login.

---

## The use case

Bay State Supply is a fictional industrial distributor in Norwood, Massachusetts.
Sam in accounts payable reconciles vendor invoices every Monday morning.

Four invoices are sitting in a folder. They came from four different vendors in
four different formats. Everything needed to check them lives somewhere else:

| Where | What |
|---|---|
| The folder | Four invoices and the signed supply contract that sets the pricing rules |
| The database | Purchase orders, goods receipts, contract pricing, and every invoice already paid |

Neither source answers the question alone. The contract says price is set on the
date the order was placed — only the database knows what that date was. The
database holds every line that was ordered — only the contract says which extra
charges are not allowed.

---

## Prerequisites

| | |
|---|---|
| SQL Server 2016 or later | Developer Edition, Express, LocalDB, or Docker |
| .NET runtime | Data API builder 2.0 targets .NET 8 — see step 4 |
| Data API builder 1.7+ | 2.0 or later recommended |
| Node.js | For the filesystem MCP server |
| An MCP client | Claude Desktop, or VS Code with GitHub Copilot |

Azure Data Studio was retired in February 2026, and SQL Server Management Studio
does not run on macOS. The [SQL Server (mssql)](https://marketplace.visualstudio.com/items?itemName=ms-mssql.mssql)
extension for VS Code works on every platform and is used throughout these
instructions.

---

## Step 1 — Create the database

Run the two scripts in order against your SQL Server instance.

```
01_schema.sql     tables, view, and column descriptions
02_seed.sql       vendors, items, contract pricing, orders, receipts, payment history
```

Both are idempotent and can be rerun at any time to reset the data.

Everything lives in a **`purchasing`** schema inside a database called
**`BayStateSupply`**. The script creates the database if it does not exist, and
never drops it, so both demos in this repository can share one database.

| Object | Holds |
|---|---|
| `Vendor` | Supplier master, including the AP contact each dispute is addressed to |
| `Item` | Product master, including the case-to-unit conversion factor |
| `PurchaseOrderHeader` | Order-level facts. The order date determines which contract price applies |
| `PurchaseOrderLine` | Per-item quantities, units and agreed prices |
| `ReceiptLine` | What arrived at the dock |
| `ContractPrice` | Negotiated prices, effective-dated so price history is preserved |
| `Invoice` | Vendor invoices already entered for payment, with their status |
| `vw_POReconciliation` | One row per PO line, joined to its receipt, its vendor, and the contract price in force on the order date |

### Verify the data loaded

`02_seed.sql` ends with a verification block. The important query returns **zero
rows** when every purchase order line resolves to exactly one contract price and
the two agree:

```sql
SELECT PONumber, LineNumber, ItemCode, OrderDate,
       POUnitPrice, ContractUnitPrice, ContractEffectiveFrom
FROM   purchasing.vw_POReconciliation
WHERE  ContractUnitPrice IS NULL
   OR  POUnitPrice <> ContractUnitPrice;
```

---

## Step 2 — Create a read-only login

The MCP server connects with an identity that cannot write anything and can see
only this schema. `01_schema.sql` ends with a commented block that creates one.
Set your own password before running it.

```sql
CREATE LOGIN bss_mcp_reader WITH PASSWORD = N'<your-password>', CHECK_POLICY = ON;
GO
USE BayStateSupply;
GO
CREATE USER bss_mcp_reader FOR LOGIN bss_mcp_reader;
GRANT SELECT ON SCHEMA::purchasing TO bss_mcp_reader;
DENY INSERT, UPDATE, DELETE, ALTER, EXECUTE ON SCHEMA::purchasing TO bss_mcp_reader;
GO
```

Two independent limits then apply: the login cannot write, and the MCP server
exposes only the entities configured in step 4.

---

## Step 3 — Locate the invoice files

Everything the demo needs is in the `invoices/` folder of this repository. The
filesystem MCP server is pointed at that folder and nothing above it.

```
invoices/
├── HF-2026-1184_Hollis_Fasteners.pdf      formatted invoice
├── SP-88214_Sudbury_Packaging.csv         spreadsheet export
├── TM-5590_Tilton_Metals.csv              pipe-delimited ERP export
├── BC-77341_Braddock_Components.txt       an email
└── purchasing-terms-BSS-PT-2026.md        standard purchasing terms
```

An HTML version of the Hollis invoice is also included. Not every filesystem MCP
server can extract text from a PDF — if yours cannot, use
`HF-2026-1184_Hollis_Fasteners.html` instead and remove the PDF.

To keep the demo files somewhere else, copy `invoices/` to a location of your
choice and use that path in step 5 instead. Either way, the server should be
scoped to one folder containing only these files.

---

## Step 4 — Configure SQL MCP Server

[SQL MCP Server](https://learn.microsoft.com/en-us/sql/mcp/) is Microsoft's
open-source MCP server for SQL databases, built on Data API builder. It is
configured with a JSON file rather than code.

### Install the CLI

Data API builder is a .NET tool, so .NET must be installed first. Confirm it is
available:

```bash
dotnet --version
```

If the command is not found, install the .NET SDK and open a new terminal
session before continuing.

```bash
dotnet tool install -g Microsoft.DataApiBuilder
dab --version
```

A global install puts `dab` on the PATH, which MCP clients need in order to
launch it.

#### If `dab` is not found

The installer prints the tools directory it used. Add it to your shell profile:

```bash
echo 'export PATH="$PATH:$HOME/.dotnet/tools"' >> ~/.zprofile
zsh -l
```

#### If `dab` reports a missing framework

Data API builder 2.0 targets **.NET 8**, and .NET does not automatically run an
application on a newer major version. If you installed a newer SDK — .NET 9 or
10 — `dab` fails with a message naming `Microsoft.NETCore.App, version 8.0.0`.

Install the **.NET 8 runtime** alongside whatever version you already have. The
runtime alone is enough; the SDK is not required. Then `dab --version` works
without further configuration.

`DOTNET_ROLL_FORWARD=Major dab --version` confirms the diagnosis, but is not a
fix worth keeping. MCP clients launch `dab` as a child process and do not
inherit your shell environment, so the variable would have to be repeated in
every client configuration.

### Create the connection string

Run the remaining commands in this step from the `dab/` folder, which is where
`dab-config.json` is written. Create it if it does not exist:

```bash
mkdir -p dab
cd dab
```

Create a file named `.env` there:

```text
MSSQL_CONNECTION_STRING=Server=localhost,1433;Database=BayStateSupply;User Id=bss_mcp_reader;Password=<your-password>;TrustServerCertificate=True
```

If SQL Server is running in Docker on a different port, change `1433` to match.

> **This file contains a password.** It is listed in `.gitignore` and must not be
> committed. `dab-config.json` refers to it by name only, so the configuration
> file itself is safe to commit.

### Initialize and add the entities

```bash
dab init \
  --database-type mssql \
  --connection-string "@env('MSSQL_CONNECTION_STRING')" \
  --host-mode Development \
  --config dab-config.json

dab add POReconciliation \
  --source purchasing.vw_POReconciliation \
  --permissions "anonymous:read" \
  --description "One row per purchase order line, joined to the goods receipt, the vendor, and the contract price in force on the order date. Use this to check a vendor invoice line against what was ordered, what arrived, and what was agreed."

dab add Invoice \
  --source purchasing.Invoice \
  --permissions "anonymous:read" \
  --description "Vendor invoices already entered for payment. Check here before approving a new invoice to confirm the same charges have not already been paid."
```

Only these two entities are exposed. Nothing else in the database is reachable,
including the base tables behind the view.

### Set the key field on the view

Data API builder needs a key for every object it exposes. Tables supply their own
primary key, but a view does not have one, so it has to be named explicitly.
Without this, the server fails to start with
`Primary key not configured on the given database object vw_POReconciliation`.

`vw_POReconciliation` returns one row per purchase order line, so `POLineID`
identifies a row:

```bash
dab update POReconciliation --source.key-fields "POLineID"
```

`Invoice` is a table and needs no equivalent.

### Add field descriptions

Without field descriptions, an agent sees entity names and has to guess what the
columns mean. Two of the four discrepancies in this demo cannot be found without
them.

```bash
dab update POReconciliation --fields.name OrderDate \
  --fields.description "Date the purchase order was placed. This determines which contract price applies, not the receipt date and not the invoice date."

dab update POReconciliation --fields.name UOMConv \
  --fields.description "How many individual units make up one purchase unit. A value of 12 means one case contains 12 units. To compare a purchase order line against an invoice billed per individual unit, multiply the quantity by this value and divide the unit price by it."

dab update POReconciliation --fields.name PurchaseUOM \
  --fields.description "Unit the item is bought and priced in. EA means individually. CS means by the case, in which case the quantity and unit price on the line are per case."

dab update POReconciliation --fields.name POUnitPrice \
  --fields.description "Agreed price for one OrderUOM on this purchase order line."

dab update POReconciliation --fields.name ContractUnitPrice \
  --fields.description "Contract price for this item and vendor that was in force on the order date."

dab update POReconciliation --fields.name QtyReceived \
  --fields.description "Quantity received at the dock. May be less than the quantity ordered. A short shipment should be invoiced at the quantity received."

dab update Invoice --fields.name PaymentStatus \
  --fields.description "Open, Paid or Void. An invoice already marked Paid must not be paid again. Vendors occasionally resubmit the same charges under a new number or a new date."
```

Only the fields that carry non-obvious meaning are described here. The rest of
the view — `PONumber`, `VendorName`, `QtyOrdered` and so on — are clear enough
from their names.

The database columns also carry these descriptions as extended properties, which
are visible to anyone querying the database directly. Data API builder keeps its
own copies in `dab-config.json`; both are worth maintaining.

### Enable stdio transport

Add the following to the `runtime` section of `dab-config.json`. This lets an MCP
client launch the server as a child process rather than requiring a separate
terminal:

```json
"mcp": {
  "enabled": true
}
```

### Confirm the server starts

Before wiring up a client, check that the configuration is valid and the
connection works:

```bash
dab start --config dab-config.json
```

A successful start logs `Successfully completed runtime initialization`, the
resolved primary key for each entity, and:

```
Now listening on: http://localhost:5000
```

It binds to `localhost`, so the server is reachable only from this machine.
Stop it with `Ctrl+C` once it starts cleanly.

If it fails, the error appears here in plain text rather than inside a client
where it is harder to read. Two common ones:

| Message | Cause |
|---|---|
| `error: 40 - Could not open a connection` | Wrong host or port in `.env`, or SQL Server is not running. The port is separated by a comma, not a colon: `Server=localhost,1433` |
| `Primary key not configured` | The view needs `--source.key-fields`, as above |

A login or password problem reports `Login failed for user` instead, so an
`error: 40` is always host or port rather than credentials.

### A note on host mode

`--host-mode Development` and the `anonymous` role make the server usable
locally without configuring authentication. That is appropriate for a
demonstration on your own machine. A deployed server would use
`--host-mode Production` with real roles and an identity provider — see
[role-based access control](https://learn.microsoft.com/en-us/azure/data-api-builder/authorization).

---

## Step 5 — Connect a client

Either client below works — configure one, not both. The instructions assume
**Claude Desktop**, which is what the demo was built against. The VS Code
alternative is included for anyone who would rather stay in the editor.

Both launch Data API builder the same way, as a child process over stdio. Only
the file the configuration lives in differs.

### Claude Desktop

Edit `claude_desktop_config.json`. On macOS it is in
`~/Library/Application Support/Claude/`; on Windows, `%APPDATA%\Claude\`.
Settings → Developer opens it directly.

```json
{
  "mcpServers": {
    "baystate-sql": {
      "command": "dab",
      "args": [
        "start",
        "--mcp-stdio",
        "role:anonymous",
        "--loglevel", "error",
        "--config", "/absolute/path/to/dab-config.json"
      ]
    },
    "baystate-files": {
      "command": "npx",
      "args": [
        "-y",
        "@modelcontextprotocol/server-filesystem",
        "/absolute/path/to/MCP-consumer-demo/invoices"
      ]
    }
  }
}
```

Use absolute paths for both. Restart Claude Desktop, then confirm both servers
appear in the tools list.

If the SQL server fails to start, the usual cause is that `dab` is not on the
PATH the desktop application inherits. Use the full path instead — typically
`~/.dotnet/tools/dab` on macOS and Linux.

### VS Code — alternative

Open `MCP-consumer-demo` as a workspace — the folder that contains `dab/`,
not `dab/` itself. `${workspaceFolder}` then resolves to the demo root.

Create a `.vscode` folder at that root, and an `mcp.json` file inside it:

```
MCP-consumer-demo/
├── .vscode/
│   └── mcp.json
├── dab/
│   └── dab-config.json
└── invoices/
```

```json
{
  "servers": {
    "baystate-sql": {
      "type": "stdio",
      "command": "dab",
      "args": [
        "start",
        "--mcp-stdio",
        "role:anonymous",
        "--loglevel", "error",
        "--config", "${workspaceFolder}/dab/dab-config.json"
      ]
    },
    "baystate-files": {
      "type": "stdio",
      "command": "npx",
      "args": [
        "-y",
        "@modelcontextprotocol/server-filesystem",
        "${workspaceFolder}/invoices"
      ]
    }
  }
}
```

VS Code starts and stops both servers with the workspace. Open Copilot Chat in
Agent mode to use them.

### Running the server over HTTP instead

For a long-running server — useful when more than one client connects to it —
start it in a terminal:

```bash
dab start --config dab-config.json
```

The startup output shows the listening URLs. The MCP endpoint is typically
`http://localhost:5000/mcp`.

---

## Step 6 — Verify the tool surface

[MCP Inspector](https://github.com/modelcontextprotocol/inspector) shows exactly
what an agent sees: tool names, their parameters, and their descriptions.

```bash
npx -y @modelcontextprotocol/inspector http://localhost:5000/mcp
```

---

## Running the demo

Four prompts, in order. Each builds on the last.

**1. Read the invoices in this folder and tell me what is in them.**

Establishes the file side. The four documents arrive in four different formats,
with different column names, date formats and part numbering.

**2. Check these against our purchase orders and receipts. Flag anything that
does not reconcile.**

The main event. Resolving the discrepancies requires the contract document and
the database together.

**3. Draft a dispute email for the items you are confident about.**

The vendor contact comes from the database, the clause from the contract file,
and the quantities from the purchase order.

**4. Post the credit to the vendor account.**

This fails. The login is read-only and no tool exists to write anything — which
is the boundary the second demo in this repository picks up.

---

## Running SQL Server on a Mac

There is no ARM64 build of SQL Server, but Docker Desktop with Rosetta runs the
x86 image on Apple Silicon.

1. Install **Docker Desktop for Mac (Apple silicon)**.
2. Settings → Resources → set memory to at least 4 GB.
3. Settings → General → enable **Use Rosetta for x86/amd64 emulation**.
   If Rosetta is not present: `softwareupdate --install-rosetta`

```bash
docker run \
  --platform linux/amd64 \
  --name sqldemo \
  -e "ACCEPT_EULA=Y" \
  -e "MSSQL_SA_PASSWORD=<your-password>" \
  -e "MSSQL_PID=Developer" \
  -p 1433:1433 \
  -d \
  mcr.microsoft.com/mssql/server:2022-latest
```

Wait for `SQL Server is now ready for client connections`:

```bash
docker logs sqldemo
```

Connect from VS Code to `localhost,1433` with **Trust Server Certificate**
enabled — the container uses a self-signed certificate.

**Notes**

- Use SQL Server 2022 rather than the 2025 preview, which can crash on macOS
  over AVX instruction requirements.
- After a restart, use `docker start sqldemo`, not `docker run`.
- Volume mounting is unreliable on Docker for Mac ARM64. Rebuild from the two SQL
  scripts rather than relying on the container to preserve data.

---

## Repository layout

```
MCP-consumer-demo/
├── README.md
├── .vscode/
│   └── mcp.json      only if using VS Code
├── 01_schema.sql
├── 02_seed.sql
├── .env.example      copy to dab/.env and set your password
├── invoices/         the four invoices and the purchasing terms
├── logos/            vendor and Bay State Supply logos
└── dab/
    └── dab-config.json
```

---

## Notes

Bay State Supply is fictional. Every vendor, contact, item, price and invoice in
this repository is invented sample data.

Part of **Introduction to MCP** — https://github.com/traceykroll/IntroductionToMCP

Licensed under the MIT License.
