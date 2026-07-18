#!/usr/bin/env python3
"""Generate an image-to-video clip with Gemini Omni Flash without exposing the API key."""

from __future__ import annotations

import argparse
import base64
import json
import mimetypes
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path


API_ROOT = "https://generativelanguage.googleapis.com/v1beta"


def read_env_value(path: Path, name: str) -> str:
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        if key.strip() == name:
            return value.strip().strip('"').strip("'")
    raise RuntimeError(f"{name} is not set in {path}")


def request_json(url: str, api_key: str, payload: dict | None = None) -> dict:
    data = None if payload is None else json.dumps(payload).encode("utf-8")
    request = urllib.request.Request(
        url,
        data=data,
        headers={
            "Content-Type": "application/json",
            "x-goog-api-key": api_key,
        },
        method="POST" if payload is not None else "GET",
    )
    try:
        with urllib.request.urlopen(request, timeout=900) as response:
            return json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as error:
        detail = error.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"Gemini API failed ({error.code}): {detail[:1600]}") from error


def find_video_uri(response: dict) -> str:
    output = response.get("output_video") or {}
    if output.get("uri"):
        return output["uri"]

    for step in response.get("steps", []):
        for content in step.get("content", []):
            if content.get("type") == "video" and content.get("uri"):
                return content["uri"]
    raise RuntimeError("Gemini response did not contain a video URI")


def file_id_from_uri(uri: str) -> str:
    marker = "/files/"
    if marker not in uri:
        raise RuntimeError(f"Unexpected Gemini file URI: {uri}")
    return uri.split(marker, 1)[1].split(":", 1)[0].split("?", 1)[0]


def download_video(uri: str, api_key: str, output: Path) -> None:
    separator = "&" if "?" in uri else "?"
    url = f"{uri}{separator}key={urllib.parse.quote(api_key)}"
    request = urllib.request.Request(url, headers={"x-goog-api-key": api_key})
    with urllib.request.urlopen(request, timeout=900) as response:
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_bytes(response.read())


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--image", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--prompt-file", type=Path, required=True)
    parser.add_argument("--env-file", type=Path, required=True)
    args = parser.parse_args()

    api_key = read_env_value(args.env_file, "GEMINI_API_KEY")
    image_data = base64.b64encode(args.image.read_bytes()).decode("ascii")
    mime_type = mimetypes.guess_type(args.image.name)[0] or "image/png"
    prompt = args.prompt_file.read_text(encoding="utf-8").strip()

    payload = {
        "model": "gemini-omni-flash-preview",
        "input": [
            {"type": "image", "data": image_data, "mime_type": mime_type},
            {"type": "text", "text": prompt},
        ],
        "generation_config": {"video_config": {"task": "image_to_video"}},
        "response_format": {"type": "video", "aspect_ratio": "16:9", "delivery": "uri"},
        "background": False,
        "store": True,
        "stream": False,
    }

    print("Requesting Gemini Omni Flash image-to-video generation...", flush=True)
    response = request_json(f"{API_ROOT}/interactions", api_key, payload)
    video_uri = find_video_uri(response)
    file_id = file_id_from_uri(video_uri)

    deadline = time.time() + 1200
    while time.time() < deadline:
        status = request_json(f"{API_ROOT}/files/{file_id}", api_key)
        state = status.get("state", "UNKNOWN")
        if isinstance(state, dict):
            state = state.get("name", "UNKNOWN")
        print(f"Video state: {state}", flush=True)
        if state == "ACTIVE":
            break
        if state == "FAILED":
            raise RuntimeError("Gemini video processing failed")
        time.sleep(5)
    else:
        raise TimeoutError("Timed out waiting for Gemini video")

    download_video(video_uri, api_key, args.output)
    print(f"Saved {args.output} ({args.output.stat().st_size} bytes)", flush=True)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as error:
        print(str(error), file=sys.stderr)
        raise SystemExit(1)
