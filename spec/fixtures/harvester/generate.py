#!/usr/bin/env python3
"""Runs the harvester's entity mapping over input.json in real Bento and writes expected.json.

The mapping is the step of seeds/decidim/pipeline.yaml after the comment "Each record as its entity",
so mapper_harvester_spec.rb proves pull and push agree. Run after that step changes:
python3 spec/fixtures/harvester/generate.py <joinedcontext-deployment clone>
"""
import json
import pathlib
import subprocess
import sys
import textwrap

BENTO = "ghcr.io/warpstreamlabs/bento:1.22.0@sha256:ef674bebae45793c982c350d8f37c2c7661133c1dc65a5517fb977b36dc09841"
HERE = pathlib.Path(__file__).parent

lines = (pathlib.Path(sys.argv[1]) / "seeds/decidim/pipeline.yaml").read_text().split("\n")
start = next(i for i, line in enumerate(lines) if "Each record as its entity." in line) + 2
end = next(i for i, line in enumerate(lines) if i > start and "root = if $hidden" in line) + 1
mapping = textwrap.dedent("\n".join(lines[start:end]))

given = json.loads((HERE / "input.json").read_text())
expected = {}
for name, record in given["records"].items():
    message = {"cfg": given["cfg"], "space": given["space"], "component": given["component"], "record": record}
    if name == "process":
        message["component"] = None
    out = subprocess.run(
        ["docker", "run", "--rm", "-i", "-e", "JC_SPACE=participacia", BENTO, "blobl", mapping],
        input=json.dumps(message), capture_output=True, text=True, check=True,
    )
    expected[name] = json.loads(out.stdout)
(HERE / "expected.json").write_text(json.dumps(expected, ensure_ascii=False, indent=2, sort_keys=True) + "\n")
