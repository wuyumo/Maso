import hashlib
import importlib.util
import plistlib
import tempfile
import unittest
import urllib.error
from pathlib import Path
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('publisher', Path(__file__).parents[1] / 'publish_remote_exercise_catalog.py')
publisher = importlib.util.module_from_spec(spec)
spec.loader.exec_module(publisher)


class Response:
    status = 206

    def __init__(self, data, content_range='bytes 0-3/4'):
        self.data = data
        self.headers = {'Content-Range': content_range}

    def read(self):
        return self.data

    def __enter__(self):
        return self

    def __exit__(self, *args):
        return False


class DeliveryVerificationTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        info = self.root / 'build/DerivedData-Device/Build/Products/Debug-iphoneos/Maso.app/Info.plist'
        info.parent.mkdir(parents=True)
        info.write_bytes(plistlib.dumps({'MasoAIProxyURL': 'https://primary.example',
                                        'MasoAIProxyFallbackURL': 'https://fallback.example',
                                        'MasoClientToken': 'test-only'}))
        self.candidate = {'assets': [{'exerciseId': 'example', 'sha256': hashlib.sha256(b'GIF!').hexdigest(),
                                     'bytes': 4, 'videoPath': '/media'}]}

    def verify(self):
        with patch.object(publisher, 'ROOT', self.root):
            publisher.verify_changed_assets({'assets': []}, self.candidate)

    def test_primary_404_uses_fallback(self):
        error = urllib.error.HTTPError('https://primary.example/media', 404, 'missing', {}, None)
        with patch.object(publisher.urllib.request, 'urlopen', side_effect=[error, Response(b'GIF!')]) as fetch:
            self.verify()
        self.assertEqual([x.args[0].full_url for x in fetch.call_args_list],
                         ['https://primary.example/media', 'https://fallback.example/media'])

    def test_bad_range_uses_fallback(self):
        with patch.object(publisher.urllib.request, 'urlopen', side_effect=[Response(b'GIF!', 'bytes 1-4/5'), Response(b'GIF!')]):
            self.verify()

    def test_no_valid_base_fails(self):
        with patch.object(publisher.urllib.request, 'urlopen', side_effect=urllib.error.URLError('unavailable')):
            with self.assertRaisesRegex(RuntimeError, 'range unavailable'):
                self.verify()

    def test_wrong_bytes_still_fail_sha(self):
        with patch.object(publisher.urllib.request, 'urlopen', return_value=Response(b'BAD!')):
            with self.assertRaisesRegex(RuntimeError, 'hash mismatch'):
                self.verify()


if __name__ == '__main__':
    unittest.main()
