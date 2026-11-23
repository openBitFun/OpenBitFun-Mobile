"""Mirror a GenUI test sender across the Android Emulator's virtual network."""

import argparse
import ipaddress
import os
import re
import selectors
import shlex
import socket
import socketserver
import subprocess
import threading
import time

ENDPOINT = "/sdcard/Android/data/com.openbitfun.mobile.debug/files/genui-nearby-endpoint.txt"
SERVICE_TYPE = "_obf-img-v2._tcp"
PRIVATE_NETWORKS = tuple(ipaddress.ip_network(cidr) for cidr in (
    "10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16", "169.254.0.0/16",
))
ANDROID_RECEIVER = "com.openbitfun.mobile.app.GenUiNearbyImagesTest#receiveGalleryImageFromNearbySimulator"
ANDROID_RUNNER = "com.openbitfun.mobile.debug.test/androidx.test.runner.AndroidJUnitRunner"


def sender_endpoint(adb):
    deadline = time.monotonic() + 40
    while time.monotonic() < deadline:
        result = subprocess.run(
            [*adb, "shell", "cat", ENDPOINT], capture_output=True, text=True, timeout=5,
        )
        if result.returncode == 0:
            address, raw_port = result.stdout.split()
            port = int(raw_port)
            endpoint_address = ipaddress.ip_address(address)
            if not any(endpoint_address in network for network in PRIVATE_NETWORKS) or endpoint_address.is_loopback or not 1024 <= port <= 65535:
                raise ValueError("The test must publish a private Android socket")
            return address, port
        time.sleep(0.25)
    raise TimeoutError("The Android sender did not publish its test socket")


class Bridge(socketserver.BaseRequestHandler):
    def handle(self):
        server = self.server
        address, port = server.emulator_endpoint
        process = subprocess.Popen(
            [*server.adb, "shell", "-T", "toybox", "nc", address, str(port)],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
        )

        def to_emulator():
            try:
                while data := self.request.recv(65536):
                    process.stdin.write(data)
                    process.stdin.flush()
            except OSError:
                pass
            finally:
                process.stdin.close()

        upstream = threading.Thread(target=to_emulator, daemon=True)
        upstream.start()
        try:
            while data := process.stdout.read1(65536):
                self.request.sendall(data)
        except OSError:
            pass
        finally:
            try:
                self.request.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass
            process.terminate()
            process.wait(timeout=5)
            upstream.join(timeout=5)
            process.stdout.close()


class SimulatorServer(socketserver.ThreadingTCPServer):
    daemon_threads = True


def ios_endpoint(name):
    deadline = time.monotonic() + 60
    with subprocess.Popen(
        ["dns-sd", "-L", name, SERVICE_TYPE, "local."], stdout=subprocess.PIPE,
    ) as resolver, selectors.DefaultSelector() as events:
        events.register(resolver.stdout, selectors.EVENT_READ)
        pending = b""
        try:
            while (remaining := deadline - time.monotonic()) > 0 and events.select(remaining):
                chunk = os.read(resolver.stdout.fileno(), 4096)
                if not chunk:
                    break
                *lines, pending = (pending + chunk).split(b"\n")
                for line in lines:
                    address = re.search(rb"\bip=(\d+\.\d+\.\d+\.\d+)(?:\s|$)", line)
                    port = re.search(rb"\bport=(\d+)(?:\s|$)", line)
                    if address and port:
                        host = ipaddress.IPv4Address(address[1].decode())
                        port_number = int(port[1])
                        if any(host in network for network in PRIVATE_NETWORKS) and 1024 <= port_number <= 65535:
                            return str(host), port_number
            raise TimeoutError(f"The iOS simulator did not advertise an IPv4 endpoint for {name!r}")
        finally:
            resolver.terminate()
            resolver.wait(timeout=5)


class IosBridge(socketserver.BaseRequestHandler):
    def handle(self):
        def forward(source, destination):
            try:
                while data := source.recv(65536):
                    destination.sendall(data)
                destination.shutdown(socket.SHUT_WR)
            except OSError:
                pass

        with socket.create_connection(self.server.ios_endpoint, timeout=8) as sender:
            sender.settimeout(90)
            self.request.settimeout(90)
            upstream = threading.Thread(target=forward, args=(self.request, sender), daemon=True)
            upstream.start()
            forward(sender, self.request)
            upstream.join(timeout=5)


def run_android_receiver(adb, ios_sender):
    endpoint = ios_endpoint(ios_sender)
    with SimulatorServer(("127.0.0.1", 0), IosBridge) as server:
        server.ios_endpoint = endpoint
        host_port = server.server_address[1]
        guest_port = subprocess.check_output([*adb, "reverse", "tcp:0", f"tcp:{host_port}"], text=True).strip()
        print(f"Relaying the iOS simulator's verified stream from {ios_sender!r}", flush=True)
        server.timeout = 75
        threading.Thread(target=server.handle_request, daemon=True).start()
        try:
            command = shlex.join([
                "am", "instrument", "-w", "-e", "genuiNearbyIosSender", "iOS Simulator (OpenBitFun QA)",
                "-e", "genuiNearbyReversePort", guest_port, "-e", "class", ANDROID_RECEIVER, ANDROID_RUNNER,
            ])
            result = subprocess.run([*adb, "shell", command], stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                    text=True, timeout=160)
            print(result.stdout, end="")
            if result.returncode or "OK (1 test)" not in result.stdout:
                raise SystemExit(1)
        finally:
            subprocess.run([*adb, "reverse", "--remove", f"tcp:{guest_port}"], check=True)


def publish_android_sender(adb, host):
    endpoint = sender_endpoint(adb)
    with SimulatorServer((str(host), 0), Bridge) as server:
        server.adb = adb
        server.emulator_endpoint = endpoint
        port = server.server_address[1]
        announcement = subprocess.Popen(
            ["dns-sd", "-R", "Android Simulator (OpenBitFun QA)", SERVICE_TYPE, "local.",
             str(port), f"ip={host}", f"port={port}"],
        )
        try:
            print(f"Forwarding the Android simulator's verified stream at {host}:{port}", flush=True)
            server.serve_forever()
        except KeyboardInterrupt:
            pass
        finally:
            announcement.terminate()
            announcement.wait(timeout=5)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--adb", default="adb")
    parser.add_argument("--serial", required=True)
    direction = parser.add_mutually_exclusive_group(required=True)
    direction.add_argument("--host", type=ipaddress.IPv4Address, help="Publish the Android sender on this Mac address")
    direction.add_argument("--ios-sender", help="Receive an image from this iOS simulator's Bonjour service name")
    args = parser.parse_args()
    adb = [args.adb, "-s", args.serial]
    if args.ios_sender is not None:
        run_android_receiver(adb, args.ios_sender)
    else:
        if not args.host.is_private or args.host.is_loopback:
            parser.error("--host must be a private IPv4 interface address")
        publish_android_sender(adb, args.host)


if __name__ == "__main__":
    main()
