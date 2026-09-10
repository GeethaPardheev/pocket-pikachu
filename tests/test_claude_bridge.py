import importlib.util, pathlib, tempfile, os, pty, subprocess, time, json, unittest
SOURCE=pathlib.Path(__file__).resolve().parents[1]/'integrations/claude/bridge.py'
spec=importlib.util.spec_from_file_location('bridge',SOURCE); bridge=importlib.util.module_from_spec(spec); spec.loader.exec_module(bridge)
class BridgeTest(unittest.TestCase):
    def test_live_output_send_interrupt_and_cleanup(self):
        with tempfile.TemporaryDirectory(prefix='bbtest-') as temp:
            root=pathlib.Path(temp); bridge.ROOT=root/'events'
            fake=root/'claude'
            fake.write_text('#!/usr/bin/python3\nimport os,tty\ntty.setraw(0)\nprint("FAKE READY",flush=True)\nbuf=b""\nwhile True:\n d=os.read(0,4096)\n buf+=d\n if b"quit-test" in buf: break\n os.write(1,b"RECEIVED:"+d.hex().encode()+b"\\n")\n')
            fake.chmod(0o700)
            master,slave=pty.openpty()
            code='import importlib.util,pathlib; s=importlib.util.spec_from_file_location("b",'+repr(str(SOURCE))+'); b=importlib.util.module_from_spec(s); s.loader.exec_module(b); b.ROOT=pathlib.Path('+repr(str(bridge.ROOT))+'); b.run([])'
            child=subprocess.Popen(['/usr/bin/python3','-c',code],stdin=slave,stdout=slave,stderr=slave,env={**os.environ,'PATH':temp+':/usr/bin:/bin'})
            os.close(slave)
            import threading
            def drain():
                try:
                    while os.read(master,8192): pass
                except OSError: pass
            threading.Thread(target=drain,daemon=True).start()
            def snapshot(needle):
                end=time.monotonic()+6
                while time.monotonic()<end:
                    for f in bridge.ROOT.glob('*.json'):
                        data=json.loads(f.read_text())
                        if needle in data['output']: return data
                    time.sleep(.05)
                self.fail('Snapshot missing '+needle)
            try:
                item=snapshot('FAKE READY')
                bridge.control(item['id'],'send','hello')
                snapshot('68656c6c6f')
                bridge.control(item['id'],'interrupt')
                snapshot('RECEIVED:1b')
                with self.assertRaises(ValueError): bridge.control('../bad','send','x')
                with self.assertRaises(ValueError): bridge.control(item['id'],'send','\x1bunsafe')
                os.kill(item['pid'],15); child.wait(timeout=5)
                self.assertFalse(list(bridge.ROOT.glob('*.json')))
            finally:
                if child.poll() is None: child.terminate(); child.wait(timeout=5)
                os.close(master)
if __name__=='__main__': unittest.main()
