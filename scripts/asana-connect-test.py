#!/usr/bin/env python3
"""Private developer trial for Asana task/parent access, not coworker authentication.
Credentials are entered locally and stored in a separate macOS Keychain item.
"""
import argparse
import base64
import getpass
import hashlib
import json
from pathlib import Path
import secrets
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request
import webbrowser

ROOT = Path(__file__).resolve().parent.parent
REDIRECT = 'urn:ietf:wg:oauth:2.0:oob'

class TrialError(Exception): pass
class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs): return None

def request(path, token=None, form=None):
    url = 'https://app.asana.com' + path
    headers = {'Accept': 'application/json'}
    if token: headers['Authorization'] = 'Bearer ' + token
    data = None
    if form is not None:
        data = urllib.parse.urlencode(form).encode()
        headers['Content-Type'] = 'application/x-www-form-urlencoded'
    try:
        req = urllib.request.Request(url, data=data, headers=headers)
        with urllib.request.build_opener(NoRedirect()).open(req, timeout=30) as response:
            return json.load(response)
    except urllib.error.HTTPError as error:
        explanations = {401: 'Sign-in expired or was rejected.', 403: 'Asana denied access. Check task permissions, app scopes and organization approval.', 404: 'Task not found or inaccessible.', 429: 'Asana is busy. Try again later.'}
        raise TrialError(explanations.get(error.code, 'Asana request failed.') + f' (HTTP {error.code})') from None
    except (urllib.error.URLError, TimeoutError, ValueError):
        raise TrialError('Could not reach Asana or read its response.') from None

def keychain(action, value=None):
    source = ROOT / 'scripts/AsanaTrialKeychain.swift'
    helper = ROOT / 'build/asana-trial-keychain'
    helper.parent.mkdir(exist_ok=True)
    if not helper.exists() or helper.stat().st_mtime < source.stat().st_mtime:
        subprocess.run(['xcrun', 'swiftc', '-parse-as-library', str(source), '-o', str(helper), '-framework', 'Security'], check=True)
    result = subprocess.run([str(helper), action], input=json.dumps(value).encode() if value is not None else None, capture_output=True)
    if result.returncode: raise TrialError('Keychain is unavailable or the trial is not connected.')
    return json.loads(result.stdout) if action == 'load' else None

def task_id(value):
    if value.isdigit(): return value
    url = urllib.parse.urlparse(value)
    if url.scheme != 'https' or url.hostname != 'app.asana.com' or url.username or url.password:
        raise TrialError('Use the task’s HTTPS app.asana.com link.')
    parts = url.path.strip('/').split('/')
    if 'task' in parts:
        candidate = parts[parts.index('task') + 1:][:1]
        if candidate and candidate[0].isdigit(): return candidate[0]
    # Classic /0/project/task or modern /1/workspace/project/project/task/task.
    numbers = [part for part in parts if part.isdigit()]
    if parts[0] == '0' and len(numbers) >= 3: return numbers[-1]
    raise TrialError('Copy the individual task link, not a project or workspace link.')

def connect(client_id):
    if not client_id.isdigit(): raise TrialError('Enter the numeric Client ID from Asana’s developer console.')
    secret = getpass.getpass('Asana Client secret (hidden; stays on this Mac): ').strip()
    if not secret: raise TrialError('No secret entered; cancelled.')
    verifier = secrets.token_urlsafe(64)
    challenge = base64.urlsafe_b64encode(hashlib.sha256(verifier.encode()).digest()).decode().rstrip('=')
    params = {'client_id': client_id, 'redirect_uri': REDIRECT, 'response_type': 'code',
              'state': secrets.token_urlsafe(32), 'code_challenge_method': 'S256',
              'code_challenge': challenge, 'scope': 'tasks:read'}
    url = 'https://app.asana.com/-/oauth_authorize?' + urllib.parse.urlencode(params)
    print('Approve read access in your browser, then copy the one-time code back here.')
    if not webbrowser.open(url): print(url)
    code = getpass.getpass('Asana one-time code (hidden): ').strip()
    if not code: raise TrialError('No code entered; cancelled.')
    result = request('/-/oauth_token', form={'grant_type': 'authorization_code', 'client_id': client_id,
        'client_secret': secret, 'redirect_uri': REDIRECT, 'code': code, 'code_verifier': verifier})
    if not result.get('refresh_token'): raise TrialError('Asana did not provide renewable authorization.')
    keychain('save', {'client_id': client_id, 'client_secret': secret, 'refresh_token': result['refresh_token']})
    print('Trial connected. Authorization saved in macOS Keychain; no task changed.')

def read_task(value):
    gid = task_id(value)
    saved = keychain('load')
    result = request('/-/oauth_token', form={'grant_type': 'refresh_token', **saved})
    if result.get('refresh_token') and result['refresh_token'] != saved['refresh_token']:
        saved['refresh_token'] = result['refresh_token']; keychain('save', saved)
    token = result['access_token']
    def fetch(identifier):
        if not str(identifier).isdigit(): raise TrialError('Asana returned an invalid task identifier.')
        return request('/api/1.0/tasks/' + str(identifier) + '?opt_fields=name,notes,parent.gid,parent.name,permalink_url', token=token)['data']
    task = fetch(gid)
    print('\nTASK: ' + task['name'])
    print(task.get('notes') or '(No description)')
    parent = task.get('parent')
    if parent:
        parent = fetch(parent['gid'])
        print('\nPARENT TASK: ' + parent['name'])
        print(parent.get('notes') or '(No parent description)')
        print('\nSuccess: task and parent retrieved. Nothing changed in Asana.')
    else: print('\nThis task has no parent. Nothing changed in Asana.')

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    c = commands.add_parser('connect'); c.add_argument('--client-id', required=True)
    commands.add_parser('task')
    commands.add_parser('disconnect')
    args = parser.parse_args()
    try:
        if args.command == 'connect': connect(args.client_id)
        elif args.command == 'task': read_task(input('Paste the individual Asana task link: ').strip())
        else:
            keychain('delete')
            print('Local trial credentials removed. Revoke Today in Asana Apps settings to revoke its authorization too.')
    except (TrialError, OSError, ValueError, KeyError, subprocess.CalledProcessError) as error:
        print(str(error) if isinstance(error, TrialError) else 'Trial failed; no credential details were printed.', file=sys.stderr)
        return 1
    except (KeyboardInterrupt, EOFError):
        print('\nCancelled.'); return 1
    return 0

if __name__ == '__main__': sys.exit(main())
