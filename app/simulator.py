import time
import os
import threading

def simulate_failure(mode: str = "crash"):
    if mode == "crash":
        os._exit(1)  # Kills process — K8s sees CrashLoopBackOff
    elif mode == "oom":
        # Allocate memory until OOMKilled
        data = []
        while True:
            data.append("x" * 10**7)
    elif mode == "slow":
        time.sleep(30)  # Readiness probe fails → pod marked unready
        return {"status": "recovered after 30s delay"}

def simulate_load(duration: int = 30, cpu_percent: int = 80):
    def burn_cpu():
        end_time = time.time() + duration
        while time.time() < end_time:
            _ = sum(i * i for i in range(10000))
    
    threads = max(1, int(os.cpu_count() * cpu_percent / 100))
    for _ in range(threads):
        t = threading.Thread(target=burn_cpu)
        t.daemon = True
        t.start()
    
    return {"status": "load_generating", "duration": duration, "threads": threads}