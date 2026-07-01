"""Minimal AgentCore app using Strands with web search + calculator + SQL tools.

Run locally:   python agent.py
Then invoke:   curl -XPOST http://localhost:8080/invocations \
                    -H 'content-type: application/json' \
                    -d '{"prompt": "What is 23*19, and who won the 2024 Euros?"}'

SQL access:
    Neither Strands (strands_tools) nor Bedrock AgentCore ship a built-in
    SQL/PostgreSQL tool, so the database tools below are plain Strands custom
    @tool functions backed by psycopg (psycopg3). Configure the connection via
    the DATABASE_URL env var, e.g.:
        export DATABASE_URL='postgresql://user:pass@host:5432/dbname'
    For production on AgentCore, prefer a read-only DB role and pull the
    connection string from AWS Secrets Manager rather than a plain env var.

text2sql:
    The agent reasons over a curated schema injected into its system prompt.
    Edit these two files to tune SQL accuracy (no code changes needed):
        schema.sql         - annotated DDL (types, FKs, column comments, sample
                             values) describing your tables.
        query_examples.md  - verified question -> SQL few-shot examples.

Dependencies: psycopg[binary]  (pip install "psycopg[binary]")
"""

import os
from pathlib import Path

from bedrock_agentcore.runtime import BedrockAgentCoreApp
from strands import Agent, tool
from strands_tools import calculator  # built-in math tool

import psycopg
from psycopg.rows import dict_row

from ddgs import DDGS

app = BedrockAgentCoreApp()


@tool
def web_search(query: str, max_results: int = 5) -> str:
    """Search the web and return the top results.

    Args:
        query: The search query.
        max_results: Number of results to return (default 5).
    """
    with DDGS() as ddgs:
        hits = list(ddgs.text(query, max_results=max_results))
    if not hits:
        return "No results found."
    return "\n\n".join(
        f"{h['title']}\n{h['href']}\n{h['body']}" for h in hits
    )


# --- SQL (PostgreSQL) tools -------------------------------------------------
# Path of least resistance: a direct psycopg connection per call. No pool is
# needed for AgentCore's request/response model; for high throughput swap in
# psycopg_pool.ConnectionPool.

MAX_ROWS = 100  # cap rows returned to the model to keep context small


def _connect():
    dsn = os.environ.get("DATABASE_URL")
    if not dsn:
        raise RuntimeError(
            "DATABASE_URL is not set. Export e.g. "
            "postgresql://user:pass@host:5432/dbname"
        )
    return psycopg.connect(dsn)


@tool
def db_schema(table: str = "") -> str:
    """Inspect the PostgreSQL schema so you know what you can query.

    Call this before writing a query when you are unsure of table or column
    names. With no argument it lists all tables; with a table name it lists
    that table's columns and types.

    Args:
        table: Optional table name. Empty lists all tables in the public schema.
    """
    try:
        with _connect() as conn, conn.cursor(row_factory=dict_row) as cur:
            if table:
                cur.execute(
                    """
                    SELECT column_name, data_type, is_nullable
                    FROM information_schema.columns
                    WHERE table_schema = 'public' AND table_name = %s
                    ORDER BY ordinal_position
                    """,
                    (table,),
                )
                rows = cur.fetchall()
                if not rows:
                    return f"No table named '{table}' found in the public schema."
                lines = [f"Columns of {table}:"]
                lines += [
                    f"  {r['column_name']}: {r['data_type']}"
                    f"{' (nullable)' if r['is_nullable'] == 'YES' else ''}"
                    for r in rows
                ]
                return "\n".join(lines)

            cur.execute(
                """
                SELECT table_name
                FROM information_schema.tables
                WHERE table_schema = 'public' AND table_type = 'BASE TABLE'
                ORDER BY table_name
                """
            )
            tables = [r["table_name"] for r in cur.fetchall()]
            if not tables:
                return "No tables found in the public schema."
            return "Tables:\n" + "\n".join(f"  {t}" for t in tables)
    except Exception as exc:  # surface errors to the model instead of crashing
        return f"Schema lookup failed: {exc}"


@tool
def query_database(sql: str) -> str:
    """Run a read-only SQL SELECT query against the PostgreSQL database.

    Only a single SELECT (or WITH ... SELECT) statement is allowed; anything
    that writes is rejected. Use db_schema first if you don't know the schema.
    Results are capped at the first 100 rows.

    Args:
        sql: A single read-only SELECT statement.
    """
    stripped = sql.strip().rstrip(";").strip()
    if not stripped:
        return "Empty query."

    lowered = stripped.lower()
    if not (lowered.startswith("select") or lowered.startswith("with")):
        return "Rejected: only SELECT / WITH queries are allowed."
    if ";" in stripped:
        return "Rejected: only a single statement is allowed (no ';')."

    try:
        # A read-only transaction is the real guardrail; the prefix check above
        # is just a fast fail. Postgres will block any write inside this block.
        with _connect() as conn:
            conn.read_only = True
            with conn.cursor(row_factory=dict_row) as cur:
                cur.execute(stripped)
                rows = cur.fetchmany(MAX_ROWS)
                if not rows:
                    return "Query returned no rows."
                header = list(rows[0].keys())
                lines = [" | ".join(header)]
                lines += [
                    " | ".join("" if r[c] is None else str(r[c]) for c in header)
                    for r in rows
                ]
                if len(rows) == MAX_ROWS:
                    lines.append(f"... (truncated at {MAX_ROWS} rows)")
                return "\n".join(lines)
    except Exception as exc:
        return f"Query failed: {exc}"


# --- text2sql: feed the model a curated schema + few-shot examples ----------
# For a small schema (<~30 tables) the cheapest, most reliable approach is to
# inject the whole annotated schema into the system prompt at startup rather
# than make the model discover it via tool calls. Both files are read verbatim,
# so edit them directly to tune the agent's SQL accuracy. db_schema remains as a
# runtime fallback for anything not covered by schema.sql.

_BASE_DIR = Path(__file__).resolve().parent


def _load_text(filename: str) -> str:
    try:
        return (_BASE_DIR / filename).read_text(encoding="utf-8").strip()
    except FileNotFoundError:
        return ""


SCHEMA_DOC = _load_text("schema.sql")
QUERY_EXAMPLES = _load_text("query_examples.md")

_prompt_parts = [
    "You are a concise assistant. Use web_search for current facts "
    "and calculator for any arithmetic. Cite sources when you search.",
    "For questions about data, write a single read-only PostgreSQL SELECT "
    "and run it with query_database. Rely on the schema below; only call "
    "db_schema if you need something not shown here.",
]
if SCHEMA_DOC:
    _prompt_parts.append("## Database schema (PostgreSQL)\n" + SCHEMA_DOC)
if QUERY_EXAMPLES:
    _prompt_parts.append("## Example questions and their SQL\n" + QUERY_EXAMPLES)

SYSTEM_PROMPT = "\n\n".join(_prompt_parts)

agent = Agent(
    system_prompt=SYSTEM_PROMPT,
    tools=[web_search, calculator, db_schema, query_database],
)


@app.entrypoint
def invoke(payload):
    """AgentCore runtime entrypoint."""
    result = agent(payload.get("prompt", ""))
    return {"result": result.message}


if __name__ == "__main__":
    app.run()
