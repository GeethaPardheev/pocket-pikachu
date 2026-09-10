#!/usr/bin/python3
"""Own a Claude PTY; expose bounded local output and explicit user controls."""
import os, sys, json, socket, select, time, uuid, pathlib, re, signal, termios, tty, fcntl, struct
ROOT = pathlib.Path.home() / 'Library/Application Support/PocketPikachu/claude'
ANSI = re.compile(r'\x1b\][^\x07]*(?:\x07|\x1b\\)|\x1b\[[0-?]*[ -/]*[@-~]|\x1b[@-_]')

def control(session, action, text=''):
    if not re.fullmatch(r'[a-f0-9]{32}', session): raise ValueError('Invalid session')
    if action not in ('send', 'interrupt'): raise ValueError('Invalid action')
    if not isinstance(text, str) or len(text.encode()) > 16000 or any(ord(c)<32 and c not in '\n\t' for c in text):
        raise ValueError('Unsupported input')
    endpoint = ROOT / (session+'.sock')
    with socket.socket(socket.AF_UNIX) as client:
        client.settimeout(2); client.connect(str(endpoint.resolve(strict=True)))
        client.sendall(json.dumps({'action':action,'text':text}).encode()+b'\n')
        reply = client.recv(1024)
        if reply != b'OK\n': raise RuntimeError(reply.decode(errors='replace'))

def run(args):
    import pty, shutil
    if not sys.stdin.isatty(): raise RuntimeError('Run pikachu-claude in an interactive terminal')
    executable = shutil.which('claude') or str(pathlib.Path.home()/'.local/bin/claude')
    if not os.path.isfile(executable): raise RuntimeError('Install Claude Code first')
    os.umask(0o077); ROOT.mkdir(parents=True,exist_ok=True); os.chmod(ROOT,0o700)
    session=uuid.uuid4().hex; endpoint=ROOT/(session+'.sock'); snapshot=ROOT/(session+'.json')
    # macOS Unix socket paths have a short limit; use a private short directory.
    import tempfile
    short=pathlib.Path(tempfile.mkdtemp(prefix='bb-')); actual=short/'s'
    endpoint.symlink_to(actual)
    server=socket.socket(socket.AF_UNIX); server.bind(str(actual)); server.listen(4)
    pid,master=pty.fork()
    if pid==0: os.execv(executable,[executable,'--ax-screen-reader']+args)
    previous=termios.tcgetattr(0); output=''; last=0; clients={}
    def resize(*_):
        try: fcntl.ioctl(master,termios.TIOCSWINSZ,fcntl.ioctl(0,termios.TIOCGWINSZ,b'\0'*8))
        except OSError: pass
    resize(); signal.signal(signal.SIGWINCH,resize)
    def shutdown(*_): raise SystemExit(0)
    signal.signal(signal.SIGTERM,shutdown); signal.signal(signal.SIGHUP,shutdown)
    def publish(state='Connected'):
        clean=ANSI.sub('',output).replace('\r','\n')
        clean=''.join(c for c in clean if c in '\n\t' or ord(c)>=32)
        data={'id':session,'pid':pid,'project':pathlib.Path.cwd().name,'updated':time.time(),'state':state,'output':clean[-8000:]}
        temp=snapshot.with_suffix('.tmp'); temp.write_text(json.dumps(data)); temp.replace(snapshot)
    try:
        tty.setraw(0); publish()
        while True:
            exited,_ = os.waitpid(pid,os.WNOHANG)
            if exited: return
            ready,_,_=select.select([0,master,server]+list(clients),[],[],0.2)
            for stream in ready:
                if stream==0:
                    data=os.read(0,4096)
                    if data: os.write(master,data)
                elif stream==master:
                    try: data=os.read(master,8192)
                    except OSError: return
                    if not data: return
                    os.write(1,data); output=(output+data.decode(errors='replace'))[-24000:]
                elif stream==server:
                    c,_=server.accept(); c.setblocking(False); clients[c]=(b'',time.monotonic())
                else:
                    c=stream; data=c.recv(18000); buf,started=clients[c]; buf+=data
                    if b'\n' in buf or not data or len(buf)>17000:
                        try:
                            request=json.loads(buf)
                            action=request.get('action'); text=request.get('text','')
                            if action=='interrupt': os.write(master,b'\x1b')
                            elif action=='send' and isinstance(text,str) and len(text.encode())<=16000 and text.strip() and not any(ord(ch)<32 and ch not in '\n\t' for ch in text):
                                os.write(master,b'\x1b[200~'+text.encode()+b'\x1b[201~\r')
                            else: raise ValueError('Invalid control')
                            c.send(b'OK\n')
                        except Exception:
                            try: c.send(b'ERROR\n')
                            except OSError: pass
                        c.close(); clients.pop(c,None)
                    else: clients[c]=(buf,started)
            for c,(_,started) in list(clients.items()):
                if time.monotonic()-started>2: c.close(); clients.pop(c,None)
            if time.monotonic()-last>0.5: publish(); last=time.monotonic()
    finally:
        termios.tcsetattr(0,termios.TCSADRAIN,previous)
        for c in clients: c.close()
        server.close(); os.close(master)
        try: os.kill(pid,signal.SIGHUP)
        except ProcessLookupError: pass
        for path in (snapshot,endpoint,actual):
            try: path.unlink()
            except FileNotFoundError: pass
        try: short.rmdir()
        except OSError: pass

if __name__=='__main__':
    try:
        if len(sys.argv)>1 and sys.argv[1]=='control':
            data=json.load(sys.stdin); control(data['id'],data['action'],data.get('text',''))
        else: run(sys.argv[1:])
    except Exception as e:
        print('Pikachu Claude: '+str(e),file=sys.stderr); sys.exit(1)
