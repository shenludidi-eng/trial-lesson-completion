#!/usr/bin/env python3
"""Prepare a Pages release and immutable before/after HTML snapshots."""
import argparse
import hashlib
import html
import json
import subprocess
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def digest(data):
    return hashlib.sha256(data).hexdigest()


def write_new(path, data):
    with path.open('xb') as handle:
        handle.write(data)


def prepare(source, data_end, formal_data_end):
    current = ROOT / 'index.html'
    archive = ROOT / 'archive'
    archive.mkdir(exist_ok=True)
    before = {p: digest(p.read_bytes()) for p in archive.rglob('*.html') if p.name != 'index.html'}
    original = current.read_bytes()
    incoming = source.read_text(encoding='utf-8')
    if '__CLASS_CSV__' in incoming or 'id="class-csv"' not in incoming or 'id="formal-class-csv"' not in incoming:
        raise SystemExit('Source is not a rendered completion dashboard')
    history_url = 'https://shenludidi-eng.github.io/trial-lesson-completion/archive/'
    # Normalize inherited links before checking whether the history footer exists.
    incoming = incoming.replace(
        'https://rosannabebe.github.io/trial-lesson-completion/archive/', history_url)
    history = f'<a href="{history_url}" style="color:inherit">历史版本 / History</a>'
    if history not in incoming:
        incoming = incoming.replace('</body>', f'<footer style="padding:24px;text-align:center">{history}</footer>\n</body>')
    updated = incoming.encode('utf-8')
    stamp = datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
    old_name = f'{stamp}-before-{digest(original)[:12]}.html'
    new_name = f'{stamp}-release-{digest(updated)[:12]}.html'
    # Exclusive creation prevents even a repeated timestamp from overwriting history.
    write_new(archive / old_name, original)
    write_new(archive / new_name, updated)
    commit = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
    record = {'created_at_utc': stamp, 'previous_commit': commit,
              'previous': old_name, 'previous_sha256': digest(original),
              'release': new_name, 'release_sha256': digest(updated),
              'data_end_utc': data_end, 'formal_data_end_utc': formal_data_end}
    write_new(archive / f'{stamp}.json', (json.dumps(record, ensure_ascii=False, indent=2)+'\n').encode())
    for path, expected in before.items():
        if digest(path.read_bytes()) != expected:
            raise SystemExit(f'Historical snapshot changed: {path.name}')
    links = '\n'.join(f'<li><a href="{html.escape(p.name)}">{html.escape(p.name)}</a></li>'
                      for p in sorted(archive.glob('*.html'), reverse=True) if p.name != 'index.html')
    (archive / 'index.html').write_text('<!doctype html><html lang="zh-CN"><meta charset="utf-8">'
        '<meta name="viewport" content="width=device-width,initial-scale=1"><title>看板历史版本</title>'
        '<style>body{max-width:1000px;margin:40px auto;padding:0 24px;font:16px/1.8 system-ui}a{color:#16734a}li{overflow-wrap:anywhere}</style>'
        '<h1>看板历史版本</h1><p><a href="../">打开最新版</a></p>'
        '<p>文件名时间为 UTC；before 是发布前快照，release 是发布后快照。历史快照只新增，不覆盖。</p>'
        f'<ul>{links}</ul></html>', encoding='utf-8')
    current.write_bytes(updated)
    print(json.dumps(record, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--data-end', required=True, help='Latest available trial event in UTC')
    parser.add_argument('--formal-data-end', required=True)
    args = parser.parse_args()
    prepare(args.source, args.data_end, args.formal_data_end)
