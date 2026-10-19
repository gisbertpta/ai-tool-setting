"""Tests for the Jira rules. Run in cred-gw/: python3 -m unittest -v (stdlib only)."""

from __future__ import annotations

import unittest
import urllib.parse

from core import Denied
from jira_policy import API, JiraService, Plan, Policy, parse_body, plan_request, split_order_by

LABEL = 'Widerspruchsmanager'
READ_ONLY = Policy(label=LABEL, allow_writes=False)
WRITES = Policy(label=LABEL, allow_writes=True)


def jql_of(plan: Plan) -> str:
    """Return the jql parameter of a planned search query."""
    return dict(urllib.parse.parse_qsl(plan.query))['jql']


class ReadRulesTest(unittest.TestCase):
    def test_issue_reads_need_label_check(self) -> None:
        for path in (f'{API}/issue/PILOT-1', f'{API}/issue/PILOT-1/comment', f'{API}/issue/12345/transitions'):
            plan = plan_request(READ_ONLY, 'GET', path, 'startAt=0', None)
            self.assertEqual(plan.check_keys, (path.split('/')[5],))
            self.assertEqual(plan.query, 'startAt=0')

    def test_other_endpoints_are_denied(self) -> None:
        for method, path in (
            ('GET', f'{API}/project'),
            ('GET', f'{API}/user'),
            ('GET', f'{API}/issue/PILOT-1/remotelink'),
            ('GET', '/rest/agile/1.0/board/1/issue'),
            ('POST', f'{API}/search'),
            ('DELETE', f'{API}/issue/PILOT-1'),
            ('POST', f'{API}/issueLink'),
            ('GET', f'{API}/issue/PILOT-1/../../project'),
        ):
            with self.subTest(method=method, path=path), self.assertRaises(Denied):
                plan_request(WRITES, method, path, '', None)

    def test_writes_are_denied_when_read_only(self) -> None:
        with self.assertRaises(Denied) as caught:
            plan_request(READ_ONLY, 'POST', f'{API}/issue/PILOT-1/comment', '', {'body': 'x'})
        self.assertEqual(caught.exception.status, 403)


class SearchRulesTest(unittest.TestCase):
    def test_jql_is_wrapped_with_label(self) -> None:
        plan = plan_request(READ_ONLY, 'GET', f'{API}/search', 'jql=status%3DOpen&maxResults=5', None)
        self.assertEqual(jql_of(plan), f'(status=Open) AND labels = "{LABEL}"')
        self.assertIn('maxResults=5', plan.query)
        self.assertEqual(plan.check_keys, ())

    def test_order_by_stays_last(self) -> None:
        plan = plan_request(READ_ONLY, 'GET', f'{API}/search', 'jql=' + urllib.parse.quote('a = 1 order by created'), None)
        self.assertEqual(jql_of(plan), f'(a = 1 ) AND labels = "{LABEL}" order by created')

    def test_order_by_inside_quotes_is_text(self) -> None:
        condition, order_by = split_order_by('summary ~ "order by" and x = 1')
        self.assertEqual((condition, order_by), ('summary ~ "order by" and x = 1', ''))

    def test_breakout_attempts_are_denied(self) -> None:
        for jql in ('x = 1) OR (project = OTHER', 'x = 1 OR (y = 2', 'summary ~ "open', 'a = b\\) OR c = d', ''):
            with self.subTest(jql=jql), self.assertRaises(Denied):
                plan_request(READ_ONLY, 'GET', f'{API}/search', urllib.parse.urlencode({'jql': jql}), None)

    def test_quoted_parentheses_are_allowed(self) -> None:
        plan = plan_request(READ_ONLY, 'GET', f'{API}/search', urllib.parse.urlencode({'jql': 'summary ~ ")("'}), None)
        self.assertEqual(jql_of(plan), f'(summary ~ ")(") AND labels = "{LABEL}"')

    def test_duplicate_jql_is_denied(self) -> None:
        with self.assertRaises(Denied):
            plan_request(READ_ONLY, 'GET', f'{API}/search', 'jql=a%3D1&jql=b%3D2', None)


class WriteRulesTest(unittest.TestCase):
    def test_edit_keeping_label_passes(self) -> None:
        body = {'fields': {'summary': 's', 'labels': ['sdd', LABEL]}}
        self.assertEqual(plan_request(WRITES, 'PUT', f'{API}/issue/PILOT-1', '', body).check_keys, ('PILOT-1',))

    def test_edit_removing_label_is_denied(self) -> None:
        for body in ({'fields': {'labels': ['sdd']}}, {'update': {'labels': [{'remove': LABEL}]}}, None, []):
            with self.subTest(body=body), self.assertRaises(Denied):
                plan_request(WRITES, 'PUT', f'{API}/issue/PILOT-1', '', body)

    def test_transition_with_label_removal_is_denied(self) -> None:
        with self.assertRaises(Denied):
            plan_request(WRITES, 'POST', f'{API}/issue/PILOT-1/transitions', '', {'fields': {'labels': []}})

    def test_create_requires_label(self) -> None:
        with self.assertRaises(Denied):
            plan_request(WRITES, 'POST', f'{API}/issue', '', {'fields': {'summary': 's', 'labels': ['sdd']}})
        plan = plan_request(WRITES, 'POST', f'{API}/issue', '', {'fields': {'summary': 's', 'labels': [LABEL]}})
        self.assertEqual(plan.check_keys, ())

    def test_subtask_checks_parent(self) -> None:
        body = {'fields': {'labels': [LABEL.lower()], 'parent': {'key': 'PILOT-7'}}}
        self.assertEqual(plan_request(WRITES, 'POST', f'{API}/issue', '', body).check_keys, ('PILOT-7',))
        with self.assertRaises(Denied):
            plan_request(WRITES, 'POST', f'{API}/issue', '', {'fields': {'labels': [LABEL], 'parent': {}}})


class FakeJira:
    """Answers label lookups; issues in `labelled` carry the label."""

    def __init__(self, labelled: set[str]) -> None:
        self.labelled = labelled

    def get_json(self, path_query: str) -> tuple[int, object]:
        key = path_query.split('/')[5].split('?')[0]
        return 200, {'fields': {'labels': [LABEL] if key in self.labelled else ['other']}}


class ServiceTest(unittest.TestCase):
    def test_labelled_issue_passes(self) -> None:
        service = JiraService('jira.test', WRITES)
        query = service.authorize('GET', f'{API}/issue/PILOT-1', 'fields=summary', {}, None, FakeJira({'PILOT-1'}))  # type: ignore[arg-type]
        self.assertEqual(query, 'fields=summary')

    def test_unlabelled_issue_is_refused(self) -> None:
        service = JiraService('jira.test', WRITES)
        with self.assertRaises(Denied) as caught:
            service.authorize('POST', f'{API}/issue/OTHER-9/comment', '', {}, b'{"body": "x"}', FakeJira(set()))  # type: ignore[arg-type]
        self.assertEqual(caught.exception.status, 403)

    def test_invalid_json_is_refused(self) -> None:
        with self.assertRaises(Denied):
            parse_body(b'{')


if __name__ == '__main__':
    unittest.main()
