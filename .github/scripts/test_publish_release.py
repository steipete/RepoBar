#!/usr/bin/env python3
import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('publisher', Path(__file__).with_name('publish-release.py'))
publisher = importlib.util.module_from_spec(spec)
spec.loader.exec_module(publisher)

class PublicationTests(unittest.TestCase):
    def run_candidate(self, *, dry=False, existing=None, corrupt=False):
        with tempfile.TemporaryDirectory() as directory:
            old = os.getcwd()
            os.chdir(directory)
            try:
                release = Path('release')
                release.mkdir()
                metadata = {'dry_run':dry,'commit':'a'*40,'tag':'v1.2.3','tag_object':'b'*40,'build':2}
                (release/'release.json').write_text(json.dumps(metadata))
                (release/'RELEASE-NOTES.md').write_text('## 1.2.3 - 2026-01-01\n\n- Note\n')
                (release/'example.tar.gz').write_bytes(b'source archive bytes')
                (release/'SHA256SUMS').write_text(''.join(
                    hashlib.sha256(p.read_bytes()).hexdigest()+'  '+p.name+'\n'
                    for p in sorted(release.iterdir())))
                names=sorted(p.name for p in release.iterdir())
                assets=[{'name':name,'url':'https://api.github.com/assets/'+name} for name in names]
                def api(path, **kwargs):
                    if kwargs.get('method')=='PATCH':
                        return {'draft':False}
                    if kwargs.get('data') is not None:
                        return {'id':42,'upload_url':'https://uploads.github.com/assets{?name}'}
                    return {'id':42,'draft':api.call_count_before_publish,'assets':assets,
                            'body':(release/'RELEASE-NOTES.md').read_text()}
                api.call_count_before_publish = True
                calls=[]
                def api_call(path, **kwargs):
                    calls.append((path, kwargs))
                    result=api(path, **kwargs)
                    if kwargs.get('method')=='PATCH':
                        api.call_count_before_publish=False
                    return result
                class Opener:
                    def open(self, request, timeout):
                        name=request.full_url.rsplit('/',1)[1]
                        return io.BytesIO(b'corrupt' if corrupt else (release/name).read_bytes())
                def upload(request, timeout):
                    return io.BytesIO(json.dumps({'state':'uploaded','size':len(request.data)}).encode())
                with patch.dict(os.environ, {'RELEASE_COMMIT':'a'*40, 'GITHUB_REPOSITORY':'owner/repo', 'GH_TOKEN':'test-placeholder','RUNNER_TEMP':directory}), \
                     patch.object(publisher.subprocess,'check_output',return_value='b'*40+'\trefs/tags/v1.2.3\n'), \
                     patch.object(publisher.validator,'release_for_tag',return_value=existing), \
                     patch.object(publisher.validator,'api',side_effect=api_call), \
                     patch.object(publisher.urllib.request,'urlopen',side_effect=upload), \
                     patch.object(publisher.urllib.request,'build_opener',return_value=Opener()):
                    with patch.object(publisher.validator,'check_appcast_build',create=True):
                        error=None
                        try:
                            publisher.main()
                        except ValueError as caught:
                            error=str(caught)
                return error,calls
            finally:
                os.chdir(old)

    def test_dry_run_never_creates_a_release(self):
        error,calls=self.run_candidate(dry=True)
        self.assertIn('not authorized',error)
        self.assertEqual(calls,[])

    def test_existing_draft_never_creates_a_release(self):
        error,calls=self.run_candidate(existing={'draft':True})
        self.assertIn('already exists',error)
        self.assertEqual(calls,[])

    def test_corrupt_download_never_publishes(self):
        error,calls=self.run_candidate(corrupt=True)
        self.assertIn('differs',error)
        self.assertFalse(any(kwargs.get('method')=='PATCH' for _,kwargs in calls))

    def test_promotion_uses_the_created_release_id(self):
        error,calls=self.run_candidate()
        self.assertIsNone(error)
        promotion=[path for path,kwargs in calls if kwargs.get('method')=='PATCH']
        self.assertEqual(promotion,['repos/owner/repo/releases/42'])
        self.assertFalse(any('/tags/' in path for path,_ in calls))

if __name__ == '__main__':
    unittest.main()
