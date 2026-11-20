#define _GNU_SOURCE
#include <sys/ptrace.h>
#include <sys/wait.h>
#include <sys/user.h>
#include <sys/types.h>
#include <unistd.h>
#include <errno.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <stdint.h>
#include <signal.h>
#include <time.h>

static int poke(pid_t pid, uint64_t where, const void *src, size_t len) {
    const uint8_t *p = src;
    for (size_t i = 0; i < len; i += 8) {
        uint64_t word = 0;
        size_t count = len - i < 8 ? len - i : 8;
        memcpy(&word, p+i, count);
        if (ptrace(PTRACE_POKEDATA, pid, (void*)(where+i), (void*)word) != 0) return -1;
    }
    return 0;
}
static uint64_t peek(pid_t pid, uint64_t where) {
    errno=0;
    return (uint64_t)ptrace(PTRACE_PEEKDATA,pid,(void*)where,0);
}
static void fail(const char* s) { perror(s); exit(2); }
static int check_case(const char* file,int scenario) {
    pid_t pid=fork(); if(pid<0)fail("fork");
    if(pid==0) {
        if(ptrace(PTRACE_TRACEME,0,0,0)<0) _exit(99);
        execl(file,file,NULL);
        _exit(98);
    }
    int status, in=0, sysno=-1, got_clock=0, connect_count=0, read_count=0;
    uint64_t arg_rsi=0;
    if(waitpid(pid,&status,0)<0)fail("waitpid");
    if(!WIFSTOPPED(status)) {fprintf(stderr,"initial unexpected %d\n",status);return 1;}
    if(ptrace(PTRACE_SETOPTIONS,pid,0,PTRACE_O_TRACESYSGOOD)<0) fail("setoptions");
    int expected= scenario==2||scenario==4||scenario==5||scenario==6 ? 1:0;
    for(int n=0;n<1000;n++) {
        if(ptrace(PTRACE_SYSCALL,pid,0,0)<0)fail("syscall");
        if(waitpid(pid,&status,0)<0)fail("waitpid");
        if(WIFEXITED(status)) {
            int code=WEXITSTATUS(status);
            int want_connections = scenario==2 ? 2 : scenario==5||scenario==6 ? 0 : ((scenario==1||scenario==3||scenario==7)?2:1);
            if(code!=expected || connect_count!=want_connections || (scenario==2 && got_clock) || ((scenario==0||scenario==1||scenario==3||scenario==7) && !got_clock)) {
                fprintf(stderr,"FAIL scenario %d: status=%d (want %d), connects=%d (want %d), clock=%d\n",scenario,code,expected,connect_count,want_connections,got_clock);
                return 1;
            }
            printf("PASS scenario %d status=%d connects=%d clock=%d\n",scenario,code,connect_count,got_clock);
            return 0;
        }
        if(WIFSIGNALED(status)) {fprintf(stderr,"unexpected signal %d\n",WTERMSIG(status));return 1;}
        if(!WIFSTOPPED(status))continue;
        int sig=WSTOPSIG(status);
        if(sig!=(SIGTRAP|0x80)) {fprintf(stderr,"signal %d in scenario %d\n",sig,scenario); ptrace(PTRACE_KILL,pid,0,0); return 1;}
        struct user_regs_struct r;
        if(ptrace(PTRACE_GETREGS,pid,0,&r)<0)fail("regs");
        if(!in) {
            in=1;sysno=r.orig_rax;arg_rsi=r.rsi;
            if(sysno!=60) {
                r.orig_rax=(unsigned long)-1;
                if(ptrace(PTRACE_SETREGS,pid,0,&r)<0)fail("set entry");
            }
        } else {
            in=0;
            if(sysno==60)continue;
            long result=-ENOSYS;
            if(sysno==41) result=scenario==5 ? -EPERM : 7;
            if(sysno==54) result=scenario==6 ? -EINVAL: 0;
            if(sysno==42) {
                connect_count++;
                uint64_t a=peek(pid,arg_rsi);
                uint32_t ip=(a>>32)&0xffffffffu;
                uint32_t desired=connect_count==1?0x0023efd8u:0x01c89fa2u;
                if(ip!=desired) {fprintf(stderr,"wrong server IP: %08x != %08x\n",ip,desired);ptrace(PTRACE_KILL,pid,0,0);return 1;}
                result=0;
            }
            if(sysno==1) {
                uint64_t a=peek(pid,arg_rsi);
                if((a&0xff)!=0x23u) {fprintf(stderr,"bad SNTP request byte %02lx\n",a&0xff);ptrace(PTRACE_KILL,pid,0,0);return 1;}
                result=(scenario==7 && connect_count==1)?20:48;
            }
            if(sysno==0) {
                read_count++;
                if((scenario==1 && read_count==1)||(scenario==2 && read_count<=2)) result=-EAGAIN;
                else {
                    uint8_t pkt[48]={0};
                    pkt[0]=0x24;pkt[1]=(scenario==3 && read_count==1) ? 0 : 2;
                    uint32_t secs=2208988800u+1777777777u;
                    pkt[40]=(secs>>24)&255;pkt[41]=(secs>>16)&255;pkt[42]=(secs>>8)&255;pkt[43]=secs&255;
                    if(poke(pid,arg_rsi,pkt,sizeof(pkt))<0) fail("poke response");
                    result=48;
                }
            }
            if(sysno==227) {
                got_clock++;
                uint64_t secs=peek(pid,arg_rsi);
                uint64_t nanos=peek(pid,arg_rsi+8);
                if(secs!=1777777777u || nanos!=0) {fprintf(stderr,"wrong time sec=%lu nsec=%lu\n",secs,nanos);ptrace(PTRACE_KILL,pid,0,0);return 1;}
                result=scenario==4 ? -EPERM:0;
            }
            if(result==-ENOSYS){fprintf(stderr,"Unexpected syscall %d\n",sysno);ptrace(PTRACE_KILL,pid,0,0);return 1;}
            r.rax=result;
            if(ptrace(PTRACE_SETREGS,pid,0,&r)<0)fail("set return");
        }
    }
    fprintf(stderr,"timeout tracing scenario %d\n",scenario);
    ptrace(PTRACE_KILL,pid,0,0);
    return 1;
}
int main(int argc,char**argv){if(argc<2)return 2;int err=0;for(int i=0;i<8;i++)err|=check_case(argv[1],i);return err;}
