import hashlib
import sys
import unittest
from pathlib import Path
import xml.etree.ElementTree as ET

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/"tools"))
import build

class ArtifactTests(unittest.TestCase):
    def test_original_pack_unchanged(self):
        for line in (ROOT/"MANIFEST_SHA256.txt").read_text().splitlines():
            digest,name=line.split(maxsplit=1)
            self.assertEqual(hashlib.sha256((ROOT/name).read_bytes()).hexdigest(),digest,name)

    def test_deterministic_build(self):
        build.build()
        first=(ROOT/"build/SWARMFALL_P1A.rbxlx").read_bytes()
        build.build()
        self.assertEqual(first,(ROOT/"build/SWARMFALL_P1A.rbxlx").read_bytes())

    def test_embedded_sources_exact(self):
        tree=ET.parse(ROOT/"build/SWARMFALL_P1A.rbxlx")
        embedded={e.find("Properties/string[@name='Name']").text:e.find("Properties/ProtectedString[@name='Source']").text or ""
                  for e in tree.findall(".//Item") if e.attrib["class"] in ("Script","LocalScript","ModuleScript")}
        files=list((ROOT/"src").rglob("*.luau"))
        self.assertEqual(len(embedded),len(files))
        for file in files:
            name=file.name.replace(".server.luau","").replace(".client.luau","").replace(".luau","")
            self.assertEqual(embedded[name],file.read_text(encoding="utf-8"),str(file))

if __name__=="__main__": unittest.main(verbosity=2)
