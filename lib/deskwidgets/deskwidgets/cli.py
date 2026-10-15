"""Command line: `deskwidgets [command]` (no command = run the service)."""
import argparse
import json
import os
import shutil
import subprocess
import sys
import time

from . import VERSION, catalog, paths, settings as settings_mod
from .i18n import set_lang, tr


def _bus():
    import gi
    gi.require_version('Gio', '2.0')
    from gi.repository import Gio, GLib
    return Gio, GLib, Gio.bus_get_sync(Gio.BusType.SESSION)


def service_running():
    Gio, GLib, bus = _bus()
    reply = bus.call_sync('org.freedesktop.DBus', '/org/freedesktop/DBus', 'org.freedesktop.DBus', 'NameHasOwner',
                          GLib.Variant('(s)', (paths.APP_ID,)), GLib.VariantType('(b)'), Gio.DBusCallFlags.NONE, -1, None)
    return reply.unpack()[0]


def ensure_service():
    if service_running():
        return True
    subprocess.Popen([paths.bin_path(), 'run'], start_new_session=True,
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    for _ in range(50):
        time.sleep(0.1)
        if service_running():
            return True
    return False


def remote(action, param=None):
    """Activates an action of the running service (starting it if needed)."""
    if not ensure_service():
        print(tr('Сервіс DeskWidgets не запустився', 'The DeskWidgets service did not start'), file=sys.stderr)
        return 1
    Gio, GLib, bus = _bus()
    Gio.DBusActionGroup.get(bus, paths.APP_ID, paths.APP_PATH).activate_action(action, param)
    bus.flush_sync(None)
    return 0


def _layout():
    try:
        with open(paths.LAYOUT, encoding='utf-8') as f:
            return json.load(f).get('instances', [])
    except (OSError, ValueError):
        return []


def cmd_run(_a):
    from .service import run
    return run()


def cmd_gallery(a):
    from .gallery import main
    return main(['--configure', a.id] if getattr(a, 'id', None) else [])


def cmd_add(a):
    from gi.repository import GLib
    return remote('add', GLib.Variant('s', a.type))


def cmd_remove(a):
    from gi.repository import GLib
    return remote('remove', GLib.Variant('s', a.id))


def cmd_simple(a):
    return remote(a.command)


def cmd_list(_a):
    for i in _layout():
        print(f"{i['id']:18} {i['type']:15} {i['size']:7} cell=({i['col']},{i['row']}) {i['style']}/{i['accent']}")
    return 0


def cmd_types(_a):
    for t in sorted(catalog.discover().values(), key=lambda t: (t.category, t.id)):
        where = tr('мій', 'mine') if t.user else tr('вбудований', 'built-in')
        print(f'{t.id:16} {t.title:28} {",".join(t.sizes):22} {catalog.category_name(t.category)} · {where}')
    return 0


def cmd_new(a):
    from . import scaffold
    try:
        folder = scaffold.create(a.id, a.name)
    except FileExistsError as e:
        print(tr('Вже існує: ', 'Already exists: ') + str(e), file=sys.stderr)
        return 1
    print(folder)
    print(tr(f'Відредагуйте widget.lua, потім: deskwidgets reload && deskwidgets add {os.path.basename(folder)}',
             f'Edit widget.lua, then: deskwidgets reload && deskwidgets add {os.path.basename(folder)}'))
    return 0


def cmd_preview(a):
    from . import engine
    types = catalog.discover()
    t = types.get(a.type)
    if t is None:
        print(tr('Немає такого віджета: ', 'No such widget: ') + a.type, file=sys.stderr)
        return 1
    s = settings_mod.load()
    paths.ensure_dirs()
    engine.write_fontconf(s)
    out = os.path.abspath(a.output or f'{t.id}-{a.size or t.size}.png')
    ok = engine.render(t, out, size=a.size, style=a.style, accent=a.accent, lang=a.lang or settings_mod.language(s),
                       scale=a.scale, demo=not a.live)
    print(out if ok else tr('Не вдалося відрендерити', 'Rendering failed'))
    return 0 if ok else 1


def render_thumbnails(types=None, lang=None):
    """Renders all thumbnails at once to ~/.cache/deskwidgets/previews/<version>/<lang>/<type>.png."""
    from . import engine
    s = settings_mod.load()
    lang = lang or settings_mod.language(s)
    paths.ensure_dirs()
    engine.write_fontconf(s)
    out_dir = os.path.join(paths.PREVIEWS, VERSION, lang)
    os.makedirs(out_dir, exist_ok=True)
    jobs = [(t, engine.render(t, os.path.join(out_dir, f'{t.id}.png'), lang=lang, wait=False))
            for t in (types or catalog.discover()).values()]
    ok = True
    for t, proc in jobs:
        try:
            proc.wait(timeout=30)
        except subprocess.TimeoutExpired:
            proc.kill()
        ok &= os.path.exists(os.path.join(out_dir, f'{t.id}.png'))
    return ok


def cmd_previews(_a):
    return 0 if render_thumbnails() else 1


def cmd_setup(a):
    from . import desktop
    done = desktop.setup(autostart=not a.no_autostart, hotkey=not a.no_hotkey, extension=not a.no_extension)
    s = settings_mod.load()
    s.update({'autostart': not a.no_autostart, 'hotkey': not a.no_hotkey, 'grid_overlay': not a.no_extension,
              '_setup_done': True})
    settings_mod.save(s)
    for k, v in done.items():
        print(f'{k}: {"ok" if v else "-"}')
    if done.get('extension'):
        print(tr('Підказка-сітка GNOME запрацює після повторного входу в систему.',
                 'The GNOME grid helper starts working after you log out and back in.'))
    return 0


def udev_command():
    rules = os.path.join(paths.DATA, 'data', 'udev', '70-deskwidgets-hid.rules')
    return (f'sudo install -m 644 {rules} /etc/udev/rules.d/ && sudo udevadm control --reload '
            f'&& sudo udevadm trigger --subsystem-match=hidraw')


def cmd_mice(_a):
    from . import hidbattery
    code = hidbattery.main()
    if any(not d['access'] for d in hidbattery.find()):
        print(tr('Щоб читати заряд миші без root, один раз виконайте:', 'To read the mouse battery without root, run once:'))
        print('  ' + udev_command())
    return code


def cmd_doctor(_a):
    from . import desktop, hidbattery
    from .grid import Grid
    ok = True

    def row(name, good, note=''):
        nonlocal ok
        ok &= bool(good) or note.startswith('(')
        print(f"{'✔' if good else '✘'} {name}{(' — ' + note) if note else ''}")

    print("=== DeskWidgets System & Dependency Checks ===")
    conky = shutil.which('conky')
    row('conky', conky, tr('встановіть conky-all', 'install conky-all') if not conky else '')
    if conky:
        info = subprocess.run(['conky', '-v'], capture_output=True, text=True).stdout
        row(tr('conky з Lua/Cairo', 'conky with Lua/Cairo'), 'Cairo' in info, tr('потрібен пакет conky-all', 'needs conky-all'))
    for mod, ver, pkg in (('Gtk', '3.0', 'gir1.2-gtk-3.0'), ('GdkPixbuf', '2.0', 'gir1.2-gdkpixbuf-2.0')):
        try:
            import gi
            gi.require_version(mod, ver)
            __import__('gi.repository.' + mod)
            row(f'{mod} {ver}', True)
        except (ImportError, ValueError):
            row(f'{mod} {ver}', False, pkg if '(' not in pkg else '(' + pkg)
    s = settings_mod.load()
    font = subprocess.run(['fc-list', s.get('font', 'Ubuntu Sans')], capture_output=True, text=True).stdout.strip()
    row(tr('шрифт ', 'font ') + s.get('font', 'Ubuntu Sans'), font, tr('буде запасний sans-serif', 'a fallback sans-serif will be used'))
    row(tr('сервіс працює', 'service running'), service_running(), f'({tr("запустіть", "start it")}: deskwidgets)')

    print("\n=== DeskWidgets Layout & Overlap Diagnostics ===")
    # 1. Read monitor workarea from xrandr or default 1280x1024
    screen_w, screen_h = 1280, 1024
    try:
        xrandr_out = subprocess.run(['xrandr', '--query'], capture_output=True, text=True).stdout
        for line in xrandr_out.splitlines():
            if ' connected' in line and ('primary' in line or '1280x1024' in line or 'HDMI-1' in line):
                import re
                m = re.search(r'(\d+)x(\d+)\+(\d+)\+(\d+)', line)
                if m:
                    screen_w, screen_h = int(m.group(1)), int(m.group(2))
                    break
    except Exception:
        pass

    top_bar = 28
    print(f"Monitor Workarea: {screen_w}x{screen_h} (Top Bar: {top_bar}px, Outer Margin: {s.get('margin_side', 16)}px, Gap: {s.get('gap', 16)}px)")

    grid = Grid(screen_w, screen_h, s)
    instances = _layout()

    # Query running X11 windows via wmctrl if available
    live_windows = {}
    try:
        wm_res = subprocess.run(['wmctrl', '-lG'], capture_output=True, text=True)
        for line in wm_res.stdout.splitlines():
            parts = line.split()
            if len(parts) >= 8 and 'deskwidget:' in line:
                for token in parts:
                    if token.startswith('deskwidget:'):
                        wid_name = token[len('deskwidget:'):]
                        live_windows[wid_name] = {
                            'x': int(parts[2]),
                            'y': int(parts[3]),
                            'w': int(parts[4]),
                            'h': int(parts[5]),
                        }
    except Exception:
        pass

    rects = []
    print("\nConfigured Widget Rectangles:")
    for inst in instances:
        iid = inst['id']
        size = inst['size']
        col = inst.get('col', 0)
        row_idx = inst.get('row', 0)
        calc_wx, calc_wy, calc_ww, calc_wh = grid.window_rect(col, row_idx, size)
        card_x, card_y, card_w, card_h = grid.card_rect(col, row_idx, size)

        # Use live X11 coords if window is currently mapped
        if iid in live_windows:
            cur = live_windows[iid]
            actual_x, actual_y, actual_w, actual_h = cur['x'], cur['y'], cur['w'], cur['h']
            source = "X11 Live"
        else:
            actual_x, actual_y, actual_w, actual_h = calc_wx, calc_wy, calc_ww, calc_wh
            source = "Grid Calc"

        rects.append({'id': iid, 'x': actual_x, 'y': actual_y, 'w': actual_w, 'h': actual_h,
                      'col': col, 'row': row_idx, 'card': (card_x, card_y, card_w, card_h)})
        print(f"  • {iid:12} [{size:6}] grid=({col},{row_idx}) -> win=({actual_x}, {actual_y}, {actual_w}x{actual_h}) card=({card_x}, {card_y}, {card_w}x{card_h}) [{source}]")

    print("\nIntegrity Checks:")
    # Check off-screen
    off_screen = []
    for r in rects:
        if r['x'] < 0 or r['y'] < top_bar or (r['x'] + r['w']) > screen_w or (r['y'] + r['h']) > screen_h:
            off_screen.append(f"{r['id']} (bounds: x={r['x']}, y={r['y']}, x2={r['x']+r['w']}, y2={r['y']+r['h']})")
    if off_screen:
        ok = False
        print(f"✘ Off-screen / Clipping: {', '.join(off_screen)}")
    else:
        print(f"✔ Off-screen Bounds: All {len(rects)} widgets fit strictly within {screen_w}x{screen_h} (below {top_bar}px bar)")

    # Check overlaps
    overlaps = []
    for i in range(len(rects)):
        for j in range(i + 1, len(rects)):
            r1, r2 = rects[i], rects[j]
            # Two boxes overlap if they intersect horizontally AND vertically
            if (r1['x'] < r2['x'] + r2['w'] and r1['x'] + r1['w'] > r2['x'] and
                r1['y'] < r2['y'] + r2['h'] and r1['y'] + r1['h'] > r2['y']):
                overlaps.append(f"{r1['id']} overlaps with {r2['id']}")
    if overlaps:
        ok = False
        print(f"✘ Window Overlaps Found: {', '.join(overlaps)}")
    else:
        print(f"✔ Non-overlapping: All {len(rects)} widget windows have strictly zero overlap")

    return 0 if ok else 1


def cmd_status(_a):
    ok = True
    print("=== DeskWidgets Status ===")

    # 1. Check Service PID and stale PID handling
    pid_file = os.path.join(paths.CACHE, 'service.pid')
    service_pid = None
    pid_status = "STOPPED"

    if os.path.isfile(pid_file):
        try:
            with open(pid_file, 'r', encoding='utf-8') as f:
                content = f.read().strip()
                if content.isdigit():
                    service_pid = int(content)
        except Exception:
            pass

    if service_pid is not None:
        try:
            os.kill(service_pid, 0)
            is_alive = True
        except (OSError, ProcessLookupError):
            is_alive = False

        if is_alive:
            try:
                with open(f'/proc/{service_pid}/cmdline', 'rb') as f:
                    cmdline = f.read().replace(b'\0', b' ').decode('utf-8', 'ignore')
                if 'deskwidgets' in cmdline:
                    pid_status = f"{service_pid} (running) [PID file valid]"
                else:
                    pid_status = f"{service_pid} [STALE - PID corresponds to an unrelated process: {cmdline[:30]}]"
                    ok = False
            except Exception:
                pid_status = f"{service_pid} (running) [PID file valid]"
        else:
            pid_status = f"{service_pid} [STALE - process not alive]"
            ok = False
    else:
        try:
            for p in os.listdir('/proc'):
                if p.isdigit():
                    try:
                        with open(f'/proc/{p}/cmdline', 'rb') as f:
                            c = f.read().replace(b'\0', b' ').decode('utf-8', 'ignore')
                        if 'deskwidgets run' in c or 'bin/deskwidgets run' in c:
                            service_pid = int(p)
                            pid_status = f"{service_pid} (running) [WARNING: PID file missing]"
                            break
                    except Exception:
                        pass
        except Exception:
            pass
        if service_pid is None:
            pid_status = "NOT RUNNING"
            ok = False

    print(f"Service PID: {pid_status}")

    # 2. X11 Window and Geometry Checks
    s = settings_mod.load()
    screen_w, screen_h = 1280, 1024
    from .grid import Grid
    grid = Grid(screen_w, screen_h, s)

    live_windows = {}
    try:
        from .x11 import X11
        x = X11()
        screen_w, screen_h = x.screen_size()
        grid = Grid(screen_w, screen_h, s)
        widget_wins = x.widget_windows()
        for wid, win_handle in widget_wins.items():
            geom = x.geometry(win_handle)
            pid = x.pid(win_handle)
            if geom:
                live_windows[wid] = {
                    'x': geom[0], 'y': geom[1],
                    'w': geom[2], 'h': geom[3],
                    'pid': pid
                }
    except Exception as e:
        try:
            wm_res = subprocess.run(['wmctrl', '-lpG'], capture_output=True, text=True)
            for line in wm_res.stdout.splitlines():
                parts = line.split()
                if len(parts) >= 8 and 'deskwidget:' in line:
                    for token in parts:
                        if token.startswith('deskwidget:'):
                            wid = token[len('deskwidget:'):]
                            live_windows[wid] = {
                                'x': int(parts[3]), 'y': int(parts[4]),
                                'w': int(parts[5]), 'h': int(parts[6]),
                                'pid': int(parts[2]) if parts[2].isdigit() else None
                            }
        except Exception:
            pass

    print(f"Screen Geometry: {screen_w}x{screen_h}\n")
    print("Widget Instances:")

    instances = _layout()
    if not instances:
        print("  No widgets configured in layout.json")
        return 1

    passed_count = 0
    total_count = len(instances)

    for inst in instances:
        wid = inst.get('id', 'unknown')
        wtype = inst.get('type', 'unknown')
        size = inst.get('size', 'small')
        col, row = inst.get('col', 0), inst.get('row', 0)
        calc_x, calc_y, calc_w, calc_h = grid.window_rect(col, row, size)

        real = live_windows.get(wid)
        if not real:
            print(f"[FAIL] {wid} ({wtype}:{size}): NO RUNNING PROCESS / NO WINDOW")
            print(f"       Real geometry:       NONE")
            print(f"       Calculated geometry: x={calc_x:<4} y={calc_y:<4} w={calc_w:<4} h={calc_h:<4}")
            err_file = os.path.expanduser(f"~/.cache/sequoia/widgets/{wid}.stderr")
            if os.path.isfile(err_file) and os.path.getsize(err_file) > 0:
                try:
                    with open(err_file, 'r', encoding='utf-8', errors='ignore') as ef:
                        lines = [ln.strip() for ln in ef.readlines() if ln.strip()]
                        if lines:
                            print(f"       Captured stderr:     {lines[-1]}")
                except Exception:
                    pass
            ok = False
        else:
            rx, ry, rw, rh = real['x'], real['y'], real['w'], real['h']
            cpid = real.get('pid') or 'unknown'
            dx = abs(rx - calc_x)
            dy = abs(ry - calc_y)
            if dx <= 4 and dy <= 4:
                print(f"[PASS] {wid} ({wtype}:{size}): conky PID {cpid}")
                print(f"       Real geometry:       x={rx:<4} y={ry:<4} w={rw:<4} h={rh:<4}")
                print(f"       Calculated geometry: x={calc_x:<4} y={calc_y:<4} w={calc_w:<4} h={calc_h:<4}")
                passed_count += 1
            else:
                print(f"[FAIL] {wid} ({wtype}:{size}): GEOMETRY MISPLACED (dx={rx-calc_x}, dy={ry-calc_y})")
                print(f"       Real geometry:       x={rx:<4} y={ry:<4} w={rw:<4} h={rh:<4}")
                print(f"       Calculated geometry: x={calc_x:<4} y={calc_y:<4} w={calc_w:<4} h={calc_h:<4}")
                ok = False

    print(f"\nSummary: {passed_count}/{total_count} widgets passing geometry and process checks.")
    if not ok:
        print("RESULT: FAILURES DETECTED")
        return 1
    else:
        print("RESULT: ALL CHECKS PASSED")
        return 0


def main(argv=None):
    set_lang(settings_mod.language())
    p = argparse.ArgumentParser(prog='deskwidgets', description=tr(
        'Віджети робочого столу в стилі macOS (conky).', 'macOS-style desktop widgets for Linux (conky).'))
    p.add_argument('--version', action='version', version=f'deskwidgets {VERSION}')
    sub = p.add_subparsers(dest='command')
    sub.add_parser('run', help=tr('запустити сервіс (за замовчуванням)', 'run the service (default)')).set_defaults(func=cmd_run)
    sub.add_parser('gallery', help=tr('відкрити галерею', 'open the gallery')).set_defaults(func=cmd_gallery)
    c = sub.add_parser('configure', help=tr('налаштування віджета', 'settings of a widget'))
    c.add_argument('id'); c.set_defaults(func=cmd_gallery)
    c = sub.add_parser('add', help=tr('додати віджет на стіл', 'add a widget to the desktop'))
    c.add_argument('type'); c.set_defaults(func=cmd_add)
    c = sub.add_parser('remove', help=tr('прибрати віджет', 'remove a widget'))
    c.add_argument('id'); c.set_defaults(func=cmd_remove)
    for name, h in (('arrange', tr('розставити по сітці', 'pack widgets onto the grid')),
                    ('reload', tr('перечитати віджети й перезапустити', 're-read widget folders and restart')),
                    ('quit', tr('зупинити сервіс', 'stop the service'))):
        sub.add_parser(name, help=h).set_defaults(func=cmd_simple)
    sub.add_parser('list', help=tr('віджети на столі', 'widgets on the desktop')).set_defaults(func=cmd_list)
    sub.add_parser('status', help=tr('статус віджетів і геометрія', 'widget status and geometry')).set_defaults(func=cmd_status)
    sub.add_parser('types', help=tr('усі доступні віджети', 'all available widgets')).set_defaults(func=cmd_types)
    c = sub.add_parser('new', help=tr('створити свій віджет', 'create your own widget'))
    c.add_argument('id'); c.add_argument('--name'); c.set_defaults(func=cmd_new)
    c = sub.add_parser('preview', help=tr('відрендерити віджет у PNG', 'render a widget to PNG'))
    c.add_argument('type'); c.add_argument('--size', choices=list(catalog.SIZES)); c.add_argument('--style')
    c.add_argument('--accent'); c.add_argument('--lang', choices=['uk', 'en']); c.add_argument('--scale', type=float, default=1.0)
    c.add_argument('--live', action='store_true', help=tr('справжні дані замість прикладу', 'real data instead of sample data'))
    c.add_argument('-o', '--output'); c.set_defaults(func=cmd_preview)
    sub.add_parser('previews', help=tr('оновити мініатюри галереї', 'refresh gallery thumbnails')).set_defaults(func=cmd_previews)
    c = sub.add_parser('setup', help=tr('автозапуск, гаряча клавіша, підказка-сітка', 'autostart, hotkey, grid helper'))
    c.add_argument('--no-autostart', action='store_true'); c.add_argument('--no-hotkey', action='store_true')
    c.add_argument('--no-extension', action='store_true'); c.set_defaults(func=cmd_setup)
    sub.add_parser('doctor', help=tr('перевірити залежності', 'check dependencies')).set_defaults(func=cmd_doctor)
    sub.add_parser('mice', help=tr('заряд бездротових ігрових мишей', 'battery of wireless gaming mice')).set_defaults(func=cmd_mice)
    a = p.parse_args(argv)
    if not getattr(a, 'func', None):
        return cmd_run(a)
    return a.func(a) or 0
