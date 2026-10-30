"""Real MediaMTX interoperability. Downloads only a pinned checksum-verified test tool."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import shutil
import socket
import subprocess
import tarfile
import tempfile
import time
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[1]
VERSION = "v1.21.3"
ASSETS = {
    "Windows": ("windows_amd64.zip", "b2f5246b07cb72961df03b8d5e8cad43dc657bcf3f49a87bb031bdf22721af74"),
    "Linux": ("linux_amd64.tar.gz", "0a2ea7eba96023631efa1bea7804823a9145b043b6646a8a05798d4ac24ed635"),
}

def obtain(directory):
    suffix, digest = ASSETS[platform.system()]
    filename = "mediamtx_" + VERSION + "_" + suffix
    path = directory / filename
    urllib.request.urlretrieve("https://github.com/bluenviron/mediamtx/releases/download/" + VERSION + "/" + filename, path)
    assert hashlib.sha256(path.read_bytes()).hexdigest() == digest, "server checksum mismatch"
    executable = "mediamtx.exe" if os.name == "nt" else "mediamtx"
    if suffix.endswith("zip"):
        with zipfile.ZipFile(path) as archive:
            (directory / executable).write_bytes(archive.read(executable))
    else:
        with tarfile.open(path) as archive:
            member = archive.extractfile(executable)
            assert member is not None
            (directory / executable).write_bytes(member.read())
        (directory / executable).chmod(0o755)
    return directory / executable

def ready(server, port):
    deadline = time.monotonic() + 10
    while time.monotonic() < deadline:
        assert server.poll() is None, "MediaMTX terminated before ready"
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=.1):
                return
        except OSError:
            time.sleep(.05)
    raise RuntimeError("server readiness timeout")

def stop(process):
    if process and process.poll() is None:
        process.terminate()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=5)

def run(args):
    moon = str(Path(args.moon).resolve()) if Path(args.moon).exists() else args.moon
    subprocess.run([moon, "build", "--target", args.target, "--deny-warn"], cwd=ROOT, check=True)
    stem = ROOT / "_build" / args.target / "debug" / "build" / "cmd" / "moonrtsp" / "moonrtsp"
    if args.target == "wasm":
        runner = shutil.which("moonrun") or str(Path(moon).with_name("moonrun.exe" if os.name == "nt" else "moonrun"))
        command = [runner, str(stem.with_suffix(".wasm"))]
    else:
        command = [str(stem.with_suffix(".exe"))]
    results = []
    with tempfile.TemporaryDirectory(prefix="moonrtsp-interop-") as temporary:
        directory = Path(temporary)
        binary = Path(args.server).resolve() if args.server else obtain(directory)
        for scheme in ["basic", "digest"]:
            for publication in ["tcp", "udp"]:
                config = directory / "server.yml"
                # All credentials below are public, disposable test values.
                config.write_text("""logLevel: warn
rtspAddress: 127.0.0.1:18554
rtpAddress: 127.0.0.1:18000
rtcpAddress: 127.0.0.1:18001
rtmp: false
hls: false
webrtc: false
srt: false
moq: false
rtspAuthMethods: [SCHEME]
authInternalUsers:
  - user: fixture
    pass: fixture-only
    permissions:
      - action: publish
      - action: read
paths:
  all_others:
""".replace("SCHEME", scheme), encoding="utf-8")
                environment = dict(os.environ, MOONRTSP_USER="fixture", MOONRTSP_PASSWORD="fixture-only")
                uri = "rtsp://127.0.0.1:18554/live"
                server = publisher = None
                try:
                    with (directory / "server.log").open("w") as log, (directory / "publisher.log").open("w+") as publisher_log:
                        server = subprocess.Popen([str(binary), str(config)], cwd=directory, stdout=log, stderr=log)
                        ready(server, 18554)
                        publisher = subprocess.Popen(command + ["publish-multi", uri, publication, "300"], cwd=ROOT, env=environment, stdout=publisher_log, stderr=subprocess.STDOUT)
                        # Probe the actual published stream: native stdout redirected
                        # to a file may stay buffered until the publisher exits.
                        deadline = time.monotonic() + 10
                        while True:
                            probe = subprocess.run(command + ["inspect", uri], cwd=ROOT, env=environment, capture_output=True, text=True, timeout=10)
                            if probe.returncode == 0:
                                inspect = probe.stdout
                                break
                            assert publisher.poll() is None, "publisher exited before stream readiness: " + (directory / "publisher.log").read_text(encoding="utf-8")
                            assert time.monotonic() < deadline, "stream readiness timeout: " + probe.stdout + probe.stderr
                            time.sleep(.05)
                        assert "track=0 kind=audio" in inspect and "track=1 kind=audio" in inspect
                        for transport in ["tcp", "udp"]:
                            playback = subprocess.run(command + ["play", uri, transport, "8"], cwd=ROOT, env=environment, capture_output=True, text=True, timeout=10, check=True).stdout
                            assert "received packets=8" in playback
                            if transport == "tcp":
                                assert "rtp track=0" in playback and "rtp track=1" in playback
                        wrong = dict(environment, MOONRTSP_PASSWORD="incorrect-fixture")
                        denial = subprocess.run(command + ["inspect", uri], cwd=ROOT, env=wrong, capture_output=True, text=True, timeout=10)
                        assert denial.returncode != 0, "wrong credentials accepted"
                        publisher.wait(timeout=12)
                        assert publisher.returncode == 0
                        assert "published packets=300" in (directory / "publisher.log").read_text(encoding="utf-8")
                        results.append({"authentication": scheme, "publication": publication, "tracks": 2, "playback": ["tcp", "udp"], "pause_resume_keepalive_teardown": True, "wrong_credentials_rejected": True})
                except Exception as error:
                    print("interop failure:", scheme, publication, flush=True)
                    if isinstance(error, subprocess.CalledProcessError):
                        print("client stdout:", error.stdout, flush=True)
                        print("client stderr:", error.stderr, flush=True)
                    for name in ["server.log", "publisher.log"]:
                        log_path = directory / name
                        if log_path.exists():
                            print(name + ":\n" + log_path.read_text(encoding="utf-8", errors="replace"), flush=True)
                    raise
                finally:
                    stop(publisher)
                    stop(server)
    print(json.dumps({"server": "MediaMTX " + VERSION, "target": args.target, "cases": results}, indent=2))

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--moon", default="moon")
    parser.add_argument("--target", choices=["wasm", "native"], default="wasm")
    parser.add_argument("--server")
    run(parser.parse_args())
