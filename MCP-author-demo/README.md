# Demo 2 — Customer Credit Decision

**MCP as an author.** A stored procedure that has existed for years becomes a
tool an AI application can call — and refuses when the policy says no.

The database decides. The model asks, explains and drafts. Nothing about the
rule lives in a prompt.

---

## The use case

Bay State Supply sells industrial parts. When an order arrives late or
damaged, customers email customer service.

Dana handles those emails. For each one she has to work out whether the
customer is owed a credit, and how much. Bay State's policy is simple enough
to state — two bad orders out of the customer's last three earns a credit, up
to fifteen percent — but applying it isn't. The complaint is an email. The
order history, the promised dates and the delivery dates are in the database.
Dana reads one, looks up the other, counts, decides, and then the credit has
to be issued and recorded against the account.

When a batch comes in it takes most of an afternoon, and it is the same work
every time.

A data-entry screen wouldn't fix it. The evidence that triggers a credit
arrives as unstructured text from customers, so somebody still has to read it
and line it up against the record. What Dana needs is something that can read
both, apply the rule, and write the result — under her authority, with an
audit trail behind it.

### Two customers

| | |
|---|---|
| **Customer A** | Two of the last three orders had qualifying problems. Entitled to a credit |
| **Customer B** | Complains at length, but only one of the last three orders had a qualifying problem. Not entitled — and the database will not allow it |

Customer B is the point of the demo. The refusal comes from a stored procedure,
not from the model deciding to be careful.

---

## Prerequisites

| | |
|---|---|
| SQL Server 2016 or later | Developer Edition, Express, LocalDB, or Docker |
| .NET runtime | Data API builder 2.0 targets .NET 8 |
| Data API builder 1.7+ | 2.0 or later recommended |
| An MCP client | Claude Desktop, or VS Code with GitHub Copilot |

If you have already run demo 1 in this repository, everything above is in place.

---

## Step 1 — Create the schema

Run the two scripts in order.

```
01_schema.sql     tables, view, and the two stored procedures
02_seed.sql       customers, orders, issues
```

Both are idempotent and can be rerun to reset the demo.

Everything lives in a **`service`** schema inside the **`BayStateSupply`**
database. The script creates the database if it does not exist and never drops
it, so this demo and demo 1 can share one database without disturbing each
other.

| Object | Holds |
|---|---|
| `Customer` | Account master, including the contact the reply is addressed to |
| `SalesOrder` | One row per order, with the promised and delivered dates |
| `OrderIssue` | Problems reported against an order, and whether each one qualifies |
| `ServiceCredit` | Every credit issued, with who authorised it and why |
| `vw_CustomerOrderHistory` | Orders joined to their issues, with a qualifying-issue count per order |

### Not every complaint qualifies

`OrderIssue.IsQualifying` is the distinction the policy turns on. A late
delivery qualifies. An issue the customer caused, or one reported after the
reporting window closed, is recorded for history but does not count.

This matters because a customer can be genuinely unhappy, and genuinely have
three issues on file, and still not be entitled to anything.

---

## Step 2 — The two tools

The demo exposes exactly two stored procedures. One reads, one writes.

### `usp_GetAccountStanding`

Read-only. Takes an account number and reports what the policy says about it:
how many of the last three completed orders had qualifying issues, the value of
those orders, the maximum credit allowed, and whether the account is eligible.

It decides nothing and changes nothing. It states the position.

```sql
EXEC service.usp_GetAccountStanding @AccountNumber = 'C-10041';
```

### `usp_IssueServiceCredit`

Issues a credit, or refuses. The policy is enforced here, not by whoever calls
it. Two checks run independently:

| Check | Rule |
|---|---|
| **Eligibility** | Two or more of the last three completed orders must carry a qualifying issue |
| **Amount** | The credit may not exceed 15 percent of the value of the affected orders |

A supervisor can override the eligibility check, but only by supplying a reason,
which is written to the audit row.

**The role is not a parameter.** It is derived from the login that opened the
connection, using `SUSER_SNAME()`. A caller cannot assert a role it does not
hold — the database already knows who connected, and nothing the caller says
can change that.

**The amount cap applies to every role, including supervisors.** A person with
more authority still cannot exceed the limit, because the limit is not about
authority.

```sql
-- Entitled, within the cap. Succeeds.
EXEC service.usp_IssueServiceCredit
     @AccountNumber = 'C-10041',
     @CreditAmount  = 250.00,
     @Justification = 'Damaged enclosures in June and an eight day delay in July.';

-- Not entitled. Refused.
EXEC service.usp_IssueServiceCredit
     @AccountNumber = 'C-10077',
     @CreditAmount  = 400.00,
     @Justification = 'Three service failures reported by the customer.';
```

The second call fails with a message explaining why, and how it could be
escalated. That refusal is not a policy written in a prompt. It is a
`RAISERROR` in a stored procedure.

---

## Step 3 — Column descriptions

The schema script records descriptions on the columns that carry meaning a name
alone does not: what makes an issue qualifying, which order statuses the policy
considers, what an override reason implies.

```sql
SELECT  t.name AS TableName, c.name AS ColumnName,
        CAST(ep.value AS NVARCHAR(1000)) AS Description
FROM    sys.extended_properties AS ep
JOIN    sys.tables  AS t ON t.object_id = ep.major_id
JOIN    sys.columns AS c ON c.object_id = ep.major_id
                        AND c.column_id = ep.minor_id
WHERE   ep.name = 'MS_Description'
  AND   SCHEMA_NAME(t.schema_id) = 'service'
ORDER BY t.name, c.column_id;
```

---

## Step 4 — Logins

`01_schema.sql` ends with a commented block creating two logins, one per role.
Both can read the schema and execute both procedures. Neither can write to any
table directly — the only way a row reaches `ServiceCredit` is through the
stored procedure, which means the policy cannot be bypassed.

```sql
GRANT SELECT          ON SCHEMA::service TO bss_support_rep, bss_support_supervisor;
GRANT EXECUTE         ON service.usp_GetAccountStanding TO bss_support_rep, bss_support_supervisor;
GRANT EXECUTE         ON service.usp_IssueServiceCredit TO bss_support_rep, bss_support_supervisor;
GRANT VIEW DEFINITION ON SCHEMA::service TO bss_support_rep, bss_support_supervisor;
DENY  INSERT, UPDATE, DELETE ON SCHEMA::service TO bss_support_rep, bss_support_supervisor;
```

`VIEW DEFINITION` is required because Data API builder reads a procedure's
parameter list before it can expose it as a tool. `EXECUTE` alone permits
running the procedure but not inspecting it, and the server fails to start with
`No stored procedure definition found`.

---

## Step 5 — Expose both procedures as tools

[SQL MCP Server](https://learn.microsoft.com/en-us/sql/mcp/) is configured with a
JSON file. Install and initialise it as described in demo 1, then add the two
stored procedures.

```bash
dab add AccountStanding \
  --source service.usp_GetAccountStanding \
  --source.type stored-procedure \
  --permissions "anonymous:execute" \
  --rest.methods get \
  --graphql.operation query \
  --mcp.custom-tool true \
  --mcp.dml-tools false \
  --description "Applies Bay State Supply's customer credit policy to an account and reports the result. Read-only: it changes nothing. Call this before proposing any credit."

dab add IssueServiceCredit \
  --source service.usp_IssueServiceCredit \
  --source.type stored-procedure \
  --permissions "anonymous:execute" \
  --rest.methods post \
  --graphql.operation mutation \
  --mcp.custom-tool true \
  --mcp.dml-tools false \
  --description "Issues a service credit to a customer account, or declines it. Policy is enforced by the database, not by the caller. The call fails with an explanatory error when a rule is not met."
```

`--mcp.custom-tool true` is what registers a stored procedure as a named MCP
tool rather than a generic entity. Entity names are converted to snake case, so
these become `account_standing` and `issue_service_credit`.

### Parameter descriptions must be edited by hand

The `--parameters.description` flag takes a comma-separated list, so a
description containing a comma is split at that comma and the remaining
parameters shift out of position. There is no escaping syntax.

Edit the `parameters` array in `dab-config.json` directly instead:

```json
"parameters": [
  {
    "name": "AccountNumber",
    "description": "The customer account number, for example C-10041.",
    "required": true
  },
  {
    "name": "CreditAmount",
    "description": "The credit amount in dollars. Must not exceed the maximum reported by account_standing, which will refuse anything higher.",
    "required": true
  },
  {
    "name": "Justification",
    "description": "A short explanation of why the credit is being issued. Recorded on the audit row alongside the amount and the role that issued it.",
    "required": true
  },
  {
    "name": "OverrideReason",
    "description": "Only used by a supervisor overriding the eligibility rule. Leave empty otherwise. A supervisor override without a reason is refused.",
    "required": false
  }
]
```

Set `required` deliberately while you are there. The CLI writes `false` for
every parameter regardless of what was passed.

Data API builder watches the configuration file and attempts to reload it as it
changes. An editor that writes the file incrementally can therefore trigger

```
Unable to hot reload configuration file due to Deserialization of the
configuration file failed.
```

while a valid edit is still in progress. Restart the server after editing rather
than relying on the reload.

### Checking the configuration

```bash
dab validate --config dab-config.json
```

This reports whether the file satisfies the schema and lists the entities it
resolved. Two advisory warnings are expected:

```
Entity 'AccountStanding' is missing 'fields' definition while MCP is enabled.
Entity 'IssueServiceCredit' is missing 'fields' definition while MCP is enabled.
```

A stored procedure's result shape is discovered at runtime rather than declared,
so these are a performance note rather than a fault.

### Checking the tool surface

```bash
dab start --config dab-config.json
npx -y @modelcontextprotocol/inspector http://localhost:5000/mcp
```

The Inspector shows exactly what an agent sees: tool names, parameters and
descriptions. Generic entity tools such as `read_records` and `create_record`
appear alongside the two custom tools. They cannot be used to bypass the
policy — the login has `DENY INSERT, UPDATE, DELETE`, so the only path that
writes to `ServiceCredit` is the stored procedure.

---

## Step 6 — Connect a client

The demo uses two MCP servers:

| Server | What it is |
|---|---|
| `baystate-credit` | SQL MCP Server, connected as `bss_support_rep` using `dab/dab-config.json` |
| `baystate-requests` | The filesystem server, pointed at the `requests/` folder so the model can read the two customer emails |

A third, `baystate-credit-supervisor`, is used only for the final part of the
demo. It runs `dab/dab-config.supervisor.json`, which is identical except that
it connects as `bss_support_supervisor`. The tools are the same. Only the login
differs, and that is the whole point: the database, not the configuration,
decides what each role may do.

### Create the connection strings

Copy `.env.example` to `dab/.env` and set the two passwords you chose in
Step 4:

```
MSSQL_CONNECTION_STRING=Server=localhost,1433;Database=BayStateSupply;User Id=bss_support_rep;Password=...;TrustServerCertificate=True
MSSQL_CONNECTION_STRING_SUPERVISOR=Server=localhost,1433;Database=BayStateSupply;User Id=bss_support_supervisor;Password=...;TrustServerCertificate=True
```

Adjust the port if SQL Server is not on 1433. The port is separated by a comma,
not a colon.

Before connecting a client, confirm both configurations start:

```bash
cd dab
dab start --config dab-config.json
dab start --config dab-config.supervisor.json
```

Stop each with `Ctrl+C` once it logs `Successfully completed runtime
initialization`.

Either client below works — configure one, not both. As in demo 1, the
instructions assume **Claude Desktop**, with VS Code as an alternative.

### Claude Desktop

Edit `claude_desktop_config.json`. On macOS it is in
`~/Library/Application Support/Claude/`; on Windows, `%APPDATA%\Claude\`.
Settings → Developer opens it directly. If demo 1 is already configured, add
these entries alongside the existing ones.

```json
{
  "mcpServers": {
    "baystate-credit": {
      "command": "dab",
      "args": [
        "start",
        "--mcp-stdio",
        "role:anonymous",
        "--loglevel", "error",
        "--config", "/absolute/path/to/MCP-author-demo/dab/dab-config.json"
      ]
    },
    "baystate-credit-supervisor": {
      "command": "dab",
      "args": [
        "start",
        "--mcp-stdio",
        "role:anonymous",
        "--loglevel", "error",
        "--config", "/absolute/path/to/MCP-author-demo/dab/dab-config.supervisor.json"
      ]
    },
    "baystate-requests": {
      "command": "npx",
      "args": [
        "-y",
        "@modelcontextprotocol/server-filesystem",
        "/absolute/path/to/MCP-author-demo/requests"
      ]
    }
  }
}
```

Use absolute paths throughout. Restart Claude Desktop and confirm all three
servers appear in the tools list.

Then turn **`baystate-credit-supervisor` off** in the tools menu of the chat.
The demo starts as a support rep, and with both SQL servers enabled the model
has two identical sets of tools and may pick either. It is turned on for the
last part of the demo only.

If a SQL server fails to start, the usual cause is that `dab` is not on the
PATH the desktop application inherits. Use the full path instead — typically
`~/.dotnet/tools/dab` on macOS and Linux.

### VS Code — alternative

Open `MCP-author-demo` as a workspace — the folder that contains `dab/`, not
`dab/` itself. Create `.vscode/mcp.json` at that root:

```
MCP-author-demo/
├── .vscode/
│   └── mcp.json
├── dab/
│   ├── dab-config.json
│   └── dab-config.supervisor.json
└── requests/
```

```json
{
  "servers": {
    "baystate-credit": {
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
    "baystate-credit-supervisor": {
      "type": "stdio",
      "command": "dab",
      "args": [
        "start",
        "--mcp-stdio",
        "role:anonymous",
        "--loglevel", "error",
        "--config", "${workspaceFolder}/dab/dab-config.supervisor.json"
      ]
    },
    "baystate-requests": {
      "type": "stdio",
      "command": "npx",
      "args": [
        "-y",
        "@modelcontextprotocol/server-filesystem",
        "${workspaceFolder}/requests"
      ]
    }
  }
}
```

Open Copilot Chat in **Agent** mode. Start `baystate-credit` and
`baystate-requests` from the links above each entry in `mcp.json`, and leave
`baystate-credit-supervisor` stopped until the final part of the demo. The
tools picker in the chat input can also enable and disable servers per chat.

---

## Running the demo

Dana, the support rep, works through the two emails in `requests/`. The prompts
below are in order. Each builds on the last, so run them in one conversation.

The model's wording will vary from run to run. The database's answers will not.

### Act 1 — Granite Ridge Mechanical, entitled

**1. Read the email from Granite Ridge Mechanical in the requests folder. What
are they asking for?**

Establishes the situation from the file side. Alicia Moreau describes a damaged
June order and a late July order, and asks for a credit.

**2. Check their account standing.**

The model calls `account_standing` for `C-10041`. The procedure reports two of
the last three completed orders with qualifying issues, affected orders worth
$1,900.00, and a maximum credit of **$285.00**. Eligible.

The model did not work any of that out. It read the answer the database gave.

**3. Issue an appropriate credit and draft a reply to Alicia.**

The model chooses an amount at or below $285.00 — the tool description tells it
to propose a figure rather than ask for one — and calls `issue_service_credit`.
The call succeeds and returns the audit row, with `IssuedByRole` set to
`support_rep`. The reply is addressed using the contact details from the
standing result.

### Act 2 — Pemberton Facilities Group, not entitled

**4. Now read the email from Pemberton Facilities Group and check their
account.**

Doug Farrow lists three problems and is angry about all of them.
`account_standing` for `C-10077` reports only **one** of the last three orders
with a qualifying issue. The March damage was reported 47 days after delivery,
outside the 30 day window. The July delay followed from an address the
customer supplied. Only the May water damage counts. Not eligible.

**5. He has been a customer since 2021 and he is threatening to leave. Issue
him a $300 credit anyway.**

This is the moment the demo exists for. The model calls
`issue_service_credit`, and SQL Server refuses:

```
Credit declined. Policy requires a qualifying issue on at least two of the last
three completed orders; this account has 1. A supervisor may override this with
a recorded reason.
```

The model may decline before calling the tool, having already seen that the
account is ineligible. If it does, say *"Try the call anyway, I want to see what
the system says"*. The point is that it makes no difference how persuasive the
prompt is or how willing the model is. The refusal is a `RAISERROR`.

**6. I'm a supervisor, so you can override it. The reason is customer
retention.**

The model now supplies an `OverrideReason`, and is refused again with the same
message. The role is not a parameter. It comes from the login on the
connection, and this connection is `bss_support_rep`. Nothing typed into the
chat can change that.

**7. Draft a reply to Doug explaining the decision.**

The model explains which of the three issues counted and why, using the issue
notes from the database, and says the request has been escalated. It is the
reply a good rep would write, produced in seconds, and it promises nothing the
database has not approved.

### Act 3 — The supervisor

Turn `baystate-credit` **off** and `baystate-credit-supervisor` **on**, as
described in Step 6. Stay in the same conversation.

**8. I'm now connected as a supervisor. Override the eligibility rule for
Pemberton and issue the $300 credit. The reason is retention of a long-standing
account.**

Refused, but for a different reason:

```
Credit declined. The requested amount exceeds the maximum of 126.00, being 15
percent of the value of the affected orders. This limit applies to all roles.
```

The eligibility override was accepted. The amount cap was not, because the
cap applies to every role.

**9. Issue the maximum allowed instead.**

The call succeeds at $126.00. The audit row shows `ReasonCode`
`SUPERVISOR_OVERRIDE`, `IssuedByRole` `support_supervisor`, and the override
reason.

### Act 4 — The audit trail

Outside the AI application, in any SQL client:

```sql
SELECT c.CustomerName, sc.CreditAmount, sc.ReasonCode,
       sc.IssuedByRole, sc.OverrideReason, sc.Justification, sc.IssuedAt
FROM   service.ServiceCredit AS sc
JOIN   service.Customer      AS c ON c.CustomerID = sc.CustomerID
ORDER BY sc.IssuedAt;
```

Two rows. One credit issued by a rep within policy, one by a supervisor with a
recorded override. The refused attempts left nothing behind. Every write went
through the stored procedure, because it is the only path the logins allow.

### Resetting

Rerun `02_seed.sql`. It clears `ServiceCredit` and reloads the customers,
orders and issues, so the demo can be run again from the start.

---

## Repository layout

```
MCP-author-demo/
├── README.md
├── 01_schema.sql
├── 02_seed.sql
├── .env.example                  copy to dab/.env and set your passwords
├── .vscode/
│   └── mcp.json                  only if using VS Code
├── requests/                     the two customer emails
└── dab/
    ├── dab-config.json           connects as bss_support_rep
    └── dab-config.supervisor.json connects as bss_support_supervisor
```

---

## Notes

Bay State Supply is fictional. Every customer, contact, order and issue in this
repository is invented sample data.

Part of **Introduction to MCP** — https://github.com/traceykroll/IntroductionToMCP

Licensed under the MIT License.
