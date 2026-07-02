from strands import tool
from strands_tools import retrieve
from boto3.session import Session
import os

# Get the current AWS region
boto_session = Session()
region = boto_session.region_name

# Configuration - Replace with your Knowledge Base ID
KNOWLEDGE_BASE_ID = "COMPLETE"

# setting up env variables for kb access
os.environ["KNOWLEDGE_BASE_ID"] = KNOWLEDGE_BASE_ID
os.environ["AWS_REGION"] = region
os.environ["MIN_SCORE"] = "0.4"


@tool
def search_knowledge_base(query: str) -> str:
    """
    Search the knowledge base for information related to the query.

    Args:
        query: The search query to find relevant information.

    Returns:
        Relevant information from the knowledge base.
    """
    try:
        tool_use = {
            "toolUseId": "search_kb",
            "input": {
                "text": query,
            }
        }
        result = retrieve.retrieve(tool_use)

        if result["status"] == "success":
            return result["content"][0]["text"]
        else:
            return f"Unable to access knowledge base. Error: {result['content'][0]['text']}"

    except Exception as e:
        return f"Unable to access knowledge base. Error: {str(e)}"