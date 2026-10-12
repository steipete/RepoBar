#!/usr/bin/env python3
import importlib.util
from pathlib import Path
import tempfile
import os
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('validate', Path(__file__).with_name('validate-release.py'))
validate = importlib.util.module_from_spec(spec)
spec.loader.exec_module(validate)

class ReleaseValidationTests(unittest.TestCase):
    def test_notes_are_exact_and_stop_at_next_section(self):
        source = '# Changelog\n\n## Unreleased\n\n- Later\n\n## 1.2.3 - 2026-01-01\n\n- Shipped\n\n## 1.2.2 - 2025-12-01\n\n- Older\n'
        self.assertEqual(validate.notes_for(source, '1.2.3'), '## 1.2.3 - 2026-01-01\n\n- Shipped\n')

    def test_existing_draft_is_found(self):
        with patch.object(validate, 'api', return_value=[{'tag_name':'v1.2.3', 'draft':True, 'id':42}]):
            self.assertEqual(validate.release_for_tag('owner/repo', 'v1.2.3')['id'], 42)

    def test_release_search_checks_later_pages(self):
        pages = [[{'tag_name': 'v0.1.0'}] * 100, [{'tag_name':'v1.2.3', 'id':42}]]
        with patch.object(validate, 'api', side_effect=pages):
            self.assertEqual(validate.release_for_tag('owner/repo', 'v1.2.3')['id'], 42)

    def test_nonincreasing_sparkle_build_is_rejected(self):
        import base64
        feed = '<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><item><sparkle:version>34</sparkle:version></item></channel></rss>'
        with patch.object(validate, 'api', return_value={'content':base64.b64encode(feed.encode()).decode()}):
            for build in [33,34]:
                with self.assertRaisesRegex(ValueError, 'exceed'):
                    validate.check_appcast_build('owner/repo', build)
            validate.check_appcast_build('owner/repo', 35)

    def test_bad_notes_fail_closed(self):
        for source in ['## 1.2.3\n- No date', '## 1.2.3 - 2026-01-01\n',
                       '## 1.2.3 - 2999-01-01\n- Future',
                       '## 1.2.3 - 2026-01-01\n- A\n## 1.2.3 - 2026-01-02\n- B']:
            with self.subTest(source=source), self.assertRaises(ValueError):
                validate.notes_for(source, '1.2.3')

    def test_publishing_requires_a_tag_before_network_access(self):
        with tempfile.TemporaryDirectory() as directory:
            old = os.getcwd()
            os.chdir(directory)
            try:
                Path('CHANGELOG.md').write_text('## 1.2.3 - 2026-01-01\n- Shipped\n')
                with patch.object(validate, 'metadata', return_value='1.2.3'), \
                     patch.object(validate, 'git', return_value='a' * 40), \
                     patch.object(validate, 'api') as api, \
                     patch.dict(os.environ, {'DRY_RUN': 'false', 'RELEASE_TAG': '', 'GITHUB_EVENT_NAME': 'push'}):
                    with self.assertRaisesRegex(ValueError, 'existing signed annotated tag'):
                        validate.main()
                    api.assert_not_called()
            finally:
                os.chdir(old)

    def test_wrong_tag_and_lightweight_tag_fail_before_network(self):
        for tag, kind, message in [('v9.9.9', 'tag', 'disagree'), ('v1.2.3', 'commit', 'annotated')]:
            with self.subTest(tag=tag), tempfile.TemporaryDirectory() as directory:
                old = os.getcwd()
                os.chdir(directory)
                try:
                    Path('CHANGELOG.md').write_text('## 1.2.3 - 2026-01-01\n- Shipped\n')
                    def git(*args):
                        return kind if args[:2] == ('cat-file', '-t') else 'a' * 40
                    with patch.object(validate, 'metadata', return_value='1.2.3'), \
                         patch.object(validate, 'git', side_effect=git), \
                         patch.object(validate, 'api') as api, \
                         patch.dict(os.environ, {'DRY_RUN': 'false', 'RELEASE_TAG': tag, 'GITHUB_EVENT_NAME': 'push'}):
                        with self.assertRaisesRegex(ValueError, message):
                            validate.main()
                        api.assert_not_called()
                finally:
                    os.chdir(old)

if __name__ == '__main__':
    unittest.main()
