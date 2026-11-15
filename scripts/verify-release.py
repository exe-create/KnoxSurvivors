"""Verify the downloadable ZIP against the source payload and built Java module."""

import hashlib
import io
import json
from pathlib import Path, PurePosixPath
import re
import sys
import zipfile


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def verify(archive):
    root = Path(__file__).resolve().parent.parent
    version = re.search(r'^version = "([^"]+)"',
                        (root / "build.gradle.kts").read_text(), re.M).group(1)
    prefix = "mods/KnoxSurvivors/"
    expected = {prefix + path.relative_to(root / "mod").as_posix(): path.read_bytes()
                for path in (root / "mod").rglob("*") if path.is_file()}
    jar_path = root / "java/build/libs" / ("knox-survivors-" + version + ".jar")
    jar = jar_path.read_bytes()
    expected[prefix + "42/media/java/knox-survivors.jar"] = jar
    readme = (root / "release/README.txt").read_text().replace("${version}", version)
    expected["README.txt"] = readme.encode("utf-8")
    with zipfile.ZipFile(archive) as package:
        entries = [entry for entry in package.infolist() if not entry.is_dir()]
        names = [entry.filename for entry in entries]
        require(len(names) == len(set(name.casefold() for name in names)),
                "Duplicate archive paths")
        for name in names:
            path = PurePosixPath(name)
            require(not path.is_absolute() and ".." not in path.parts and "\\" not in name,
                    "Unsafe archive path: " + name)
        require(set(names) == set(expected),
                "ZIP inventory differs: " + str(sorted(set(names) ^ set(expected))))
        for name, data in expected.items():
            require(package.read(name) == data, "ZIP bytes differ from source: " + name)
        require(package.testzip() is None, "ZIP CRC failure")
    for name in ("mod/mod.info", "mod/42/mod.info", "mod/42/knoxbridge.properties"):
        data = (root / name).read_text()
        require("version=" + version in data.splitlines(), "Version mismatch: " + name)
    require((root / "mod/mod.info").read_bytes() == (root / "mod/42/mod.info").read_bytes(),
            "Mod metadata copies differ")
    require('KnoxSurvivors.VERSION = "' + version + '"' in
            (root / "mod/42/media/lua/client/KS_Bootstrap.lua").read_text(),
            "Lua version mismatch")
    require('RUNTIME_VERSION = "' + version + '"' in
            (root / "java/src/main/java/com/knoxsurvivors/bridge/KnoxBridge.java").read_text(),
            "Java version mismatch")
    with zipfile.ZipFile(io.BytesIO(jar)) as module:
        names = module.namelist()
        require("Implementation-Version: " + version in
                module.read("META-INF/MANIFEST.MF").decode(), "JAR version mismatch")
        require(all(not name.startswith(("zombie/", "com/knoxbridge/", "me/zed_0xff/",
                                         "net/bytebuddy/")) for name in names),
                "Game or framework classes bundled in the mod")
    return {"version": version, "archive": str(archive.resolve()),
            "files": len(expected), "sha256": hashlib.sha256(archive.read_bytes()).hexdigest(),
            "payload_parity": "PASS", "versions": "PASS", "native_gameplay": "NOT VERIFIED"}


if __name__ == "__main__":
    print(json.dumps(verify(Path(sys.argv[1])), indent=2))
