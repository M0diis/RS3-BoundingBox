"""Run BoundingBox's offline Lua checks. Requires lupa (see README.md)."""
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / ".tools" / "python"))
sys.path.append(str(ROOT.parent / ".tools" / "python"))
try:
    from lupa.lua54 import LuaRuntime
except ImportError:
    raise SystemExit("Install the test runtime: python -m pip install --target .tools/python lupa")

lua = LuaRuntime(unpack_returned_tuples=True)
for source in [ROOT / "main.lua", *sorted((ROOT / "src").rglob("*.lua"))]:
    lua.compile(source.read_text(encoding="utf-8"), name=str(source.relative_to(ROOT)))
manifest = json.loads((ROOT / "plugin.json").read_text(encoding="utf-8"))
assert manifest["requiredDependencies"]["prettyui"] == 6398181
assert manifest["requiredPermissions"] == []
assert manifest["hasSettingsIcon"] and manifest["hasRibbonIcon"]
assert "@" in manifest["contactEmailAddress"]
lua.globals().PLUGIN_ROOT = ROOT.as_posix()
lua.execute((ROOT / "tests" / "boundingbox_test.lua").read_text(encoding="utf-8"))
print("Lua syntax and plugin manifest: PASS")
