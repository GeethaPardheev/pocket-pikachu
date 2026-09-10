import unittest,subprocess,pathlib,json,base64,select,time,os,tempfile
HOST=pathlib.Path(__file__).resolve().parents[1]/'Resources/terminal/pty_host.py'
class TerminalTest(unittest.TestCase):
    def test_shell_resize_interrupt_and_isolation(self):
        with tempfile.TemporaryDirectory() as folder:
            sessions=[subprocess.Popen(['/usr/bin/python3',str(HOST)],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,cwd=folder,env={**os.environ,'ZDOTDIR':folder}) for _ in range(2)]
            def send(p,text):
                p.stdin.write((json.dumps({'kind':'input','data':base64.b64encode(text.encode()).decode()})+'\n').encode());p.stdin.flush()
            def until(p,needle):
                result=b''; deadline=time.monotonic()+8
                while time.monotonic()<deadline:
                    if select.select([p.stdout],[],[],.1)[0]:
                        chunk=os.read(p.stdout.fileno(),32768)
                        if not chunk: break
                        result+=chunk
                        if needle in result: return result
                self.fail('No expected terminal output: '+repr(result[-500:]))
            try:
                for p in sessions:
                    p.stdin.write(b'{"kind":"resize","cols":101,"rows":37}\n');p.stdin.flush()
                    send(p,"stty size\n"); until(p,b'37 101')
                send(sessions[0],"export PIKA_TEST_VALUE=one\n")
                send(sessions[1],"printf '\\nVALUE:%s\\n' ${PIKA_TEST_VALUE-unset}\n")
                until(sessions[1],b'VALUE:unset')
                send(sessions[0],"sleep 30\n");time.sleep(.2);send(sessions[0],'\x03')
                send(sessions[0],"printf '\\nINTERRUPTED_OK\\n'\n");until(sessions[0],b'\r\nINTERRUPTED_OK\r\n')
                for p in sessions: p.stdin.close();p.wait(timeout=4)
            finally:
                for p in sessions:
                    if p.poll() is None: p.terminate();p.wait(timeout=4)
                    p.stdout.close()
if __name__=='__main__':unittest.main()
