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

        # Paginate through all objects in the bucket
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
