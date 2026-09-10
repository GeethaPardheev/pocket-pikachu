#!/usr/bin/python3
"""One owned interactive shell. Stdin: JSON controls. Stdout: raw PTY bytes."""
import os, sys, pty, json, base64, select, signal, struct, fcntl, termios

def main():
    pid, master=pty.fork()
    if pid==0:
        os.environ['TERM']='xterm-256color'
        os.environ['COLORTERM']='truecolor'
        os.environ['TERM_PROGRAM']='PocketPikachu'
        shell='/bin/zsh'
        os.execv(shell,[shell,'-l'])
    def shutdown(*_): raise SystemExit(0)
    signal.signal(signal.SIGTERM,shutdown); signal.signal(signal.SIGHUP,shutdown)
    pending=b''
    try:
        while True:
            done,status=os.waitpid(pid,os.WNOHANG)
            if done: return os.waitstatus_to_exitcode(status)
            ready,_,_=select.select([0,master],[],[],.2)
            for fd in ready:
                if fd==master:
                    try: data=os.read(master,32768)
                    except OSError: return 0
                    if not data: return 0
                    while data: data=data[os.write(1,data):]
                else:
                    chunk=os.read(0,65536)
                    if not chunk: return 0
                    pending+=chunk
                    if len(pending)>1500000: raise ValueError('Input too large')
                    while b'\n' in pending:
                        line,pending=pending.split(b'\n',1)
                        message=json.loads(line)
                        if message.get('kind')=='input':
                            data=base64.b64decode(message['data'],validate=True)
                            if len(data)>1000000: raise ValueError('Input too large')
                            while data: data=data[os.write(master,data):]
                        elif message.get('kind')=='resize':
                            cols=max(2,min(500,int(message['cols']))); rows=max(2,min(300,int(message['rows'])))
                            fcntl.ioctl(master,termios.TIOCSWINSZ,struct.pack('HHHH',rows,cols,0,0))
    finally:
        os.close(master)
        try: os.kill(pid,signal.SIGHUP)
        except ProcessLookupError: pass
if __name__=='__main__':
    try: sys.exit(main())
    except Exception as error: print('Terminal host: '+str(error),file=sys.stderr); sys.exit(1)
