# Demo 2 — Customer Credit Decision

**MCP as an author.** A stored procedure that has existed for years becomes a
tool an AI application can call — and refuses when the policy says no.

The database decides. The model asks, explains and drafts. Nothing about the
rule lives in a prompt.

---

## The use case

Dana works in customer service at Bay State Supply. A customer is on the phone.
Their recent orders have gone badly and they are asking for a credit.

Bay State has a policy for this, and it is not complicated:

> Review the customer's last three completed orders. If two or more had a
> qualifying problem — a late delivery, a damaged item, an incorrect item — a
> credit may be issued, up to 15 percent of the value of the affected orders.

Dana can read that policy. Dana can see the orders. What Dana cannot do is
apply it: the authority to issue a credit sits with a supervisor. So the request
goes to an inbox, the supervisor is in a meeting, and the customer waits two
days for a decision that takes four seconds.

The problem is not that the data is hard to reach. It is that the decision sits
in a different person's calendar.

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
sql/01_schema.sql     tables, view, and the two stored procedures
sql/02_seed.sql       customers, orders, issues
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

## Still to come

- [ ] Client configuration
- [ ] Demo script — the prompts, in order

---

## Notes

Bay State Supply is fictional. Every customer, contact, order and issue in this
repository is invented sample data.

Part of **Introduction to MCP** — https://github.com/traceykroll/IntroductionToMCP

Licensed under the MIT License.
