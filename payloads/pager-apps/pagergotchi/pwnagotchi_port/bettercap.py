import os
import re
import time
import json
import logging
import asyncio
import subprocess
import threading
from glob import glob
from queue import Queue, Empty

import pwnagotchi_port.utils as utils

HANDSHAKES_DIR = '/root/loot/Pagergotchi/handshakes'
EXAMINE_SECONDS = 6


def freq_to_channel(freq):
    try:
        freq = int(freq)
    except (TypeError, ValueError):
        return 0
    if 2412 <= freq <= 2472:
        return (freq - 2407) // 5
    if freq == 2484:
        return 14
    if 5180 <= freq <= 5895:
        return (freq - 5000) // 5
    if 5955 <= freq <= 7115:
        return (freq - 5950) // 5
    return 0


class PineAPBackend:

    def __init__(self, handshakes_dir=HANDSHAKES_DIR, pineapd_iface='wlan1mon', pmkid_iface=None):
        self.handshakes_dir = HANDSHAKES_DIR
        self.pineapd_iface = pineapd_iface or 'wlan1mon'
        self.pmkid_iface = pmkid_iface
        self.running = False

        self.access_points = {}
        self.clients = {}
        self.handshakes = {}

        self._known_keys = set()
        self._learned_essids = {}

        self.event_queue = Queue()

        self._recon_thread = None
        self._handshake_thread = None
        self._pmkid_convert_thread = None
        self._lock = threading.Lock()
        self._clients_lock = threading.Lock()

        self._hcx_proc = None
        self._hcx_pcap = None
        self._hcx_out = None

        self._sweep_proc = None
        self._sweep_pcap = None
        self._sweep_out = None
        self._sweep_filter = None

        self.current_channel = 0
        self.focused_bssid = None
        self.iface_status = ''

        self._seed_known_keys()

    def _run_cmd(self, cmd, timeout=10):
        try:
            if isinstance(cmd, str):
                cmd = cmd.split()
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
            output = result.stdout.strip() or result.stderr.strip()
            return output, result.stderr.strip(), result.returncode
        except subprocess.TimeoutExpired:
            logging.warning("[PineAP] Command timed out: %s", cmd)
            return '', 'timeout', -1
        except Exception as e:
            logging.error("[PineAP] Command error: %s", e)
            return '', str(e), -1

    def _seed_known_keys(self):
        for key, rec in utils.scan_handshake_captures(self.handshakes_dir).items():
            self._known_keys.add(key)
            if rec['essid'] and rec['ap']:
                self._learned_essids[rec['ap'].lower()] = rec['essid']

    def apply_interfaces(self):
        present = self._pineap_interfaces()
        if self.pineapd_iface not in present:
            self._run_cmd(['_pineap', 'INTERFACE', 'ADD', self.pineapd_iface,
                           'band=2,5', 'type=max', 'rate=fast'])
            time.sleep(1)
            present = self._pineap_interfaces()

        for iface in present:
            if iface != self.pineapd_iface:
                self._run_cmd(['_pineap', 'INTERFACE', 'DISABLE', iface])

        self._run_cmd(['_pineap', 'INTERFACE', 'ENABLE', self.pineapd_iface])
        self._run_cmd(['_pineap', 'INTERFACE', 'SET', self.pineapd_iface, 'HOP', 'fast'])
        self._run_cmd(['_pineap', 'INTERFACE', 'PRIMARY', self.pineapd_iface])
        self._run_cmd(['_pineap', 'INTERFACE', 'INJECT', self.pineapd_iface])

        present = self._pineap_interfaces()
        if self.pineapd_iface in present:
            self.iface_status = self.pineapd_iface
            logging.info("[PineAP] capture interface: %s", self.pineapd_iface)
            return True
        logging.warning("[PineAP] capture interface %s not active (have: %s)",
                        self.pineapd_iface, present)
        self.iface_status = ''
        return False

    def _pineap_interfaces(self):
        out, _, rc = self._run_cmd(['_pineap', 'INTERFACE', 'LIST', 'json'])
        names = []
        if out:
            try:
                data = json.loads(out)
                for entry in data:
                    name = entry.get('ifname')
                    if name:
                        names.append(name)
            except (ValueError, AttributeError):
                pass
        return names

    def start(self):
        if self.running:
            return True
        os.makedirs(self.handshakes_dir, exist_ok=True)
        self.apply_interfaces()
        self._run_cmd(['_pineap', 'EXAMINE', 'CANCEL'])
        self.running = True

        self._recon_thread = threading.Thread(target=self._recon_loop, name="PineAP Recon", daemon=True)
        self._recon_thread.start()
        self._handshake_thread = threading.Thread(target=self._handshake_monitor_loop, name="PineAP Handshakes", daemon=True)
        self._handshake_thread.start()

        if self.pmkid_iface:
            self._start_pmkid()

        logging.info("[PineAP] started (capture=%s pmkid=%s)", self.pineapd_iface, self.pmkid_iface or 'off')
        return True

    def stop(self):
        self.running = False
        self._stop_pmkid()
        self._run_cmd(['_pineap', 'EXAMINE', 'CANCEL'])
        logging.info("[PineAP] stopped")

    def _start_pmkid(self):
        if not self.pmkid_iface:
            return
        if not utils.iface_is_monitor(self.pmkid_iface):
            logging.warning("[PMKID] %s not in monitor mode, PMKID disabled", self.pmkid_iface)
            self.pmkid_iface = None
            return
        if self._run_cmd(['which', 'hcxdumptool'])[2] != 0:
            logging.warning("[PMKID] hcxdumptool not found, PMKID disabled")
            self.pmkid_iface = None
            return

        ts = int(time.time())
        self._hcx_pcap = os.path.join(self.handshakes_dir, 'hcx_%d.pcapng' % ts)
        self._hcx_out = os.path.join(self.handshakes_dir, 'hcx_%d.22000' % ts)
        cmd = ['hcxdumptool', '-i', self.pmkid_iface, '-w', self._hcx_pcap, '-F']
        try:
            self._hcx_proc = subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except Exception as e:
            logging.warning("[PMKID] could not start hcxdumptool: %s", e)
            self._hcx_proc = None
            self.pmkid_iface = None
            return

        time.sleep(2)
        if self._hcx_proc.poll() is not None:
            logging.warning("[PMKID] hcxdumptool exited immediately, PMKID disabled")
            self._hcx_proc = None
            self.pmkid_iface = None
            return

        logging.info("[PMKID] active on %s (pid %s)", self.pmkid_iface, self._hcx_proc.pid)
        self._pmkid_convert_thread = threading.Thread(target=self._pmkid_convert_loop, name="PMKID Convert", daemon=True)
        self._pmkid_convert_thread.start()

    def _pmkid_convert_loop(self):
        while self.running and self._hcx_proc and self._hcx_proc.poll() is None:
            time.sleep(20)
            self._pmkid_convert()
        self._pmkid_convert()

    def _pmkid_convert(self):
        if not self._hcx_pcap or not os.path.exists(self._hcx_pcap):
            return
        try:
            subprocess.run(['hcxpcapngtool', '-o', self._hcx_out, self._hcx_pcap],
                           capture_output=True, timeout=60)
        except Exception as e:
            logging.debug("[PMKID] convert error: %s", e)

    def _stop_pmkid(self):
        if self._hcx_proc:
            try:
                self._hcx_proc.terminate()
                self._hcx_proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                self._hcx_proc.kill()
            except Exception:
                pass
            self._hcx_proc = None
            self._pmkid_convert()

    def pmkid_sweep_start(self, target_bssids=None):
        iface = self.pineapd_iface
        if self._run_cmd(['which', 'hcxdumptool'])[2] != 0:
            return False
        if not utils.iface_is_monitor(iface):
            return False

        self._run_cmd(['_pineap', 'EXAMINE', 'CANCEL'])
        self._run_cmd(['_pineap', 'INTERFACE', 'DISABLE', iface])
        time.sleep(1)

        ts = int(time.time())
        self._sweep_pcap = os.path.join(self.handshakes_dir, 'sweep_%d.pcapng' % ts)
        self._sweep_out = os.path.join(self.handshakes_dir, 'sweep_%d.22000' % ts)
        self._sweep_filter = None

        base = ['hcxdumptool', '-i', iface, '-w', self._sweep_pcap, '-F']
        cmd = list(base)
        if target_bssids:
            fpath = os.path.join(self.handshakes_dir, '.sweep_targets')
            try:
                with open(fpath, 'w') as fh:
                    for b in target_bssids:
                        fh.write(b.replace(':', '').lower() + '\n')
                cmd += ['--filterlist_ap=%s' % fpath, '--filtermode=2']
                self._sweep_filter = fpath
            except Exception:
                self._sweep_filter = None

        if not self._spawn_sweep(cmd):
            if self._sweep_filter:
                logging.warning("[PMKID sweep] hcxdumptool would not start with target filter, retrying unfiltered")
                self._sweep_filter = None
                if not self._spawn_sweep(base):
                    self._restore_after_sweep()
                    return False
            else:
                self._restore_after_sweep()
                return False

        logging.info("[PMKID sweep] active on %s (pid %s, targets=%s)",
                     iface, self._sweep_proc.pid, len(target_bssids) if target_bssids else 'all')
        return True

    def _spawn_sweep(self, cmd):
        try:
            self._sweep_proc = subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except Exception as e:
            logging.warning("[PMKID sweep] spawn error: %s", e)
            self._sweep_proc = None
            return False
        time.sleep(2)
        if self._sweep_proc.poll() is not None:
            self._sweep_proc = None
            return False
        return True

    def pmkid_sweep_finish(self):
        if self._sweep_proc:
            try:
                self._sweep_proc.terminate()
                self._sweep_proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                self._sweep_proc.kill()
            except Exception:
                pass
            self._sweep_proc = None
        if self._sweep_pcap and os.path.exists(self._sweep_pcap):
            try:
                subprocess.run(['hcxpcapngtool', '-o', self._sweep_out, self._sweep_pcap],
                               capture_output=True, timeout=60)
            except Exception as e:
                logging.debug("[PMKID sweep] convert error: %s", e)
        self._restore_after_sweep()

    def _restore_after_sweep(self):
        iface = self.pineapd_iface
        self._run_cmd(['_pineap', 'INTERFACE', 'ENABLE', iface])
        self._run_cmd(['_pineap', 'INTERFACE', 'SET', iface, 'HOP', 'fast'])
        self._run_cmd(['_pineap', 'INTERFACE', 'PRIMARY', iface])
        self._run_cmd(['_pineap', 'INTERFACE', 'INJECT', iface])
        if self._sweep_filter:
            try:
                os.remove(self._sweep_filter)
            except Exception:
                pass
            self._sweep_filter = None

    def _recon_loop(self):
        while self.running:
            try:
                self._fetch_aps()
                self._fetch_devices()
            except Exception as e:
                logging.debug("[PineAP] recon error: %s", e)
            time.sleep(3)

    def _fetch_aps(self):
        output, stderr, rc = self._run_cmd(['_pineap', 'RECON', 'APS', 'format=json', 'limit=200'])
        if not output:
            return
        try:
            data = json.loads(output)
        except ValueError:
            return

        aps_list = data if isinstance(data, list) else data.get('aps', [])
        new_aps = {}
        for ap in aps_list:
            mac = ap.get('mac', '').upper()
            if not mac:
                continue
            ssid = ''
            channel = 0
            beacon = ap.get('beacon', {})
            if isinstance(beacon, dict):
                for bdata in beacon.values():
                    if isinstance(bdata, dict):
                        ssid = bdata.get('ssid', '') or ssid
                        channel = bdata.get('channel', 0) or channel
                        if ssid and channel:
                            break
            if not channel:
                channel = freq_to_channel(ap.get('freq', 0))
            if not ssid:
                ssid = self._learned_essids.get(mac.lower(), '')
            new_aps[mac.lower()] = {
                'mac': mac,
                'hostname': ssid,
                'vendor': '',
                'channel': channel,
                'rssi': int(ap.get('signal', -100)),
                'encryption': 'WPA2',
                'clients': [],
                'last_seen': time.time(),
            }
        with self._lock:
            self.access_points = new_aps

    def _fetch_devices(self):
        output, stderr, rc = self._run_cmd(['_pineap', 'RECON', 'DEVICES', 'format=json', 'limit=300'])
        if not output:
            return
        try:
            data = json.loads(output)
        except ValueError:
            return
        devices = data if isinstance(data, list) else data.get('devices', data.get('data', []))
        if not isinstance(devices, list):
            return

        now = time.time()
        with self._clients_lock:
            for dev in devices:
                if not isinstance(dev, dict):
                    continue
                sta = (dev.get('mac') or dev.get('station') or '').lower()
                ap = (dev.get('ap') or dev.get('bssid') or dev.get('access_point') or '').lower()
                if not sta or not ap or len(sta) != 17 or len(ap) != 17:
                    continue
                if sta.startswith('ff:') or sta.startswith('33:33') or sta.startswith('01:'):
                    continue
                self.clients.setdefault(ap, {})[sta] = {
                    'mac': sta.upper(),
                    'vendor': '',
                    'last_seen': now,
                }

    def _get_clients_for_ap(self, ap_mac):
        ap_mac = ap_mac.lower()
        now = time.time()
        out = []
        with self._clients_lock:
            for sta, data in self.clients.get(ap_mac, {}).items():
                if now - data['last_seen'] < 300:
                    out.append({'mac': data['mac'], 'vendor': data['vendor']})
        return out

    def _handshake_monitor_loop(self):
        while self.running:
            try:
                self._check_new_handshakes()
            except Exception as e:
                logging.debug("[PineAP] handshake monitor error: %s", e)
            time.sleep(2)

    def _check_new_handshakes(self):
        captures = utils.scan_handshake_captures(self.handshakes_dir)
        for key, rec in captures.items():
            if key in self._known_keys:
                continue
            self._known_keys.add(key)
            if rec['essid'] and rec['ap']:
                self._learned_essids[rec['ap'].lower()] = rec['essid']
            self.handshakes[key] = rec
            self.event_queue.put({
                'tag': 'wifi.client.handshake',
                'data': {
                    'file': rec.get('file', ''),
                    'ap': rec['ap'],
                    'station': rec['sta'],
                    'ap_name': rec['essid'],
                },
            })

    def deauth(self, bssid, client_mac='FF:FF:FF:FF:FF:FF', channel=None):
        if channel is None:
            with self._lock:
                ap = self.access_points.get(bssid.lower())
            channel = ap.get('channel', 0) if ap else self.current_channel
        if not channel:
            return False
        stdout, stderr, rc = self._run_cmd(['_pineap', 'DEAUTH', bssid, client_mac, str(channel)])
        return rc == 0

    def set_channel(self, channel):
        self.current_channel = channel
        self.focused_bssid = None
        if channel == 0:
            self._run_cmd(['_pineap', 'EXAMINE', 'CANCEL'])
        else:
            self._run_cmd(['_pineap', 'EXAMINE', 'CHANNEL', str(channel), str(EXAMINE_SECONDS)])
        return True

    def dwell(self, channel, seconds):
        if channel:
            self._run_cmd(['_pineap', 'EXAMINE', 'CHANNEL', str(channel), str(int(seconds) + 1)])

    def focus_bssid(self, bssid):
        self.focused_bssid = bssid
        with self._lock:
            ap = self.access_points.get(bssid.lower())
        if ap:
            self.current_channel = ap.get('channel', 0)
        return True

    def clear_focus(self):
        self.focused_bssid = None
        self.current_channel = 0
        self._run_cmd(['_pineap', 'EXAMINE', 'CANCEL'])
        return True

    def get_current_channel(self):
        for iface in (self.pineapd_iface,):
            output, stderr, rc = self._run_cmd(['iw', 'dev', iface, 'info'])
            if output and rc == 0:
                match = re.search(r'channel\s+(\d+)\s+\((\d+)\s*MHz\)', output)
                if match:
                    channel = match.group(1)
                    freq = int(match.group(2))
                    if freq < 3000:
                        band = "2G"
                    elif freq < 5925:
                        band = "5G"
                    else:
                        band = "6G"
                    return "%s(%s)" % (channel, band)
        return '*'

    def get_session_data(self):
        with self._lock:
            aps_list = []
            for mac, ap in self.access_points.items():
                clients = self._get_clients_for_ap(mac)
                aps_list.append({
                    'mac': ap['mac'],
                    'hostname': ap['hostname'],
                    'vendor': ap['vendor'],
                    'channel': ap['channel'],
                    'rssi': ap['rssi'],
                    'encryption': ap['encryption'],
                    'clients': clients,
                    'first_seen': ap.get('first_seen', ''),
                    'last_seen': ap.get('last_seen', ''),
                })
        ifaces = [{'name': self.pineapd_iface}]
        if self.pmkid_iface:
            ifaces.append({'name': self.pmkid_iface})
        return {
            'wifi': {'aps': aps_list},
            'interfaces': ifaces,
            'modules': [
                {'name': 'wifi', 'running': self.running},
                {'name': 'wifi.recon', 'running': self.running},
            ],
        }

    def get_next_event(self, timeout=1.0):
        try:
            return self.event_queue.get(timeout=timeout)
        except Empty:
            return None

    def get_total_handshakes_count(self):
        return len(utils.scan_handshake_captures(self.handshakes_dir))

    def get_latest_handshake(self):
        if not self.handshakes:
            return None
        last_key = list(self.handshakes.keys())[-1]
        return self.handshakes[last_key]


class Client:

    def __init__(self, hostname='localhost', scheme='http', port=8081,
                 username='user', password='pass'):
        self.hostname = hostname
        self.scheme = scheme
        self.port = port
        self.username = username
        self.password = password
        self.url = "%s://%s:%d/api" % (scheme, hostname, port)
        self.websocket = "ws://%s:%s@%s:%d/api" % (username, password, hostname, port)

        self._backend = None
        self._backend_lock = threading.Lock()
        self._handshakes_dir = HANDSHAKES_DIR
        self._pineapd_iface = 'wlan1mon'
        self._pmkid_iface = None

    def set_interfaces(self, pineapd_iface, pmkid_iface):
        self._pineapd_iface = pineapd_iface or 'wlan1mon'
        self._pmkid_iface = pmkid_iface
        if self._backend:
            self._backend.pineapd_iface = self._pineapd_iface
            self._backend.pmkid_iface = self._pmkid_iface

    def _ensure_backend(self):
        with self._backend_lock:
            if self._backend is None:
                self._backend = PineAPBackend(
                    handshakes_dir=self._handshakes_dir,
                    pineapd_iface=self._pineapd_iface,
                    pmkid_iface=self._pmkid_iface)
            return self._backend

    def stop(self):
        if self._backend:
            self._backend.stop()
            logging.info("[Client] backend stopped")

    def get_total_handshakes_count(self):
        return self._ensure_backend().get_total_handshakes_count()

    def get_latest_handshake(self):
        return self._ensure_backend().get_latest_handshake()

    def session(self, sess="session"):
        return self._ensure_backend().get_session_data()

    def run(self, command, verbose_errors=True):
        backend = self._ensure_backend()
        command = command.strip()
        logging.debug("[bettercap/PineAP] run: %s", command)

        if command == 'wifi.recon on':
            backend.start()
            return {'success': True}
        if command == 'wifi.recon off':
            backend.stop()
            return {'success': True}
        if command.startswith('wifi.recon.channel'):
            parts = command.split()
            if len(parts) >= 2:
                arg = parts[1]
                if arg == 'clear':
                    backend.clear_focus()
                else:
                    try:
                        channels = [int(c.strip()) for c in arg.split(',')]
                        if len(channels) == 1:
                            backend.set_channel(channels[0])
                        else:
                            backend.clear_focus()
                    except ValueError:
                        pass
            return {'success': True}
        if command == 'wifi.clear':
            with backend._lock:
                backend.access_points.clear()
            return {'success': True}
        if command.startswith('wifi.assoc'):
            mac = command.replace('wifi.assoc', '').strip()
            if mac:
                backend.focus_bssid(mac)
            return {'success': True}
        if command.startswith('wifi.deauth'):
            args = command.replace('wifi.deauth', '').strip().split()
            if args:
                bssid = args[0]
                client_mac = args[1] if len(args) > 1 else 'FF:FF:FF:FF:FF:FF'
                backend.deauth(bssid, client_mac)
            return {'success': True}
        if command.startswith('set wifi.'):
            return {'success': True}
        if command.startswith('events.'):
            return {'success': True}
        if command.startswith('!'):
            shell_cmd = command[1:]
            try:
                result = subprocess.run(shell_cmd, shell=True, capture_output=True, text=True, timeout=30)
                return {'success': result.returncode == 0, 'output': result.stdout}
            except Exception as e:
                return {'success': False, 'error': str(e)}
        return {'success': True}

    async def start_websocket(self, consumer):
        backend = self._ensure_backend()
        logging.info("[bettercap/PineAP] event polling started")
        while backend.running or self._backend is None:
            try:
                event = backend.get_next_event(timeout=1.0)
                if event:
                    await consumer(json.dumps(event))
                else:
                    await asyncio.sleep(0.2)
            except Exception as e:
                logging.debug("[bettercap/PineAP] event loop error: %s", e)
                await asyncio.sleep(1.0)
