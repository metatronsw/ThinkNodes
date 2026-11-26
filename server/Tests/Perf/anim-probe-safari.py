import os, sys, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from perf import Safari
s = Safari()
try:
    s.call("POST", "/url", {"url": "http://localhost:8888/bench-anim.svg"})
    time.sleep(2)
    code = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "anim-probe.js")).read()
    print("Safari:", s.js("return " + code.split("\n", 2)[2].strip().rstrip(";")))
finally:
    s.close()
