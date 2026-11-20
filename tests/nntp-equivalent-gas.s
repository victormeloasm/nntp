.intel_syntax noprefix
.section .text
.global start
server:
  .short 2, 0x7B00
  .long 0x0023EFD8
  .quad 0
request:
  .byte 0x23
  .zero 47
start:
  push 41
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
  mov ebx, eax

  push 0
  push 1
  sub rsp, 48
  mov eax, 54
  mov edi, ebx
  push 1
  pop rsi
  mov edx, 20
  lea r10, [rsp+48]
  mov r8d, 16
  syscall
  test eax, eax
  js fatal

  mov r12d, 1
retry:
  mov eax, 42
  mov edi, ebx
  mov rsi, OFFSET FLAT:server
  push 16
  pop rdx
  syscall
  test eax, eax
  js fallback

  push 1
  pop rax
  mov rsi, OFFSET FLAT:request
  mov edx, 48
  syscall
  cmp eax, 48
  jne fallback

  xor eax, eax
  mov rsi, rsp
  syscall
  cmp eax, 48
  jne fallback

  mov al, byte ptr [rsp]
  and al, 7
  cmp al, 4
  jne fallback
  cmp byte ptr [rsp+1], 0
  je fallback

  mov eax, dword ptr [rsp+40]
  bswap eax
  sub eax, 2208988800
  movsxd rax, eax
  mov qword ptr [rsp+48], rax
  mov eax, 227
  xor edi, edi
  lea rsi, [rsp+48]
  syscall
  neg eax
  mov edi, eax
  jmp finish
fallback:
  dec r12d
  js fatal
  mov dword ptr [rip+server+4], 0x01C89FA2
  jmp retry
fatal:
  push 1
  pop rdi
finish:
  push 60
  pop rax
  syscall
