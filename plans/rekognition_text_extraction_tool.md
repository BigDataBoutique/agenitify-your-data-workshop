# Plan: Rekognition Image Text Extraction Tool

## Goal

Add a tool that scans all images in a configured S3 bucket and uses AWS Rekognition `DetectText` to extract text from each one. Results are returned per image. The tool works with credentials for a cross-account AWS setup.

---

## Credential Approach: Cross-Account Role Assumption

The runtime (`AgentCoreRuntimeRole` in account `115068475968`) assumes `RekognitionAccessRole` in the target account (`506746133768`) via STS. The role ARN is passed at deploy time via the `REKOGNITION_ROLE_ARN` environment variable. If the variable is absent, the default session credentials are used (same-account scenario).

The S3 bucket name is passed via `REKOGNITION_BUCKET`. Both variables are read from the environment at module load time.

The S3 bucket **must be in the same region as the Rekognition endpoint** (`AWS_REGION`).

---

## Implementation

### `rekognition_tool.py`

```python
from strands import tool
import boto3
import os
from boto3.session import Session

_boto_session = Session()
REGION = os.environ.get("AWS_REGION", _boto_session.region_name)
REKOGNITION_ROLE_ARN = os.environ.get("REKOGNITION_ROLE_ARN")
REKOGNITION_BUCKET = os.environ.get("REKOGNITION_BUCKET")

IMAGE_EXTENSIONS = {".jpg", ".jpeg", ".png", ".bmp", ".webp", ".gif"}


def _get_session():
    if REKOGNITION_ROLE_ARN:
        sts = boto3.client("sts")
        assumed = sts.assume_role(
            RoleArn=REKOGNITION_ROLE_ARN,
            RoleSessionName="rekognition-tool-session",
        )
        creds = assumed["Credentials"]
        return boto3.Session(
            aws_access_key_id=creds["AccessKeyId"],
            aws_secret_access_key=creds["SecretAccessKey"],
            aws_session_token=creds["SessionToken"],
            region_name=REGION,
        )
    return boto3.Session(region_name=REGION)


@tool
def extract_text_from_all_images() -> str:
    """
    List all images in the configured S3 bucket and extract text from each one
    using AWS Rekognition DetectText.

    Returns:
        For each image: its name followed by the detected text lines.
        Images with no detected text are noted but still included.
    """
    if not REKOGNITION_BUCKET:
        return "Image extraction is not configured: REKOGNITION_BUCKET environment variable is missing."

    try:
        session = _get_session()
        s3 = session.client("s3")
        rekognition = session.client("rekognition")

        keys = []
        paginator = s3.get_paginator("list_objects_v2")
        for page in paginator.paginate(Bucket=REKOGNITION_BUCKET):
            for obj in page.get("Contents", []):
                key = obj["Key"]
                ext = os.path.splitext(key)[1].lower()
                if ext in IMAGE_EXTENSIONS:
                    keys.append(key)

        if not keys:
            return f"No images found in bucket '{REKOGNITION_BUCKET}'."

        results = []
        for key in keys:
            response = rekognition.detect_text(
                Image={"S3Object": {"Bucket": REKOGNITION_BUCKET, "Name": key}}
            )
            lines = [
                d["DetectedText"]
                for d in response.get("TextDetections", [])
                if d["Type"] == "LINE"
            ]
            text = "\n  ".join(lines) if lines else "(no text detected)"
            results.append(f"{key}:\n  {text}")

        return "\n\n".join(results)

    except Exception as e:
        return f"Failed to extract text from images. Error: {str(e)}"
```

### `kb_agent.py` — registration and system prompt

```python
from rekognition_tool import extract_text_from_all_images

agent = Agent(
    model=model,
    tools=[search_knowledge_base, extract_text_from_all_images],
    system_prompt="""
When using tools:
1. Always use search_knowledge_base first for any question.
2. If search_knowledge_base returns no relevant results, call extract_text_from_all_images before giving up. It takes no arguments — it scans all images in the configured bucket and returns each image name with its detected text. Use whatever text it finds to answer the user.
3. If neither tool has the answer, let the user know.
"""
)
```

### `kb_agent_deploy.py` — environment variables at deploy time

`REKOGNITION_ROLE_ARN` and `REKOGNITION_BUCKET` are read from the environment and forwarded to the runtime via `launch(env_vars=...)`. Deploy with:

```bash
uv run --env REKOGNITION_ROLE_ARN=arn:aws:iam::506746133768:role/RekognitionAccessRole \
        --env REKOGNITION_BUCKET=bdb-rekognition-test \
        kb_agent_deploy.py
```

---

## IAM Permissions

### `RekognitionAccessRole` (account `506746133768`) — permissions policy

```json
{
  "Statement": [
    {
      "Sid": "AllowDetectText",
      "Effect": "Allow",
      "Action": "rekognition:DetectText",
      "Resource": "*"
    },
    {
      "Sid": "AllowS3Access",
      "Effect": "Allow",
      "Action": ["s3:ListBucket", "s3:GetObject"],
      "Resource": [
        "arn:aws:s3:::bdb-rekognition-test",
        "arn:aws:s3:::bdb-rekognition-test/*"
      ]
    }
  ]
}
```

### `RekognitionAccessRole` — trust policy

```json
{
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::115068475968:role/AgentCoreRuntimeRole"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
```

### `AgentCoreRuntimeRole` (account `115068475968`) — inline policy (added manually to agent account)

```json
{
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "sts:AssumeRole",
      "Resource": "arn:aws:iam::506746133768:role/RekognitionAccessRole"
    }
  ]
}
```

---

## Terraform (`terraform/`)

Manages the target account (`506746133768`) resources:

- **S3 bucket** (`bdb-rekognition-test`) with AES256 encryption and public access blocked, in the same region as the runtime (`us-west-2`)
- **Bucket policy** granting `s3:ListBucket` and `s3:GetObject` to `RekognitionAccessRole`
- **`RekognitionAccessRole`** with trust policy allowing `AgentCoreRuntimeRole` to assume it
- **Inline policy** on the role granting `rekognition:DetectText`, `s3:ListBucket`, and `s3:GetObject`

The `sts:AssumeRole` permission on `AgentCoreRuntimeRole` (runtime account) is managed manually as it lives in a separate account.

Apply:
```bash
terraform apply \
  -var="bucket_name=bdb-rekognition-test" \
  -var="runtime_account_id=115068475968" \
  -var="aws_region=us-west-2"
```

---

## Decision Summary

| Item | Decision |
|---|---|
| Credentials | Cross-account STS AssumeRole via `REKOGNITION_ROLE_ARN` env var |
| Bucket | Plain bucket name via `REKOGNITION_BUCKET` env var (not ARN or URL) |
| Scope | All images in the bucket (paginated), filtered by extension |
| Region | Must match between S3 bucket and Rekognition endpoint (`us-west-2`) |
| Runtime account IAM | Added manually (separate AWS account from Terraform target) |
