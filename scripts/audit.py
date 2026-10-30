"""No dependencies: production inventory and conservative engineering-history audit."""
import json
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

def git(*args):
    return subprocess.check_output(['git', *args], cwd=ROOT, encoding='utf-8')

def run():
    inventory = []
    # Production comprises the portable core and socket client. Examples, tests, interfaces and generated
    # files cannot be included merely to satisfy the participant's size threshold.
    for f in sorted(list(ROOT.glob('*.mbt')) + list((ROOT / 'net').glob('*.mbt'))):
        if f.name.endswith(('_test.mbt', '_wbtest.mbt')):
            continue
        lines = f.read_text(encoding='utf-8').splitlines()
        substantive = sum(bool(s.strip()) and not s.lstrip().startswith('//') for s in lines)
        inventory.append({'file': str(f.relative_to(ROOT)).replace('\\', '/'), 'physical': len(lines), 'nonblank_noncomment': substantive})
    commits = []
    for sha in git('rev-list', '--reverse', 'HEAD').splitlines():
        subject = git('show', '-s', '--format=%s', sha).strip()
        paths = git('diff-tree', '--root', '--no-commit-id', '--name-only', '-r', sha).splitlines()
        code = [s for s in paths if s.endswith(('.mbt', '.py'))]
        # Count only a nonempty engineering slice (production/test/example/audit
        # code), never documentation-only/format-only/release-marker commits.
        changed = git('show', '--format=', '--ignore-all-space', sha, '--', *code) if code else ''
        meaningful = bool(code) and any(
            line[:1] in ('+', '-') and not line.startswith(('+++', '---'))
            and line[1:].strip() and not line[1:].lstrip().startswith(('//', '#'))
            for line in changed.splitlines()
        )
        commits.append({'sha': sha, 'subject': subject, 'paths': paths,
                        'conservative_effective': meaningful,
                        'reason': 'retained engineering implementation/test/tool slice' if meaningful else 'excluded from conservative code-slice count'})
    result = {'production_files': inventory,
              'physical_production_lines': sum(x['physical'] for x in inventory),
              'nonblank_noncomment_production_lines': sum(x['nonblank_noncomment'] for x in inventory),
              'raw_commits': len(commits),
              'conservative_effective_commits': sum(x['conservative_effective'] for x in commits),
              'commits': commits}
    print(json.dumps(result, indent=2, ensure_ascii=False))
    assert result['nonblank_noncomment_production_lines'] >= 1500, 'production floor not met'
    assert result['conservative_effective_commits'] >= 20, 'history floor not met'

if __name__ == '__main__':
    run()
