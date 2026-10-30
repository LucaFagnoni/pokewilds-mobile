"""Dedicated server smoke test, in runs of a headless server:
0. a world an older server hosted while it still had a player of its own
   (server/fixtures/online_v1.zip): it is found by its name, that SERVER
   player is gone, and a new player starts in its first area;
then three on one new world:
1. no player IDs: another build and a wrong shared password are refused; a
   client joins (the server makes the first area as it comes), walks into a
   new area the server has to make, and is saved, the only player in the
   saved world: the server is none;
2. player IDs, open: no ID is refused, a first login makes an ID, a wrong
   password is refused, the same ID on a second device gets the same character
   back, and a device that played before IDs keeps its character; two players
   in the first area see each other, and nobody else;
3. player IDs, closed: an unknown ID is refused until `account add` makes it
   (this server started with a bare --server: the game's scene hands over).

    python server/smoke_test.py GODOT            (GODOT = editor binary, runs project/)
    python server/smoke_test.py PokeWilds.console.exe --exe
    (--port N: the server's port, 54777 by default; another beside other servers;
     --quick: only the server runs, not the checks before them)

Run from the repository root. Exits 0 on success."""
import hashlib, json, os, re, subprocess, sys, tempfile, time, zipfile

godot = sys.argv[1]
command = [godot] if "--exe" in sys.argv else [godot, "--path", "project"]
work = tempfile.mkdtemp(prefix="pw-server-smoke-")
port = sys.argv[sys.argv.index("--port") + 1] if "--port" in sys.argv else "54777"
logs = {}


def start(name, args, build="smoke-a"):
    logs[name] = os.path.join(work, name + ".log")
    out = open(logs[name], "wb")
    # The compat id too: CI's project/compat_id.txt would make every "build" here compatible.
    env = dict(os.environ, POKEWILDS_BUILD_ID=build, POKEWILDS_COMPAT_ID=build)
    return subprocess.Popen(command + ["--headless"] + args, stdin=subprocess.PIPE, stdout=out, stderr=subprocess.STDOUT, env=env)


def text(name):
    return open(logs[name], "rb").read().decode("utf-8", "replace")


def fail(reason):
    for name in logs:
        print(f"----- {name} log (last lines) -----")
        print("\n".join(text(name).splitlines()[-40:]))
    print("SMOKE FAIL:", reason)
    sys.exit(1)


def wait_for(name, process, needle, seconds):
    deadline = time.time() + seconds
    while time.time() < deadline:
        if needle in text(name): return
        if process.poll() is not None: fail(f"{name} exited ({process.returncode}) before {needle!r}")
        time.sleep(1)
    fail(f"{name}: no {needle!r} after {seconds}s")


def send(process, line):
    process.stdin.write((line + "\n").encode()); process.stdin.flush()


# The address parser and the outside-address check first: seconds, not minutes.
if "--exe" not in sys.argv and "--quick" not in sys.argv:
    check = subprocess.run(command + ["--headless", "-s", os.path.abspath("server/address_check.gd")], capture_output=True, text=True, errors="replace")
    if "ADDRESS CHECK: 0 failed" not in check.stdout: print(check.stdout[-2000:], check.stderr[-2000:]); print("SMOKE FAIL: address check"); sys.exit(1)
    print("address check ok")
    # World deltas and compressed transfers (coop_world_delta.gd, coop_blob.gd).
    check = subprocess.run(command + ["--headless", "-s", os.path.abspath("server/coop_traffic_check.gd")], capture_output=True, text=True, errors="replace")
    if "COOP TRAFFIC CHECK: 0 failed" not in check.stdout: print(check.stdout[-2000:], check.stderr[-2000:]); print("SMOKE FAIL: co-op traffic check"); sys.exit(1)
    print("co-op traffic check ok")
    # The phone's list of saved servers: add, edit, delete, survive a restart, join.
    check = subprocess.run(command + ["--headless", "-s", os.path.abspath("server/saved_servers_test.gd"), "--", "--touch-ui"], capture_output=True, text=True, errors="replace", timeout=900)
    found = re.search(r"SAVED SERVERS TEST: (\d+) checks, (\d+) failed", check.stdout)
    if not found or found.group(2) != "0": print(check.stdout[-3000:]); print("SMOKE FAIL: saved servers list"); sys.exit(1)
    print(f"saved servers list ok ({found.group(1)} checks)")
    # The iPhone's ZeroTier plugin, as the game uses it, against a stand-in.
    import zerotier_stub
    ok, output = zerotier_stub.run(command)
    if not ok: print(output[-3000:]); print("SMOKE FAIL: ZeroTier bridge"); sys.exit(1)
    print("ZeroTier bridge ok")

server_data = os.path.join(work, "server")
server = None


def start_server(name, extra, world="Smoke", data=None, scene=True):
    """The server as start_server.bat starts it: its own scene, never the game's
    (main.tscn); without `scene`, as a bare --server does, the game's scene hands over."""
    global server
    server = start(name, (["res://scenes/server.tscn"] if scene else []) + ["--server", "--port", port, "--world", world, "--size", "S",
        "--data", data or server_data, "--no-upnp", "--area-size", "S"] + extra)
    started = time.time()
    wait_for(name, server, "listening on TCP port " + port, 900)
    print(f"{name} ready in {time.time() - started:.0f}s")
    return name


def stop_server(name):
    saves = text(name).count("SERVER world saved")
    send(server, "stop")
    # Closing the input as the launcher does lets the console-reading thread end
    # (on Linux the process otherwise waits for it at exit).
    server.stdin.close()
    try: server.wait(120)
    except subprocess.TimeoutExpired: fail(f"{name} did not stop")
    if text(name).count("SERVER world saved") <= saves: fail(f"{name} did not save on stop")


def join(name, args, needle, build="smoke-a"):
    """Runs a client to its end; its log must contain `needle`."""
    client = start(name, ["--join", "127.0.0.1:" + port, "--data", os.path.join(work, "device-" + name.split("-")[0])] + args, build)
    try: client.wait(900)
    except subprocess.TimeoutExpired: client.kill(); fail(f"{name} neither joined nor failed")
    if needle not in text(name): fail(f"{name}: expected {needle!r}")
    return text(name)


def actor_of(name):
    found = re.search(r"CLIENT joined world (\w+) in area (\S+) .* as (\w+)", text(name))
    if not found: fail(f"{name} did not join")
    return found.groups()


def device_actor(device):
    token = re.search(r'token="(\w+)"', open(os.path.join(work, "device-" + device, "coop_identity.cfg")).read()).group(1)
    return hashlib.sha256(token.encode()).hexdigest()


def same_wild(name, run, area="0,0"):
    """The player saw the area's wild Pokemon as the server runs them (a few
    may come or go in the moment between the two counts)."""
    seen = re.search(rf"CLIENT sees (\d+) wild Pokemon in area {area}", text(name))
    held = re.findall(rf"SERVER area {area} in play: (\d+) wild", text(run))
    if not seen or not held or abs(int(seen.group(1)) - int(held[-1])) > 5:
        fail(f"{name} sees {seen.group(1) if seen else 'no'} wild Pokemon in area {area}, the server runs {held[-1] if held else 'none'}")


def saved_world(data, world_id):
    """The state of a world as its server saved it in world.json."""
    world = os.path.join(data, "online_worlds", world_id, "world.json")
    return json.loads(json.load(open(world, encoding="utf-8"))["payload"])["state"]


try:
    # --- 0: a world an older server hosted, with a player of its own ---------
    old_data = os.path.join(work, "old-server")
    with zipfile.ZipFile("server/fixtures/online_v1.zip") as fixture:
        old_world = json.loads(json.loads(fixture.read("world.json"))["payload"])
        fixture.extractall(os.path.join(old_data, "online_worlds", old_world["id"]))
    owner = old_world["metadata"]["owner"]
    if old_world["state"]["members"].get(owner, {}).get("name") != "SERVER": fail("the fixture is not an old server's world")
    run = start_server("server0", ["--accounts", "off"], "Fixture", old_data)
    if f'loading world "Fixture" ({old_world["id"]})' not in text(run): fail("the old server's world was not found by its name")
    if "SERVER player is gone" not in text(run): fail("the old server's own player was not dropped")
    join("newcomer", ["--quit-after-join"], f"CLIENT joined world {old_world['id']} in area 0,0")
    stop_server(run)
    state = saved_world(old_data, old_world["id"])
    if "player/" + owner in state["records"] or owner in state["members"]: fail("the old SERVER player is still in the saved world")
    if "player/" + device_actor("newcomer") not in state["records"]: fail("the newcomer is not in the saved world")
    if open(os.path.join(old_data, "online_worlds", old_world["id"], "name.txt"), encoding="utf-8").read() != "Fixture": fail("the world's name file")
    print("an old server's world loads by its name, without its SERVER player; a new player starts in its first area")


    # --- 1: no player IDs, the shared password ---------------------------------
    run = start_server("server1", ["--accounts", "off", "--password", "smoke"])
    join("stranger", ["--password", "smoke"], "DIFFERENT GAME VERSION", build="smoke-b")
    print("another build refused")
    join("intruder", ["--password", "wrong"], "WRONG PASSWORD")
    print("wrong shared password refused")
    # The client also walks into a new area, which the server must make for it.
    join("old", ["--password", "smoke", "--see", "0", "--travel", "--quit-after-join"], "CLIENT travelled to area 1,0")
    world_id, area, _ = actor_of("old")
    if area != "0,0" or "SERVER made area 0,0" not in text(run): fail(f"the first player did not start in the first area made for them ({area})")
    if "SERVER made area 1,0" not in text(run): fail("the server did not make the new area")
    print("client joined; the server made the new area it walked into")
    # Every area is an AreaSim of the server's, the one players start in too,
    # and the first player's game holds that area as the server does.
    if "SERVER area 0,0 in play" not in text(run): fail("the server did not run the first area's Pokemon")
    same_wild("old", run)
    print("the server ran the first area's Pokemon, and the player saw them all")
    stop_server(run)
    state = saved_world(server_data, world_id)
    players = sorted(key for key in state["records"] if key.startswith("player/"))
    if players != ["player/" + device_actor("old")] or list(state["members"]) != [device_actor("old")]:
        fail(f"the saved world's players are not just the client: {players}, members {list(state['members'])}")
    print("server saved the world with the client's player in it, and no player of its own")

    # --- 2: player IDs, a first login makes the ID -----------------------------
    run = start_server("server2", [])
    join("noid", ["--quit-after-join"], "NEEDS A PLAYER ID")
    print("a player without an ID refused")
    join("phone", ["--id", "Alice", "--password", "secret-1", "--travel", "--quit-after-join"], "CLIENT travelled to area 1,0")
    _, _, alice = actor_of("phone")
    if "SERVER new player ID: alice" not in text(run): fail("the new ID was not registered")
    print("first login made the ID alice")
    join("tablet-wrong", ["--id", "alice", "--password", "secret-2"], "WRONG PLAYER ID OR PASSWORD")
    print("wrong password for alice refused")
    join("tablet", ["--id", "ALICE", "--password", "secret-1", "--quit-after-join"], "CLIENT joined world")
    _, area, again = actor_of("tablet")
    if again != alice or area != "1,0": fail(f"alice on a second device got {again} in {area}, not {alice} in 1,0")
    print("alice on a second device got her character back, where she left it")
    join("old-id", ["--id", "bob", "--password", "secret-3", "--quit-after-join"], "CLIENT joined world")
    if actor_of("old-id")[2] != device_actor("old")[:12]: fail("a device that played before IDs did not keep its character")
    print("a device that played before IDs kept its character as bob")
    # Two players in the first area see each other, and nobody else: the server is no player.
    pair = []
    for name in ["dana", "evan"]:
        pair.append(start(name, ["--join", "127.0.0.1:" + port, "--data", os.path.join(work, "device-" + name), "--id", name, "--password", "pass-" + name,
            "--see", "1", "--quit-after-join"]))
        wait_for(name, pair[-1], "CLIENT joined world", 900)
    for name, client in zip(["dana", "evan"], pair):
        try: client.wait(300)
        except subprocess.TimeoutExpired: client.kill(); fail(f"{name} did not end")
    dana, evan = actor_of("dana")[2], actor_of("evan")[2]
    if f"CLIENT sees 1 other players: {evan}" not in text("dana") or f"CLIENT sees 1 other players: {dana}" not in text("evan"):
        fail("the two players in one area did not see each other, and only each other")
    for name in ["dana", "evan"]: same_wild(name, run)
    for name, count in [("dana", 1), ("evan", 2)]:
        if not re.search(rf"SERVER join: \S+ \(ID {name}\) from \S+ \({count}/4\)", text(run)): fail(f"{name} was not counted as player {count} of 4")
    print("two players in one area see each other and nobody else; the server counts only them")
    stop_server(run)
    stored = open(os.path.join(server_data, "accounts.json"), encoding="utf-8").read()
    accounts = json.loads(stored)["accounts"]
    if set(accounts) != {"alice", "bob", "dana", "evan"} or "secret-1" in stored or not all(len(a["verifier"]) == 64 and a["salt"] for a in accounts.values()):
        fail("accounts.json is not just salted hashes of alice, bob, dana and evan")
    print("accounts.json holds salted hashes only")

    # --- 3: closed: only IDs made on the server --------------------------------
    run = start_server("server3", ["--accounts", "closed"], scene=False)
    join("carol-unknown", ["--id", "carol", "--password", "pass-4"], "UNKNOWN PLAYER ID")
    send(server, "account add carol pass-4")
    wait_for(run, server, "carol can now log in", 30)
    join("carol", ["--id", "carol", "--password", "pass-4", "--quit-after-join"], "CLIENT joined world")
    print("closed server: unknown ID refused, admitted after account add")
    stop_server(run)
    print("SMOKE OK: builds, shared password, server-made area, saves, and player IDs (open and closed) all behave")
finally:
    if server is not None and server.poll() is None: server.kill()
