from __future__ import annotations

import json
from typing import Any
from urllib import error, parse, request


class CloudflareApiError(RuntimeError):
    pass


def summarize_error_body(body: str, limit: int = 240) -> str:
    normalized = " ".join(body.split())
    if not normalized:
        return "<empty body>"
    if len(normalized) <= limit:
        return normalized
    return normalized[:limit] + "..."


class CloudflareClient:
    def __init__(self, api_token: str, base_url: str = "https://api.cloudflare.com/client/v4", per_page: int = 100, timeout: int = 30):
        self.api_token = api_token
        self.base_url = base_url.rstrip("/")
        self.per_page = per_page
        self.timeout = timeout

    def _build_url(self, path: str, query: dict[str, Any] | None = None) -> str:
        normalized_path = path if path.startswith("/") else f"/{path}"
        if not query:
            return f"{self.base_url}{normalized_path}"
        encoded = parse.urlencode({key: value for key, value in query.items() if value is not None}, doseq=True)
        return f"{self.base_url}{normalized_path}?{encoded}"

    def _request_json(self, path: str, query: dict[str, Any] | None = None) -> dict[str, Any]:
        url = self._build_url(path, query)
        http_request = request.Request(
            url,
            method="GET",
            headers={
                "Authorization": f"Bearer {self.api_token}",
                "Content-Type": "application/json",
                "User-Agent": "tomshley-cloudflare-import/0.1",
            },
        )
        try:
            with request.urlopen(http_request, timeout=self.timeout) as response:
                payload_text = response.read().decode("utf-8")
        except error.HTTPError as exc:
            body = exc.read().decode("utf-8", errors="replace")
            raise CloudflareApiError(f"HTTP {exc.code} for {url}: {summarize_error_body(body)}") from exc
        except error.URLError as exc:
            raise CloudflareApiError(f"Request failed for {url}: {exc.reason}") from exc

        try:
            payload = json.loads(payload_text)
        except json.JSONDecodeError as exc:
            raise CloudflareApiError(f"Invalid JSON response from {url}: {summarize_error_body(payload_text)}") from exc

        if payload.get("success") is False:
            errors = payload.get("errors") or []
            messages = "; ".join(str(item) for item in errors) or "Unknown Cloudflare API error"
            raise CloudflareApiError(f"Cloudflare API reported failure for {url}: {messages}")

        return payload

    def get_result(self, path: str, query: dict[str, Any] | None = None) -> Any:
        return self._request_json(path, query).get("result")

    def get_paginated(self, path: str, query: dict[str, Any] | None = None, max_pages: int = 1000) -> list[dict[str, Any]]:
        page = 1
        items: list[dict[str, Any]] = []
        while page <= max_pages:
            page_query = dict(query or {})
            page_query["page"] = page
            page_query.setdefault("per_page", self.per_page)
            effective_per_page = int(page_query["per_page"])
            payload = self._request_json(path, page_query)
            result = payload.get("result")

            if isinstance(result, list):
                page_items = result
            elif isinstance(result, dict) and isinstance(result.get("items"), list):
                page_items = result["items"]
            else:
                if result is None:
                    return items
                raise CloudflareApiError(f"Expected paginated list result for {path}, got {type(result).__name__}")

            items.extend(page_items)

            result_info = payload.get("result_info") or {}
            total_pages = result_info.get("total_pages")
            if total_pages is not None:
                if page >= int(total_pages):
                    break
            elif len(page_items) < effective_per_page:
                break

            page += 1

        return items
