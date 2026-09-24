#!/usr/bin/env python3
"""One-time PKCE authorization for the local Today release publisher.
Never prints tokens or stores them in the repository. No third-party dependencies.
"""
import argparse
import base64
import getpass
import hashlib
import json
from pathlib import Path
import secrets
import re
import time
import fcntl
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request
import webbrowser

ROOT = Path(__file__).resolve().parent.parent
KEYCHAIN = ROOT / 'build/dropbox-keychain'
SCOPES = ['account_info.read', 'files.metadata.read', 'files.content.read',
          'files.content.write', 'sharing.read', 'sharing.write']
DEFAULT_FOLDER = '/Julius Espiritu/Today Dashboard'

class PublisherError(Exception):
    pass

class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None  # Never forward credentials to redirects.

def request(url, data, headers):
    parsed = urllib.parse.urlparse(url)
    if parsed.scheme != 'https' or parsed.hostname not in ('api.dropboxapi.com', 'content.dropboxapi.com'):
        raise PublisherError('Unexpected Dropbox API host.')
    try:
        req = urllib.request.Request(url, data=data, headers=headers, method='POST')
        with urllib.request.build_opener(NoRedirect()).open(req, timeout=40) as response:
            return json.load(response)
    except urllib.error.HTTPError as error:
        # API responses can echo credentials. Report only the HTTP status.
        raise PublisherError(f'Dropbox request failed (HTTP {error.code}). Check app permissions or reconnect.') from None
    except (urllib.error.URLError, TimeoutError, ValueError):
        raise PublisherError('Dropbox could not be reached or returned an invalid response.') from None

def token_request(values):
    return request('https://api.dropboxapi.com/oauth2/token',
                   urllib.parse.urlencode(values).encode(),
                   {'Content-Type': 'application/x-www-form-urlencoded'})

def api(token, route, payload=None, root=None):
    headers = {'Authorization': 'Bearer ' + token, 'Content-Type': 'application/json'}
    if root:
        headers['Dropbox-API-Path-Root'] = json.dumps({'.tag': 'root', 'root': root})
    return request('https://api.dropboxapi.com/2/' + route,
                   json.dumps(payload).encode(), headers)

def keychain(action, value=None):
    source = ROOT / 'scripts/DropboxKeychain.swift'
    if not KEYCHAIN.exists() or KEYCHAIN.stat().st_mtime < source.stat().st_mtime:
        KEYCHAIN.parent.mkdir(exist_ok=True)
        subprocess.run(['xcrun', 'swiftc', '-parse-as-library', str(source), '-o', str(KEYCHAIN), '-framework', 'Security'], check=True)
    result = subprocess.run([str(KEYCHAIN), action], input=json.dumps(value).encode() if value is not None else None,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if result.returncode:
        raise PublisherError('Publisher credentials are unavailable. Unlock Keychain or run the connect command.')
    return json.loads(result.stdout) if action == 'load' else None

def pkce(verifier):
    return base64.urlsafe_b64encode(hashlib.sha256(verifier.encode()).digest()).decode().rstrip('=')

def authorization_url(app_key, verifier):
    return 'https://www.dropbox.com/oauth2/authorize?' + urllib.parse.urlencode({
        'client_id': app_key, 'response_type': 'code', 'token_access_type': 'offline',
        'code_challenge_method': 'S256', 'code_challenge': pkce(verifier),
        'scope': ' '.join(SCOPES)})

def connect(app_key):
    app_key = (app_key or input('Dropbox app key (not the secret): ')).strip()
    if not app_key.isalnum():
        raise PublisherError('Enter the app key from your Dropbox app settings.')
    verifier = secrets.token_urlsafe(64)
    url = authorization_url(app_key, verifier)
    print('Approve Today publishing in the browser. Dropbox will give you a one-time code.')
    if not webbrowser.open(url):
        print('Open this authorization URL in your browser:\n' + url)
    code = getpass.getpass('Paste the one-time code here (hidden): ').strip()
    if not code:
        raise PublisherError('Authorization cancelled; nothing saved.')
    result = token_request({'grant_type': 'authorization_code', 'client_id': app_key,
                            'code': code, 'code_verifier': verifier})
    if not set(SCOPES).issubset(set(result.get('scope', '').split())):
        raise PublisherError('Required permissions were not granted. Enable the listed scopes and reconnect.')
    if not result.get('refresh_token') or not result.get('access_token'):
        raise PublisherError('Dropbox did not grant persistent access. Reconnect with offline access enabled.')
    account = api(result['access_token'], 'users/get_current_account')
    keychain('save', {'app_key': app_key, 'refresh_token': result['refresh_token'],
                      'account_id': account['account_id'], 'scopes': result['scope']})
    print('Connected. Renewable publisher authorization is stored in macOS Keychain.')
    print('No release files have been uploaded or changed.')

def access_token():
    saved = keychain('load')
    result = token_request({'grant_type': 'refresh_token', 'refresh_token': saved['refresh_token'],
                            'client_id': saved['app_key']})
    token = result.get('access_token')
    if not token:
        raise PublisherError('Dropbox did not return access. Reconnect the publisher.')
    return token, saved

def status(folder):
    token, saved = access_token()
    account = api(token, 'users/get_current_account')
    if account['account_id'] != saved['account_id']:
        raise PublisherError('Publisher account changed. Reconnect before publishing.')
    root = account.get('root_info', {}).get('root_namespace_id')
    metadata = api(token, 'files/get_metadata', {'path': folder}, root=root)
    if metadata.get('.tag') != 'folder':
        raise PublisherError('The configured release destination is not a folder.')
    feed = api(token, 'files/get_metadata', {'path': folder.rstrip('/') + '/latest.json'}, root=root)
    if feed.get('.tag') != 'file':
        raise PublisherError('Existing latest.json was not found. Nothing changed.')
    print('Connected; token renewal and release-folder access verified.')
    print('Release folder: ' + metadata.get('path_display', folder))
    print('Existing latest.json found. Upload/sharing scopes authorized; no files changed.')

def dropbox_hash(data):
    chunks = [hashlib.sha256(data[i:i + 4194304]).digest() for i in range(0, len(data), 4194304)]
    return hashlib.sha256(b''.join(chunks)).hexdigest()

def upload(token, root, path, data, mode):
    headers = {'Authorization': 'Bearer ' + token,
               'Content-Type': 'application/octet-stream',
               'Dropbox-API-Path-Root': json.dumps({'.tag': 'root', 'root': root}),
               'Dropbox-API-Arg': json.dumps({'path': path, 'mode': mode,
                                             'autorename': False, 'strict_conflict': True})}
    return request('https://content.dropboxapi.com/2/files/upload', data, headers)

def public_download(url, limit):
    parsed = urllib.parse.urlparse(url)
    if parsed.scheme != 'https' or parsed.hostname not in ('www.dropbox.com', 'dropbox.com'):
        raise PublisherError('Expected a public HTTPS Dropbox file link.')
    query = [(k, v) for k, v in urllib.parse.parse_qsl(parsed.query) if k not in ('dl', 'raw')]
    url = urllib.parse.urlunparse(parsed._replace(query=urllib.parse.urlencode(query + [('dl', '1')])))
    # Anonymous, separate from the authenticated API client. No Authorization header.
    try:
        with urllib.request.urlopen(url, timeout=90) as response:
            data = response.read(limit + 1)
        if len(data) > limit:
            raise PublisherError('Public download exceeded the expected size.')
        return data
    except (urllib.error.URLError, TimeoutError):
        raise PublisherError('Could not verify the anonymous download. Feed publication was not confirmed.') from None

def release_tool(*args):
    tool = ROOT / 'build/release-tool'
    sources = [ROOT / 'prototype/calendar/UpdateSupport.swift', ROOT / 'scripts/ReleaseTool.swift']
    if not tool.exists() or any(s.stat().st_mtime > tool.stat().st_mtime for s in sources):
        subprocess.run(['xcrun', 'swiftc', '-parse-as-library', *map(str, sources), '-o', str(tool)], check=True, cwd=ROOT)
    result = subprocess.run([str(tool), *map(str, args)], cwd=ROOT, capture_output=True)
    if result.returncode:
        raise PublisherError('Release signing or signature verification failed. Nothing further published.')
    return result.stdout

def guard_build(current, baseline, archive):
    if current['build'] > baseline['build']:
        raise PublisherError('A newer build is already published; refusing to downgrade.')
    if current['build'] == baseline['build']:
        if current['sha256'] != hashlib.sha256(archive).hexdigest() or current['version'] != baseline['version']:
            raise PublisherError('This build number is already used for a different release. Increase the build number.')
        return True
    return False

def publish(archive_path, notes_path, folder):
    import tempfile
    import zipfile
    archive_path, notes_path = Path(archive_path).resolve(), Path(notes_path).resolve()
    if archive_path.stat().st_size > 150 * 1024 * 1024:
        raise PublisherError('Archive exceeds the updater size limit.')
    archive = archive_path.read_bytes()
    if not notes_path.read_text().strip():
        raise PublisherError('Release notes are required.')
    with zipfile.ZipFile(archive_path) as z:
        baseline = json.loads(z.read('Today/.today-release.json'))
        html = z.read('Today/dashboard/index.html')
        if b'data-edition="coworker"' not in html:
            raise PublisherError('Publish only a clean coworker package.')
        import plistlib
        info = plistlib.loads(z.read('Today/Today.app/Contents/Info.plist'))
        if not info.get('TodayPortable') or 'TodayPersonalDataDirectory' in info:
            raise PublisherError('The package contains a development app.')
    if not re.fullmatch(r'[0-9]+(?:\.[0-9]+)*', baseline['version']) or type(baseline['build']) is not int or baseline['build'] < 1:
        raise PublisherError('Invalid archive version/build.')
    token, saved = access_token()
    account = api(token, 'users/get_current_account')
    if account['account_id'] != saved['account_id']:
        raise PublisherError('Dropbox account changed. Reconnect before publishing.')
    root = account['root_info']['root_namespace_id']
    config = json.loads((ROOT / 'release.json').read_text())
    feed_path = folder.rstrip('/') + '/latest.json'
    feed = api(token, 'files/get_metadata', {'path': feed_path}, root)
    original = public_download(config['feedURL'], 65536)
    if dropbox_hash(original) != feed['content_hash']:
        raise PublisherError('The permanent feed link does not match the destination file. Nothing published.')
    with tempfile.TemporaryDirectory(prefix='today-publish-') as temp:
        old = Path(temp) / 'previous-latest.json'
        old.write_bytes(original)
        current = json.loads(release_tool('verify', old))
        if guard_build(current, baseline, archive):
            if public_download(current['url'], len(archive)) != archive:
                raise PublisherError('Published archive failed verification.')
            print(f"Build {baseline['build']} is already live; its signature and public download verified.")
            return
        name = f"Today-{baseline['version']}-build{baseline['build']}.zip"
        destination = folder.rstrip('/') + '/' + name
        listing = api(token, 'files/list_folder', {'path': folder}, root)
        entries = listing['entries']
        while listing.get('has_more'):
            listing = api(token, 'files/list_folder/continue', {'cursor': listing['cursor']}, root)
            entries += listing['entries']
        existing = next((e for e in entries if e['name'].lower() == name.lower()), None)
        if existing:
            if existing.get('content_hash') != dropbox_hash(archive):
                raise PublisherError('An archive with this build name already exists with different contents.')
            print('Matching archive already uploaded; resuming publication.')
        else:
            print('Uploading ' + name, flush=True)
            uploaded = upload(token, root, destination, archive, 'add')
            if uploaded['content_hash'] != dropbox_hash(archive):
                raise PublisherError('Uploaded archive hash did not match. Feed unchanged.')
        links = api(token, 'sharing/list_shared_links', {'path': destination, 'direct_only': True}, root)['links']
        link = next((x for x in links if x.get('link_permissions', {}).get('resolved_visibility', {}).get('.tag') == 'public'), None)
        if not link:
            link = api(token, 'sharing/create_shared_link_with_settings',
                       {'path': destination, 'settings': {'requested_visibility': 'public'}}, root)
        url = link['url']
        if public_download(url, len(archive)) != archive:
            raise PublisherError('Anonymous archive download failed verification. Feed unchanged.')
        # Sign a staging copy; never rewrite the immutable package.
        staged = Path(temp) / name
        staged.write_bytes(archive)
        release_tool('manifest', staged, url, notes_path)
        manifest = staged.parent / 'latest.json'
        release_tool('verify', manifest)
        payload = manifest.read_bytes()
        backup = archive_path.parent / ('previous-feed-build' + str(current['build']) + '.json')
        if not backup.exists(): backup.write_bytes(original)
        print('Verified public download. Updating the existing signed feed.', flush=True)
        updated = upload(token, root, feed_path, payload, {'.tag': 'update', 'update': feed['rev']})
        if updated['id'] != feed['id'] or updated['content_hash'] != dropbox_hash(payload):
            raise PublisherError('Feed update returned unexpected metadata. Verify the live feed before retrying.')
        (archive_path.parent / 'latest.json').write_bytes(payload)
        for attempt in range(4):
            if public_download(config['feedURL'], 65536) == payload:
                print(f"Published Today {baseline['version']} build {baseline['build']}. Signed feed and anonymous ZIP verified.")
                return
            time.sleep(3)
        raise PublisherError('Feed was uploaded but the public link has not refreshed yet. Run publish again to verify.')

def ship(notes, folder):
    import shutil
    config = json.loads((ROOT / 'release.json').read_text())
    target = ROOT / 'build/releases' / f"Today-{config['version']}-build{config['build']}"
    if target.exists():
        raise PublisherError('Release output already exists. Use publish to resume it, or increment the build for a new release.')
    notes = Path(notes).resolve()
    if not notes.read_text().strip(): raise PublisherError('Release notes are required.')
    result = subprocess.run([str(ROOT / 'scripts/package-today.sh')], cwd=ROOT, stdout=subprocess.PIPE, text=True, check=True)
    print(result.stdout)
    match = re.search(r'^Share this archive: (.+)$', result.stdout, re.M)
    if not match: raise PublisherError('Packager did not return an archive.')
    target.mkdir(parents=True)
    archive = target / (target.name + '.zip')
    shutil.copyfile(match[1], archive)
    shutil.copyfile(notes, target / 'release-notes.txt')
    publish(archive, target / 'release-notes.txt', folder)

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    auth = commands.add_parser('connect')
    auth.add_argument('--app-key')
    check = commands.add_parser('status')
    check.add_argument('--folder', default=DEFAULT_FOLDER)
    commands.add_parser('disconnect')
    pub = commands.add_parser('publish', help='Upload and announce an existing clean release; safe to retry')
    pub.add_argument('archive')
    pub.add_argument('notes')
    pub.add_argument('--folder', default=DEFAULT_FOLDER)
    shipping = commands.add_parser('ship', help='Build, upload, sign and announce a new release')
    shipping.add_argument('notes')
    shipping.add_argument('--folder', default=DEFAULT_FOLDER)
    args = parser.parse_args()
    try:
        if args.command == 'connect': connect(args.app_key)
        elif args.command == 'status': status(args.folder)
        elif args.command in ('publish', 'ship'):
            (ROOT / 'build').mkdir(exist_ok=True)
            with (ROOT / 'build/publisher.lock').open('w') as lock:
                try: fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
                except BlockingIOError: raise PublisherError('Another publisher is already running.')
                if args.command == 'publish': publish(args.archive, args.notes, args.folder)
                else: ship(args.notes, args.folder)
        else:
            keychain('delete')
            print('Local publisher credential removed. Revoke app access in Dropbox Connected apps to invalidate it there too.')
    except (PublisherError, subprocess.CalledProcessError, KeyError, OSError, ValueError) as error:
        print(str(error) if isinstance(error, PublisherError) else 'Publisher setup could not complete; no credential details were printed.', file=sys.stderr)
        return 1
    except (KeyboardInterrupt, EOFError):
        print('\nCancelled; authorization did not complete.', file=sys.stderr)
        return 1
    return 0

if __name__ == '__main__':
    sys.exit(main())
