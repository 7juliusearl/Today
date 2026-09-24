import importlib.util
import hashlib
import unittest
from unittest.mock import patch
from urllib.parse import parse_qs, urlparse

spec = importlib.util.spec_from_file_location('publisher', __file__.replace('test-dropbox-publisher.py', 'dropbox-publisher.py'))
p = importlib.util.module_from_spec(spec)
spec.loader.exec_module(p)

class PublisherTests(unittest.TestCase):
    def test_pkce_known_vector_and_offline_access(self):
        verifier = 'dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk'
        self.assertEqual(p.pkce(verifier), 'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM')
        query = parse_qs(urlparse(p.authorization_url('example', verifier)).query)
        self.assertEqual(query['token_access_type'], ['offline'])
        self.assertNotIn(verifier, p.authorization_url('example', verifier))

    def test_rejects_downgrade_and_changed_build(self):
        old = {'build': 11, 'version': '0.3.0', 'sha256': hashlib.sha256(b'zip').hexdigest()}
        self.assertTrue(p.guard_build(old, {'build': 11, 'version': '0.3.0'}, b'zip'))
        for baseline, data in [({'build': 10, 'version': '0.3.0'}, b'zip'),
                               ({'build': 11, 'version': '0.3.0'}, b'other')]:
            with self.assertRaises(p.PublisherError): p.guard_build(old, baseline, data)
        self.assertFalse(p.guard_build(old, {'build': 12, 'version': '0.3.0'}, b'new'))

    def test_credentials_never_follow_redirects_or_untrusted_hosts(self):
        self.assertIsNone(p.NoRedirect().redirect_request(None, None, 302, '', {}, 'https://example.com'))
        for url in ['http://api.dropboxapi.com/test', 'https://example.com/test']:
            with self.assertRaises(p.PublisherError): p.request(url, b'', {})

    def test_upload_preserves_revision_and_disables_renaming(self):
        import json
        with patch.object(p, 'request', return_value={}) as request:
            p.upload('secret', 'root', '/latest.json', b'feed', {'.tag': 'update', 'update': 'rev123'})
        args = json.loads(request.call_args.args[2]['Dropbox-API-Arg'])
        self.assertEqual(args['mode'], {'.tag': 'update', 'update': 'rev123'})
        self.assertFalse(args['autorename'])
        self.assertTrue(args['strict_conflict'])

    def test_hash_includes_block_boundary(self):
        data = b'a' * 4194304 + b'b'
        expected = hashlib.sha256(hashlib.sha256(data[:-1]).digest() + hashlib.sha256(b'b').digest()).hexdigest()
        self.assertEqual(p.dropbox_hash(data), expected)

if __name__ == '__main__': unittest.main()
