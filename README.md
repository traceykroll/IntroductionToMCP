# Introduction to MCP

Talk materials and two working demonstrations of the Model Context Protocol,
built for an audience of DBAs, SQL developers and business users. Each demo
contains the sample data, the code, and a full step-by-step walkthrough, with
instructions for both Claude Desktop and VS Code.

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

### MCP fundamentals

| | |
|---|---|
| [Model Context Protocol](https://modelcontextprotocol.io/) | The official site and documentation. Start here |
| [Getting started](https://modelcontextprotocol.io/docs/getting-started/intro) | Concepts and quickstarts on the same site |
| [Specification](https://modelcontextprotocol.io/specification/latest) | The authoritative protocol requirements, written for implementers |
| [Specification repository](https://github.com/modelcontextprotocol/modelcontextprotocol) | The GitHub repository behind the specification, holding the schema it is generated from and the discussion of proposed changes |
| [Reference servers](https://github.com/modelcontextprotocol/servers) | Official server implementations on GitHub, to read and to run, including the filesystem server used in demo 1 |
| [MCP Inspector](https://github.com/modelcontextprotocol/inspector) | A browser tool on GitHub that shows exactly what an agent sees. Worth running before connecting any client |
| [The original announcement](https://www.anthropic.com/news/model-context-protocol) | The post on Anthropic's blog that introduced MCP, and the problem it was built to solve |

### SQL Server

| | |
|---|---|
| [SQL MCP Server](https://learn.microsoft.com/en-us/sql/mcp/) | Microsoft Learn documentation for the open-source MCP server for SQL databases that both demos use |
| [Data API builder — MCP](https://learn.microsoft.com/en-us/azure/data-api-builder/mcp/overview) | Microsoft Learn documentation on how entities become tools |
| [VS Code quickstart](https://learn.microsoft.com/en-us/azure/data-api-builder/mcp/quickstart-visual-studio-code) | The Microsoft Learn walkthrough these demos are based on |
| [Role-based access control](https://learn.microsoft.com/en-us/azure/data-api-builder/authorization) | Microsoft Learn documentation on permissions, roles, and what production looks like |
| [SQL Server (mssql) extension](https://marketplace.visualstudio.com/items?itemName=ms-mssql.mssql) | The SQL client used throughout, from the Visual Studio Marketplace, now that Azure Data Studio has retired |

### Security

Worth reading before you expose anything you care about.

| | |
|---|---|
| [OWASP MCP Top 10 for Azure](https://microsoft.github.io/mcp-azure-security-guide/) | Microsoft's guide to the ten most critical risks, with practical advice on each |
| [MCP for Beginners: Security](https://github.com/microsoft/mcp-for-beginners/blob/main/02-Security/README.md) | The security chapter of Microsoft's curriculum on GitHub, including prompt injection and tool poisoning |
| [Security best practices](https://github.com/microsoft/mcp-for-beginners/blob/main/02-Security/mcp-best-practices.md) | Token validation, session handling and input validation, from the same curriculum |
| [Understanding and mitigating MCP security risks](https://techcommunity.microsoft.com/blog/microsoft-security-blog/understanding-and-mitigating-security-risks-in-mcp-implementations/4404667) | An overview on the Microsoft Tech Community blog of where the risks actually are |

### Learning more

| | |
|---|---|
| [MCP for Beginners](https://github.com/microsoft/mcp-for-beginners) | Microsoft's open-source curriculum on GitHub. Cross-language, hands-on, and free |

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

Content in this readme was created in part with AI. 
Last Updated: 10/3/2026