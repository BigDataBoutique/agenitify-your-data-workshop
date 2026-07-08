import os
from pathlib import Path
from urllib.parse import urlsplit, urlunsplit, parse_qsl, urlencode

from strands import Agent, tool
from strands.models import BedrockModel
from bedrock_agentcore.runtime import BedrockAgentCoreApp
from kb_agent_tools import search_knowledge_base
from rekognition_tool import extract_text_from_all_images

import psycopg
from psycopg.rows import dict_row

app = BedrockAgentCoreApp()

# --- SQL (PostgreSQL) tool --------------------------------------------------
# Connection is assembled from three separate env vars (rather than a single
# DSN) so credentials and the JDBC-style connection string can be configured
# independently: POSTGRES_USER, POSTGRES_PASSWORD, POSTGRES_JDBC_URL
# (e.g. jdbc:postgresql://host:5432/dbname).

MAX_ROWS = 100  # cap rows returned to the model to keep context small


def _connect():
    user = os.environ.get("POSTGRES_USER")
    password = os.environ.get("POSTGRES_PASSWORD")
    jdbc_url = os.environ.get("POSTGRES_JDBC_URL")
    if not (user and password and jdbc_url):
        raise RuntimeError(
            "Postgres is not configured. Set POSTGRES_USER, POSTGRES_PASSWORD, "
            "and POSTGRES_JDBC_URL (e.g. jdbc:postgresql://host:5432/dbname)."
        )
    conn_target = jdbc_url.removeprefix("jdbc:postgresql://")
    dsn = f"postgresql://{user}:{password}@{conn_target}"

    # JDBC's "ssl" query param has no libpq equivalent by that name; psycopg
    # expects "sslmode" instead, so translate it rather than erroring out.
    parts = urlsplit(dsn)
    query = dict(parse_qsl(parts.query))
    if "ssl" in query:
        ssl_value = query.pop("ssl")
        query.setdefault("sslmode", {"true": "require", "false": "disable"}.get(ssl_value, ssl_value))
    dsn = urlunsplit(parts._replace(query=urlencode(query)))

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
    that writes is rejected. Use this for questions about orders, order
    items, or customers. Results are capped at the first 100 rows.

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


# text2sql: feed the model a curated schema + few-shot examples, injected
# verbatim into the system prompt (see schema.sql / query_examples.md).
_BASE_DIR = Path(__file__).resolve().parent


def _load_text(filename: str) -> str:
    try:
        return (_BASE_DIR / filename).read_text(encoding="utf-8").strip()
    except FileNotFoundError:
        return ""


SCHEMA_DOC = _load_text("schema.sql")
QUERY_EXAMPLES = _load_text("query_examples.md")

_prompt_parts = [
    "For questions about orders, order items, or customers, write a single "
    "read-only PostgreSQL SELECT and run it with query_database. Rely on the "
    "schema below; only call db_schema if you need something not shown here.",
]
if SCHEMA_DOC:
    _prompt_parts.append("## Database schema (PostgreSQL)\n" + SCHEMA_DOC)
if QUERY_EXAMPLES:
    _prompt_parts.append("## Example questions and their SQL\n" + QUERY_EXAMPLES)

DB_PROMPT = "\n\n".join(_prompt_parts)

# Initialize the Bedrock model (Anthropic Claude Sonnet 4.5)
model = BedrockModel(
    model_id="us.anthropic.claude-sonnet-4-5-20250929-v1:0",
    temperature=0.3
)

# AgentCore endpoint
@app.entrypoint
def strands_agent_bedrock(payload):
    # Create the agent inside the entrypoint — each request gets its own instance
    # This allows multiple users to invoke the agent concurrently without conflicts
 # Create the agent inside the entrypoint
    agent = Agent(
        model=model,
        tools=[
            search_knowledge_base,
            extract_text_from_all_images,
            db_schema,
            query_database,
        ],
        system_prompt=f"""
When using tools:
1. If the question has to do with orders, order items, or customers, use the query_database tool to run a read-only SQL SELECT query and answer from its results, instead of searching the knowledge base.
{DB_PROMPT}
2. Otherwise, always use search_knowledge_base first for any question.
3. If search_knowledge_base returns no relevant results, call extract_text_from_all_images before giving up. It takes no arguments — it scans all images in the configured bucket and returns each image name with its detected text. Use whatever text it finds to answer the user.
4. If neither tool has the answer, let the user know. Ask them if they want to help in maintaining the knowledge base.

Tone: helpful, friendly tone. Feel free to make puns in Hebrew.
"""
      )  # <<==👈 Customize this prompt for YOUR use case
    try:
        user_input = payload.get("prompt")
        history = payload.get("history", [])

        # Build context from conversation history
        if history:
            context = chr(10).join([f"{'User' if msg.get('role')=='user' else 'Assistant'}: {msg.get('content','')}" for msg in history])
            full_prompt = f"Previous conversation:{chr(10)}{context}{chr(10)}{chr(10)}New user message: {user_input}"
        else:
            full_prompt = user_input

        response = agent(full_prompt)

        # Collect all content blocks from the response
        content_blocks = response.message.get('content', [])
        result_parts = []
        for block in content_blocks:
            if isinstance(block, dict):
                if 'text' in block:
                    result_parts.append(block['text'])
            elif isinstance(block, str):
                result_parts.append(block)

        return chr(10).join(result_parts) if result_parts else "No response generated."
    finally:
        print("[Agent] Request completed")

if __name__ == "__main__":
    app.run()
