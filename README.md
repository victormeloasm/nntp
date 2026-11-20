# nano-ntp v2 — Minimal SNTP Client in x86-64 Assembly

![nano-ntp logo](src/logo.png)

**nano-ntp** is a tiny Linux SNTP client written in x86-64 Assembly. It uses Linux system calls directly—**no libc, dynamic linker, DNS resolver, or external runtime dependencies**—to fetch a time value from an NTP server and set the system clock.

**v2 prebuilt ELF: 398 bytes** (353 bytes in `bin/nntp.zip`). The previous uncompressed ELF was 516 bytes, so this version is **118 bytes smaller (~22.9%)**. Both binaries are **64-bit**; the source uses `format ELF64 executable 3`.

> **Scope:** A size-optimized SNTP demonstration, not a secure or high-accuracy replacement for `chrony` or `systemd-timesyncd`.

## What's new in v2

- Fixed the fallback loop: `syscall` overwrites `RCX`, and `RDX` is reused for syscall arguments. The retry counter now survives both.
- Uses two hard-coded NTP endpoints: **Google** (`216.239.35.0:123`) and **Cloudflare** (`162.159.200.1:123`).
- Reuses one 16-byte `sockaddr_in`, updating the address for the fallback attempt.
- Uses a connected UDP socket, a stack-based 48-byte receive buffer, and shared storage for `timeval` / `timespec`.
- Checks syscall outcomes, the response length, server mode, and a nonzero stratum; reports failure with a nonzero exit status.
- Includes a syscall-interception test harness that **does not modify the host clock**.

## Clone and run the prebuilt binary

```bash
git clone https://github.com/victormeloasm/nntp.git
cd nntp
chmod +x bin/nntp
sudo ./bin/nntp
date -u
```

The command is normally silent. Check its return code immediately after running it, before `date`:

```bash
sudo ./bin/nntp
printf 'nano-ntp exit status: %s\n' "$?"
date -u
```

The program requires permission to change the system clock (`CAP_SYS_TIME`), which is why the examples use `sudo`. Do **not** grant persistent clock-setting privileges unless you understand the security implications.

## Build from source (FASM)

Install [Flat Assembler (FASM)](https://flatassembler.net/) and build:

```bash
fasm src/nntp.asm bin/nntp-fasm
chmod +x bin/nntp-fasm
wc -c bin/nntp-fasm
file bin/nntp-fasm
sudo ./bin/nntp-fasm
```

Building to `bin/nntp-fasm` leaves the supplied 398-byte binary untouched. **The 398-byte prebuilt executable was assembled from an equivalent GNU assembler listing** (`tests/nntp-equivalent-gas.s`); the size produced by FASM should be measured separately and is not guaranteed to match byte-for-byte.

## How it works

1. Open an IPv4 UDP socket and set a **one-second receive timeout**.
2. Send a 48-byte SNTPv4 client request to Google's NTP endpoint.
3. Require a 48-byte response, server mode (`4`), and nonzero stratum.
4. On connection, send, receive, or basic-validation failure, try Cloudflare.
5. Convert the server's transmit timestamp seconds from the NTP epoch to Unix time.
6. Call `clock_settime(CLOCK_REALTIME, ...)` to set the clock; return an error status if it fails.

The implementation deliberately omits fractional seconds, network-delay adjustment, and clock slewing. Setting the clock may be overwritten later by another time synchronization service.

## Tests (without changing the system clock)

The tests use Linux `ptrace` to intercept the executable's syscalls and simulate NTP responses and failures:

```bash
gcc -O2 -Wall tests/test_nntp.c -o tests/test_nntp
./tests/test_nntp ./bin/nntp
```

Covered scenarios include: primary-server success, fallback success, both timeouts, invalid stratum, `clock_settime` permission failure, socket failure, timeout-setting failure, and partial send. The tests exercise **the provided prebuilt binary**; they do not establish that every separately assembled build is byte-identical.

## Security and accuracy limitations

- **Unauthenticated time:** No NTS or request/response nonce matching. A capable network attacker may spoof or manipulate time responses; connecting UDP to a peer is **not authentication**.
- **Coarse timing:** Uses only whole seconds from the server's transmit timestamp; does not compute round-trip delay, clock offset, jitter, or subsecond precision.
- **Date range:** The 32-bit NTP seconds conversion does not robustly handle era rollover and dates around/after 2038.
- **Privileged operation:** Changing `CLOCK_REALTIME` affects the whole system and may disrupt logs, certificates, scheduled jobs, and other applications.
- **Size-first executable:** The minimal ELF uses a writable/executable load segment; it is not a hardened production binary.

For production machines or untrusted networks, use a maintained time synchronization client such as **chrony** or **systemd-timesyncd** instead.

## Repository layout

```text
nntp/
├── bin/
│   ├── nntp                     # 398-byte prebuilt Linux ELF64
│   └── nntp.zip                 # compressed prebuilt binary
├── src/
│   ├── nntp.asm                 # FASM source
│   └── logo.png
├── tests/
│   ├── test_nntp.c             # syscall-interception tests
│   └── nntp-equivalent-gas.s   # equivalent GNU assembler listing
├── LICENSE
└── README.md
```

## Author

**Víctor Duarte Melo** · 2025–2026

See [LICENSE](LICENSE) for licensing terms.
