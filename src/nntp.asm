; nano-ntp v2 -- x86-64 Linux SNTP, no libc, no DNS, two servers.
; FASM: fasm nntp.asm nntp
;           Keep this program inside a trusted environment: the time is set
;           from unauthenticated NTP data (no NTS and no RTT correction).
; Optimizations: one sockaddr rewritten on fallback, stack RX buffer,
;                shared timeval/timespec storage, connected UDP socket.
format ELF64 executable 3
entry start
segment readable executable writeable

server:
    dw 2, 0x7B00                   ; AF_INET, port 123 network order
    dd 0x0023EFD8                  ; Google 216.239.35.0
    dq 0
request:
    db 0x23                        ; LI=0, VN=4, Mode=3
    rb 47

start:
    push 41                         ; socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
    pop rax
    push 2
    pop rdi
    push 2
    pop rsi
    push 17
    pop rdx
    syscall
    test eax, eax
    js fatal
    mov ebx, eax                    ; socket fd, preserved by SYSCALL

    push 0                          ; timeval (sec=1, usec=0)
    push 1
    sub rsp, 48                     ; receive buffer + timeval/timespec

    mov eax, 54                     ; setsockopt(SO_RCVTIMEO, 1s)
    mov edi, ebx
    push 1
    pop rsi                         ; SOL_SOCKET
    mov edx, 20                     ; SO_RCVTIMEO
    lea r10, [rsp+48]
    mov r8d, 16
    syscall
    test eax, eax
    js fatal

    mov r12d, 1                     ; one fallback attempt remaining
.retry:
    mov eax, 42                     ; connect(UDP socket, server, 16)
    mov edi, ebx
    mov rsi, server
    push 16
    pop rdx
    syscall
    test eax, eax
    js .fallback

    push 1                          ; write(fd, request, 48)
    pop rax
    mov rsi, request
    mov edx, 48
    syscall
    cmp eax, 48
    jne .fallback

    xor eax, eax                    ; read(fd, rsp, 48)
    mov rsi, rsp
    syscall
    cmp eax, 48
    jne .fallback

    mov al, [rsp]
    and al, 7                       ; reply must be NTP server mode (4)
    cmp al, 4
    jne .fallback
    cmp byte [rsp+1], 0             ; reject Kiss-o'-Death / invalid stratum
    je .fallback

    mov eax, [rsp+40]               ; server TX timestamp seconds (network BE)
    bswap eax
    sub eax, 2208988800            ; NTP epoch -> Unix epoch
    movsxd rax, eax                 ; signed time_t for pre-1970 dates
    mov [rsp+48], rax               ; tv_sec, tv_nsec still zero

    mov eax, 227                    ; clock_settime(CLOCK_REALTIME,...)
    xor edi, edi
    lea rsi, [rsp+48]
    syscall
    neg eax                         ; 0 on success, errno on failure
    mov edi, eax
    jmp finish

.fallback:
    dec r12d                        ; fallback counter survives SYSCALL
    js fatal
    mov dword [server+4], 0x01C89FA2 ; Cloudflare 162.159.200.1
    jmp .retry

fatal:
    push 1
    pop rdi
finish:
    push 60                         ; exit(status)
    pop rax
    syscall
