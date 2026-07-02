import boto3
import json
import uuid
from boto3.session import Session
from botocore.config import Config

# Configuration - Replace with your agent ARN and prompt
# Agent ARN example: arn:aws:bedrock-agentcore:us-west-2:XXXXXXXXXXXX:runtime/kb_agent-XXXXXXXXXX
agent_arn = 'arn:aws:bedrock-agentcore:us-west-2:115068475968:runtime/kb_agent2-A0HqkdGJAe'

# Prompt example: 'What are the main topics in the knowledge base?'
prompt = 'Do you have images? what information you can give me about them?'

# Get the current AWS region
boto_session = Session()
region = boto_session.region_name

# Extended timeout for browser operations (may take 1-3 minutes)
client_config = Config(
    read_timeout=600,
    connect_timeout=60,
    retries={"max_attempts": 2}
)

agentcore_client = boto3.client(
    'bedrock-agentcore',
    region_name=region,
    config=client_config
)

def generate_session_id():
    """Generate a unique session ID that's at least 33 characters long"""
    return str(uuid.uuid4()).replace('-', '') + str(uuid.uuid4()).replace('-', '')[:5]

# Invoke the agent
print(f"Invoking agent... (this may take a moment)")
boto3_response = agentcore_client.invoke_agent_runtime(
    agentRuntimeArn=agent_arn,
    qualifier="DEFAULT",
    runtimeSessionId=generate_session_id(),
    payload=json.dumps({"prompt": prompt})
)

# Process the response
try:
    accumulated_bytes = b""
    for event in boto3_response.get("response", []):
        accumulated_bytes += event

    # Decode with error handling for multi-byte characters
    try:
        event_data = accumulated_bytes.decode('utf-8')
    except UnicodeDecodeError:
        event_data = accumulated_bytes.decode('utf-8', errors='replace')

    # Try to parse as JSON first
    try:
        data = json.loads(event_data)
        if isinstance(data, dict) and 'content' in data:
            for item in data['content']:
                if 'text' in item:
                    print(item['text'])
        else:
            print(data)
    except json.JSONDecodeError:
        # Response is plain text, print as-is
        print(event_data)
except Exception as e:
    print(f"Error reading response: {e}")
