# Introduction to MCP

Talk materials and two working demonstrations of the Model Context Protocol,
built for an audience of DBAs, SQL developers and business users.

Everything here runs against SQL Server. No Python, and no code beyond the SQL
you would write anyway.

---

## The two demos

Both use **Bay State Supply**, a fictional industrial distributor, and both run
against the same database using separate schemas. Either can be run on its own.

### [MCP as a consumer](./MCP-consumer-demo) — vendor invoice reconciliation

An AI application with two connections, one to a folder of files and one to a
read-only SQL Server login, checks four vendor invoices against purchase orders,
receipts and contract pricing.

The point: the contract rules live in a document, the facts live in the
database, and no integration code joins them.

### [MCP as an author](./MCP-author-demo) — customer credit decision

A stored procedure that has enforced company credit policy for years becomes a
tool an AI application can call. One customer qualifies for a credit. The next
does not, and the database refuses.

The point: the model asks and explains, the database decides. The refusal is a
`RAISERROR`, not a well-behaved model.

---

## What you need

| | |
|---|---|
| SQL Server 2016 or later | Developer Edition, Express, LocalDB, or Docker |
| .NET runtime | Data API builder 2.0 targets .NET 8 |
| Data API builder 1.7+ | 2.0 or later recommended |
| Node.js | For the filesystem MCP server |
| An MCP client | Claude Desktop, or VS Code with GitHub Copilot |

Each demo folder has its own README with the full setup, including the things
that went wrong the first time.

---

## Resources

### The protocol itself

| | |
|---|---|
| [Model Context Protocol](https://modelcontextprotocol.io/) | Official documentation. Start here |
| [Getting started](https://modelcontextprotocol.io/docs/getting-started/intro) | Concepts and quickstarts |
| [Specification](https://modelcontextprotocol.io/specification/2025-11-25) | The authoritative protocol requirements |
| [Specification repository](https://github.com/modelcontextprotocol/modelcontextprotocol) | Schema source and proposed changes |
| [Reference servers](https://github.com/modelcontextprotocol/servers) | Official implementations, including the filesystem server used in demo 1 |
| [MCP Inspector](https://github.com/modelcontextprotocol/inspector) | Shows exactly what an agent sees. Worth running before connecting any client |
| [The original announcement](https://www.anthropic.com/news/model-context-protocol) | Anthropic's launch post, for the design rationale |

### SQL Server

| | |
|---|---|
| [SQL MCP Server](https://learn.microsoft.com/en-us/sql/mcp/) | Microsoft's open-source MCP server for SQL databases. Used in both demos |
| [Data API builder — MCP](https://learn.microsoft.com/en-us/azure/data-api-builder/mcp/overview) | How entities become tools |
| [VS Code quickstart](https://learn.microsoft.com/en-us/azure/data-api-builder/mcp/quickstart-visual-studio-code) | The setup these demos are based on |
| [Role-based access control](https://learn.microsoft.com/en-us/azure/data-api-builder/authorization) | Permissions, roles, and what production looks like |
| [SQL Server (mssql) extension](https://marketplace.visualstudio.com/items?itemName=ms-mssql.mssql) | For VS Code. Azure Data Studio retired in February 2026 |

### Security

Worth reading before you expose anything you care about.

| | |
|---|---|
| [OWASP MCP Top 10 for Azure](https://microsoft.github.io/mcp-azure-security-guide/) | The ten most critical risks, with practical guidance |
| [MCP for Beginners: Security](https://github.com/microsoft/mcp-for-beginners/blob/main/02-Security/README.md) | Microsoft's security chapter, including prompt injection and tool poisoning |
| [Security best practices](https://github.com/microsoft/mcp-for-beginners/blob/main/02-Security/mcp-best-practices.md) | Token validation, session handling, input validation |
| [Understanding and mitigating MCP security risks](https://techcommunity.microsoft.com/blog/microsoft-security-blog/understanding-and-mitigating-security-risks-in-mcp-implementations/4404667) | Microsoft's overview of where the risks actually are |

### Learning more

| | |
|---|---|
| [MCP for Beginners](https://github.com/microsoft/mcp-for-beginners) | Microsoft's open-source curriculum. Cross-language, hands-on, and free |

---

## A note on scope

These demos are deliberately small. Two entities in one, two stored procedures
in the other. That is the recommended way to start: expose a handful of tools
you can describe precisely, keep them read-only until you have a reason not to,
and let the database enforce every rule that matters.

Nothing here is production configuration. Both demos run Data API builder in
development host mode with an anonymous role, which is appropriate on a laptop
and nowhere else. The security links above cover what changes when it is not a
laptop.

---

## Licence

Code and sample data are MIT licensed. See [LICENSE](./LICENSE).

Bay State Supply is fictional. Every vendor, customer, contact, item, price,
order and invoice in this repository is invented.
