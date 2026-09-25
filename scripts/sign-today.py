#!/usr/bin/env python3
"""Sign Today consistently; notarize portable packages before they are zipped."""
import argparse
import json
import os
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parent.parent


def config():
    path = ROOT / '.today-signing.json'
    saved = json.loads(path.read_text()) if path.exists() else {}
    return (os.environ.get('TODAY_SIGNING_IDENTITY', saved.get('identity', '-')),
            os.environ.get('TODAY_NOTARY_PROFILE', saved.get('notaryProfile', '')))


def run(*args, **kwargs):
    return subprocess.run(args, check=True, **kwargs)


def preflight():
    identity, profile = config()
    if identity == '-' or not profile:
        raise RuntimeError('Coworker releases require a Developer ID signing identity and a Keychain notarization profile. See scripts/RELEASING.md.')
    run('xcrun', 'notarytool', 'history', '--keychain-profile', profile, '--output-format', 'json', stdout=subprocess.DEVNULL, timeout=60)


def sign(app, release=False):
    identity, _ = config()
    if release and identity == '-':
        raise RuntimeError('Refusing to package an ad hoc signed coworker app.')
    flags = ['--force', '--sign', identity]
    if identity != '-':
        flags += ['--options', 'runtime', '--timestamp']
    run('codesign', *flags, str(app / 'Contents/MacOS/TodayUpdateHelper'))
    run('codesign', *flags, '--entitlements', str(ROOT / 'scripts/Today.entitlements'), str(app))
    run('codesign', '--verify', '--deep', '--strict', str(app))
    details = run('codesign', '-dvv', str(app), capture_output=True, text=True).stderr
    if release and 'Authority=Developer ID Application:' not in details:
        raise RuntimeError('The release must use a Developer ID Application certificate.')
    if identity == '-':
        print('Local ad hoc build: Keychain and privacy approvals may recur after rebuilds.')
    else:
        print('Signed with configured stable identity.')


def notarize(app):
    _, profile = config()
    if not profile:
        raise RuntimeError('Configure a Keychain notarization profile first.')
    archive = app.parent / 'Today-notarization.zip'
    run('ditto', '-c', '-k', '--keepParent', str(app), str(archive))
    result = run('xcrun', 'notarytool', 'submit', str(archive), '--keychain-profile', profile,
                 '--wait', '--output-format', 'json', capture_output=True, text=True)
    report = json.loads(result.stdout)
    (app.parent / 'notarization-result.json').write_text(json.dumps(report, indent=2) + '\n')
    if report.get('status') != 'Accepted':
        raise RuntimeError('Apple did not accept the app. See notarization-result.json; no release ZIP was created.')
    run('xcrun', 'stapler', 'staple', str(app))
    run('xcrun', 'stapler', 'validate', str(app))
    run('spctl', '--assess', '--type', 'execute', '--verbose', str(app))
    archive.unlink()
    print('Apple notarization accepted; ticket stapled and Gatekeeper verified.')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['sign', 'release-sign', 'preflight', 'notarize'])
    parser.add_argument('app', nargs='?')
    args = parser.parse_args()
    try:
        if args.action == 'preflight':
            preflight()
        else:
            if not args.app:
                parser.error('app is required')
            app = Path(args.app).resolve()
            if args.action == 'notarize': notarize(app)
            else: sign(app, release=args.action == 'release-sign')
    except (RuntimeError, subprocess.SubprocessError, ValueError) as error:
        parser.exit(1, str(error) + '\n')
