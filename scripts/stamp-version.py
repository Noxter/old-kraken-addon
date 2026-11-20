"""Stamp a packaged TOC with the commit used to build it."""
import re
import sys
from pathlib import Path


def stamp(path, commit):
    if not re.fullmatch(r'[0-9a-fA-F]{40}', commit):
        raise ValueError('expected a full Git commit hash')
    data = path.read_bytes()
    pattern = rb'(?m)^(## Version:[ \t]*)([^\r\n]+)'
    matches = list(re.finditer(pattern, data))
    if len(matches) != 1:
        raise ValueError('expected exactly one TOC version')
    version = matches[0].group(2).split(b'+', 1)[0]
    if not re.fullmatch(rb'\d+\.\d+\.\d+(?:-[a-z]+(?:\.\d+)?)?', version):
        raise ValueError('invalid TOC version')
    stamped = matches[0].group(1) + version + b'+g' + commit[:12].lower().encode('ascii')
    if len(version) + 14 > 48:
        raise ValueError('stamped version exceeds the presence protocol limit')
    path.write_bytes(data[:matches[0].start()] + stamped + data[matches[0].end():])


if __name__ == '__main__':
    if len(sys.argv) != 3:
        raise SystemExit('usage: stamp-version.py TOC_PATH FULL_COMMIT_HASH')
    stamp(Path(sys.argv[1]), sys.argv[2])
