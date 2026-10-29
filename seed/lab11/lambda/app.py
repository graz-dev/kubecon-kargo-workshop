"""Guestbook backend Lambda, fronted by a Lambda Function URL.

Stateless on purpose for simplicity sake. For something real, you could configure
it to write to DynamoDB or S3.

GET  -> { stage, version, message }
POST -> echoes the posted entry back in the response.
"""

import json
import os

STAGE = os.environ.get("STAGE", "unknown")
VERSION = os.environ.get("VERSION", "dev")

# CORS is handled by the Lambda Function URL `cors` config (see terraform), so we
# must NOT also set Access-Control-* headers here — duplicate
# Access-Control-Allow-Origin headers make browsers reject the response.
_HEADERS = {"Content-Type": "application/json"}


def _response(status, body):
    return {"statusCode": status, "headers": _HEADERS, "body": json.dumps(body)}


def _method(event):
    # Lambda Function URLs use the API Gateway v2 (HTTP API) event shape.
    return (
        event.get("requestContext", {})
        .get("http", {})
        .get("method", event.get("httpMethod", "GET"))
        .upper()
    )


def lambda_handler(event, context):
    method = _method(event)

    if method == "OPTIONS":
        return _response(200, {"ok": True})

    if method == "GET":
        return _response(200, {
            "stage": STAGE,
            "version": VERSION,
            "message": f"Hello from the guestbook backend — deployed by Kargo + Terraform (stage {STAGE}, version {VERSION})",
        })

    if method == "POST":
        body = event.get("body") or "{}"
        if event.get("isBase64Encoded"):
            import base64
            body = base64.b64decode(body).decode("utf-8")
        try:
            payload = json.loads(body)
        except json.JSONDecodeError:
            payload = {}
        return _response(201, {"ok": True, "echo": payload, "version": VERSION})

    return _response(405, {"ok": False, "error": f"method {method} not allowed"})
