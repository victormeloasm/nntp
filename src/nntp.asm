; nntp.asm — nano-ntp: SNTP mínimo (sem debug)
; Montar:  fasm nntp.asm
; Rodar:   sudo ./nntp   (ou: sudo setcap cap_sys_time=+ep ./nntp && ./nntp)

format ELF64 executable 3
entry start

segment readable executable writeable

; ---- syscalls / const ----
SYS_socket        = 41
SYS_setsockopt    = 54
SYS_sendto        = 44
SYS_recvfrom      = 45
SYS_clock_settime = 227
SYS_exit          = 60

AF_INET = 2
SOCK_DGRAM = 2
IPPROTO_UDP = 17
SOL_SOCKET  = 1
SO_RCVTIMEO = 20
CLOCK_REALTIME = 0
NTP_DELTA = 2208988800

; ---- dados ----
; sockaddr_in (16B cada): u16 family; u16 port (BE); u32 addr (BE); u8 zero[8]
socklist:
  ; Google NTP (216.239.35.0)
  dw AF_INET, 0x7B00
  dd 0x0023EFD8
  dq 0
  ; Cloudflare NTP (162.159.200.1)
  dw AF_INET, 0x7B00
  dd 0x01C89FA2
  dq 0
srvcount: db 2

; request 48B (LI=0, VN=4, Mode=3)
txpkt: db 0x23
       rb 47

rxpkt: rb 48        ; resposta
tv:    dq 1, 0      ; timeval {1s,0}
ts:    dq 0, 0      ; timespec {sec,nsec}

; ---- código ----
start:
  ; socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
  mov eax, SYS_socket
  mov edi, AF_INET
  mov esi, SOCK_DGRAM
  mov edx, IPPROTO_UDP
  syscall
  mov r12, rax

  ; setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, 16)
  mov eax, SYS_setsockopt
  mov edi, r12d
  mov esi, SOL_SOCKET
  mov edx, SO_RCVTIMEO
  mov r10, tv
  mov r8d, 16
  syscall

  xor ecx, ecx
  movzx edx, byte [srvcount]

.try_server:
  cmp ecx, edx
  jae .fail_all

  ; ptr = &socklist[idx] (cada item = 16B)
  mov rbx, socklist
  mov r8, rcx
  shl r8, 4
  add r8, rbx

  ; sendto(fd, txpkt, 48, 0, ptr, 16)
  mov eax, SYS_sendto
  mov edi, r12d
  mov rsi, txpkt
  mov edx, 48
  xor r10d, r10d
  mov r9d, 16
  syscall

  ; recvfrom(fd, rxpkt, 48, 0, NULL, NULL)
  mov eax, SYS_recvfrom
  mov edi, r12d
  mov rsi, rxpkt
  mov edx, 48
  xor r10d, r10d
  xor r8d,  r8d
  xor r9d,  r9d
  syscall
  cmp eax, 48
  jl .next_server

  ; unix = be32(rx[40..43]) - 2208988800
  mov eax, [rxpkt+40]
  bswap eax
  sub eax, NTP_DELTA
  mov [ts], rax
  xor eax, eax
  mov [ts+8], rax

  ; clock_settime(CLOCK_REALTIME, &ts)
  mov eax, SYS_clock_settime
  mov edi, CLOCK_REALTIME
  mov rsi, ts
  syscall

  ; exit(0)
  mov eax, SYS_exit
  xor edi, edi
  syscall

.next_server:
  inc ecx
  jmp .try_server

.fail_all:
  mov eax, SYS_exit
  mov edi, 1
  syscall
