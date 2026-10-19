"""Jira Data Center rules: every request stays inside one label on a shared board.

- GET  /rest/api/2/issue/{key}[/comment|/transitions]  the issue must carry the label
- GET  /rest/api/2/search?jql=...                      JQL is wrapped: (<jql>) AND labels = "<label>"
- with writes enabled also:
  PUT  /rest/api/2/issue/{key}                         issue must carry the label; the edit must keep it
  POST /rest/api/2/issue/{key}/comment                 issue must carry the label
  POST /rest/api/2/issue/{key}/transitions             issue must carry the label; field updates must keep it
  POST /rest/api/2/issue                               new issue must carry the label; a parent must carry it too

Everything else is refused.
"""

from __future__ import annotations

import json
import re
import urllib.parse
from collections.abc import Mapping
from dataclasses import dataclass
from typing import Any

from core import Denied, Upstream

API = '/rest/api/2'
ISSUE_REF = r'(?:[A-Z][A-Z0-9_]+-\d+|\d+)'
ISSUE_PATH = re.compile(rf'^{API}/issue/(?P<key>{ISSUE_REF})(?P<sub>/comment|/transitions)?$')
MAX_BODY_BYTES = 1_000_000


@dataclass(frozen=True)
class Policy:
    """The gateway's rules: the label that scopes every request and whether writes are allowed."""

    label: str
    allow_writes: bool


@dataclass(frozen=True)
class Plan:
    """What to do with an allowed request.

    Attributes:
        check_keys: issues that must carry the label before the request is forwarded.
        query: the query string to forward (rewritten for search).
    """

    check_keys: tuple[str, ...]
    query: str


def plan_request(policy: Policy, method: str, path: str, query: str, body: Any) -> Plan:
    """Decide whether a request may pass and which label checks it needs.

    Raises:
        Denied: when no rule allows the request.
    """
    if method == 'GET' and path == f'{API}/search':
        return Plan((), scoped_search_query(query, policy.label))
    match = ISSUE_PATH.match(path)
    if method == 'GET' and match:
        return Plan((match['key'],), query)
    if method in ('PUT', 'POST') and not policy.allow_writes:
        raise Denied(403, 'jira-gw is read-only')
    if method == 'PUT' and match and not match['sub']:
        require_label_kept(body, policy.label)
        return Plan((match['key'],), query)
    if method == 'POST' and match and match['sub'] == '/comment':
        return Plan((match['key'],), query)
    if method == 'POST' and match and match['sub'] == '/transitions':
        require_label_kept(body, policy.label)
        return Plan((match['key'],), query)
    if method == 'POST' and path == f'{API}/issue':
        return Plan(new_issue_checks(body, policy.label), query)
    raise Denied(403, f'{method} {path} is not allowed by jira-gw')


def scoped_search_query(query: str, label: str) -> str:
    """Return the query string with the JQL restricted to the label.

    Raises:
        Denied: when the JQL is missing or could escape the wrapping parentheses.
    """
    params = urllib.parse.parse_qsl(query, keep_blank_values=True)
    jql_values = [value for name, value in params if name == 'jql']
    if len(jql_values) != 1:
        raise Denied(400, 'search needs exactly one jql parameter')
    condition, order_by = split_order_by(jql_values[0])
    if not condition.strip():
        raise Denied(400, 'search needs a JQL condition')
    scoped = f'({condition}) AND labels = "{label}"{order_by}'
    rest = [(name, value) for name, value in params if name != 'jql']
    return urllib.parse.urlencode([('jql', scoped), *rest])


def split_order_by(jql: str) -> tuple[str, str]:
    """Split JQL into condition and a trailing ' ORDER BY ...' clause, checking quotes and parentheses.

    Raises:
        Denied: on unbalanced parentheses or quotes, or a backslash outside quotes; each could break out of the
            wrapping parentheses.
    """
    depth = 0
    quote = ''
    escaped = False
    order_at = -1
    for index, char in enumerate(jql):
        if escaped:
            escaped = False
        elif quote:
            if char == '\\':
                escaped = True
            elif char == quote:
                quote = ''
        elif char == '\\':
            raise Denied(400, 'backslash outside a quoted JQL string is not allowed')
        elif char in '"\'':
            quote = char
        elif char == '(':
            depth += 1
        elif char == ')':
            depth -= 1
            if depth < 0:
                raise Denied(400, 'unbalanced parentheses in JQL')
        elif depth == 0 and order_at < 0 and re.match(r'(?i)\border\s+by\b', jql[index:]):
            if index == 0 or not (jql[index - 1].isalnum() or jql[index - 1] == '_'):
                order_at = index
    if quote or escaped or depth:
        raise Denied(400, 'unbalanced quotes or parentheses in JQL')
    if order_at < 0:
        return jql, ''
    return jql[:order_at], ' ' + jql[order_at:].strip()


def require_label_kept(body: Any, label: str) -> None:
    """Refuse an edit that could remove the label.

    Raises:
        Denied: when the body is no JSON object, uses `update.labels`, or sets `fields.labels` without the label.
    """
    if not isinstance(body, dict):
        raise Denied(400, 'JSON object body required')
    update = body.get('update')
    if isinstance(update, dict) and 'labels' in update:
        raise Denied(403, 'update.labels is not allowed; set fields.labels including the project label')
    fields = body.get('fields')
    if isinstance(fields, dict) and 'labels' in fields and not has_label(fields['labels'], label):
        raise Denied(403, f'fields.labels must keep {label!r}')


def new_issue_checks(body: Any, label: str) -> tuple[str, ...]:
    """Check a create body; return the parent key whose label must be checked, if any.

    Raises:
        Denied: when the new issue would not carry the label.
    """
    require_label_kept(body, label)
    fields = body.get('fields')
    if not isinstance(fields, dict) or not has_label(fields.get('labels'), label):
        raise Denied(403, f'a new issue must carry the label {label!r} in fields.labels')
    parent = fields.get('parent')
    if parent is None:
        return ()
    ref = (parent.get('key') or parent.get('id')) if isinstance(parent, dict) else None
    if not isinstance(ref, str) or not re.fullmatch(ISSUE_REF, ref):
        raise Denied(400, 'fields.parent needs a key or id')
    return (ref,)


def has_label(raw: Any, label: str) -> bool:
    """True when a labels value (list of strings) contains the label, ignoring case like the agent scripts."""
    return isinstance(raw, list) and label.casefold() in {str(item).strip().casefold() for item in raw}


def parse_body(raw: bytes | None) -> Any:
    """Decode a JSON request body; None when there is none.

    Raises:
        Denied: when the body is too large or no valid JSON.
    """
    if raw is None:
        return None
    if len(raw) > MAX_BODY_BYTES:
        raise Denied(413, 'request body too large')
    try:
        return json.loads(raw)
    except ValueError as error:
        raise Denied(400, 'request body is no valid JSON') from error


def bearer(token: str) -> dict[str, str]:
    """Credential headers for Jira Data Center (personal access token)."""
    return {'Authorization': f'Bearer {token}'}


@dataclass(frozen=True)
class JiraService:
    """Jira behind the gateway."""

    host: str
    policy: Policy

    def authorize(
        self, method: str, path: str, query: str, headers: Mapping[str, str], body: bytes | None, upstream: Upstream
    ) -> str:
        """Apply the label rules; look up the label of every issue the request touches.

        Raises:
            Denied: when a rule refuses the request or an issue does not carry the label.
        """
        plan = plan_request(self.policy, method, path, query, parse_body(body))
        for key in plan.check_keys:
            status, issue = upstream.get_json(f'{API}/issue/{urllib.parse.quote(key)}?fields=labels')
            fields = issue.get('fields') if status == 200 and isinstance(issue, dict) else None
            if not isinstance(fields, dict) or not has_label(fields.get('labels'), self.policy.label):
                raise Denied(403, f'{key} does not carry the label {self.policy.label!r}')
        return plan.query
