import os
import json
import time
import base64
import boto3

s3 = boto3.client("s3")

BUCKET = os.environ["BUCKET"]
PREFIX = os.environ["PREFIX"]

ROUTES = {
    "/": ("index.html", "text/html"),
    "/index.html": ("index.html", "text/html"),
    "/style.css": ("style.css", "text/css"),
    "/cv.pdf": ("cv.pdf", "application/pdf"),
}


def lambda_handler(event, context):
    start = time.time()
    path = event.get("rawPath", "/")
    route = ROUTES.get(path)

    if route is None:
        status = 404
        response = {
            "statusCode": 404,
            "headers": {"Content-Type": "text/html"},
            "body": "<html><body><h1>404</h1><p>Page not found.</p></body></html>",
        }
    else:
        name, content_type = route
        try:
            obj = s3.get_object(Bucket=BUCKET, Key=PREFIX + name)
            data = obj["Body"].read()
            headers = {"Content-Type": content_type}

            if content_type == "application/pdf":
                response = {
                    "statusCode": 200,
                    "headers": headers,
                    "body": base64.b64encode(data).decode("utf-8"),
                    "isBase64Encoded": True,
                }
            else:
                text = data.decode("utf-8")
                if name == "index.html":
                    text = text.replace("{{HOSTED_ON}}", "Lambda " + context.function_name)
                    headers["Cache-Control"] = "max-age=60"
                response = {"statusCode": 200, "headers": headers, "body": text}
            status = 200
        except Exception:
            status = 500
            response = {
                "statusCode": 500,
                "headers": {"Content-Type": "text/html"},
                "body": "<html><body><h1>500</h1><p>Server error.</p></body></html>",
            }

    ms = int((time.time() - start) * 1000)
    print(json.dumps({"fn": context.function_name, "path": path, "status": status, "ms": ms}))
    return response
