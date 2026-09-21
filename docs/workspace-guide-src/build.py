#!/usr/bin/env python3
"""Build/check the self-contained workspace guide using only the Python standard library.

One EyrAgents-owned output combines host and portable AI-client references.
No sibling checkout, network or installed application is needed.
"""

import argparse
import json
import re
from pathlib import Path
from urllib.parse import urlsplit

ROOT = Path(__file__).resolve().parent


def load_reference():
    """Compose the two evidence owners without replacing their review baselines."""
    data = json.loads((ROOT / 'host-reference.json').read_text(encoding='utf-8'))
    clients = json.loads((ROOT / 'client-reference.json').read_text(encoding='utf-8'))
    if set(clients['profiles']) != {'eyragents'} or clients['recipes']:
        raise ValueError('client reference must be portable; host reference owns hdw recipes')
    if any(item['hosts'] != ['eyragents'] for item in clients['items']):
        raise ValueError('client actions must use the portable EyrAgents scope')
    for field in ('apps', 'sources'):
        overlap = data[field].keys() & clients[field].keys()
        if overlap:
            raise ValueError(f'duplicate {field}: {sorted(overlap)}')
        data[field].update(clients[field])
    data['items'].extend(dict(item, hosts=list(data['profiles'])) for item in clients['items'])
    data['workflows'].extend(clients['workflows'])
    data['checks'].extend(clients['checks'])
    data['client_notes'] = clients['profiles']['eyragents']['notes']
    active_ids = {item['id'] for item in data['items']}
    data['retired_ids'] = sorted(set(data.get('retired_ids', [])) - active_ids)
    data['title'] = 'EyrAgents Workspace Guide'
    data['reviewed'] = f'host reference {data["reviewed"]}; AI reference {clients["reviewed"]}'
    data['scope'] = ('One offline development-workspace reference: hdw, Herdr, Claude Code, '
                     'Codex, OpenCode, Hermes Agent, Neovim, shell and both host profiles. '
                     'Each source retains its own evidence baseline; installed help and '
                     'configuration determine actual behavior.')
    return data


def validate(data):
    """Reject broken reference links, selectors and unreachable profile entries."""
    profiles = set(data['profiles'])
    if profiles != {'eyrarchy', 'eyrwsl'}:
        raise ValueError('expected the EyrArcHy and EyrWSL profiles')
    ids = set()
    for item in data['items']:
        if not re.fullmatch(r'[a-z0-9-]+', item['id']) or item['id'] in ids:
            raise ValueError(f'invalid/duplicate action ID: {item["id"]}')
        ids.add(item['id'])
        if item['app'] not in data['apps']:
            raise ValueError(f'unknown app: {item["app"]}')
        if not item['hosts'] or not set(item['hosts']) <= profiles:
            raise ValueError(f'invalid host scope: {item["id"]}')
        if item['kind'] not in ('keys', 'command'):
            raise ValueError(f'invalid action kind: {item["id"]}')
        if not item['keys'] or not all(isinstance(key, str) and key for key in item['keys']):
            raise ValueError(f'missing controls: {item["id"]}')
        for field in ('title', 'category', 'mode', 'detail'):
            if not isinstance(item[field], str) or not item[field]:
                raise ValueError(f'missing {field}: {item["id"]}')
        for source in [item['source'], *item['extra']]:
            if source not in data['sources']:
                raise ValueError(f'unknown source {source}: {item["id"]}')
    for workflow in data['workflows']:
        if not all(source in data['sources'] for source in workflow['sources']):
            raise ValueError(f'unknown workflow source: {workflow["title"]}')
    for source in data['sources'].values():
        for profile in profiles:
            url = urlsplit(source['url'].replace('{repo}', profile))
            if url.scheme != 'https' or not url.netloc:
                raise ValueError(f'invalid source URL: {source["url"]}')
    recipes = data['recipes']
    if [recipe['selector'] for recipe in recipes] != ['cc', 'cx', 'oc', 'ha']:
        raise ValueError('launcher must cover all four hdw selectors')
    for recipe in recipes:
        if recipe['command'] != 'hdw ' + recipe['selector'] or recipe['resume'] != recipe['command'] + ' -c':
            raise ValueError(f'invalid launcher recipe: {recipe["selector"]}')
        if recipe['source'] not in data['sources']:
            raise ValueError(f'unknown launcher source: {recipe["selector"]}')
    for profile in profiles:
        if {item['app'] for item in data['items'] if profile in item['hosts']} != set(data['apps']):
            raise ValueError(f'missing application coverage: {profile}')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true', help='compare without writing')
    args = parser.parse_args()
    data = load_reference()
    validate(data)
    template = (ROOT / 'template.html').read_text(encoding='utf-8')
    for token in ('__REFERENCE__',):
        if template.count(token) != 1:
            raise ValueError(f'expected exactly one {token} placeholder')
    payload = json.dumps(data, ensure_ascii=False, indent=2).replace('<', '\\u003c')
    output = template.replace('__REFERENCE__', payload)
    if '\u2014' in output:
        raise ValueError('use periods, commas or semicolons instead of em dashes')
    target = ROOT.parent / 'workspace-guide.html'
    if args.check:
        if not target.exists() or target.read_text(encoding='utf-8') != output:
            raise SystemExit('FAIL: docs/workspace-guide.html is stale; run make workspace-guide')
        print(f'ok:   offline workspace guide is current; {len(data["items"])} reference actions, both hosts')
    else:
        target.write_text(output, encoding='utf-8')
        print(f'Built {target} (both hosts)')


if __name__ == '__main__':
    main()
