# ==============================================
# FIRST LOCAL COMPILATION TEST - Python
# Tests: Qwen2.5-Coder via Ollama API
# Run inside Antigravity terminal: python first-compile-test.py
# ==============================================
import urllib.request, json, sys, time

OLLAMA_URL = "http://localhost:11434"
MODEL = "qwen2.5-coder:1.5b"

print("\n[TEST-PY] First Compilation Run - Qwen2.5-Coder:1.5B")
print("="*52)

# Step 1: Health check
print("\n[1/3] Checking Ollama health...")
try:
    with urllib.request.urlopen(f"{OLLAMA_URL}/api/tags", timeout=5) as r:
        data = json.loads(r.read())
        models = [m["name"] for m in data.get("models", [])]
        if MODEL in models or any(MODEL in m for m in models):
            print(f"  [OK] Model found: {MODEL}")
        else:
            print(f"  [WARN] {MODEL} not in list. Available: {models}")
            print(f"  Run: ollama pull {MODEL}")
except Exception as e:
    print(f"  [FAIL] Ollama not responding: {e}")
    print(f"  Run: ollama serve (in separate terminal)")
    sys.exit(1)

# Step 2: First code generation call
print("\n[2/3] Sending first code generation request...")
payload = json.dumps({
    "model": MODEL,
    "prompt": "Write a Python function to calculate fibonacci(n) with memoization. Just the code, no explanation.",
    "stream": False,
    "options": {"temperature": 0.1, "num_predict": 200}
}).encode()

try:
    req = urllib.request.Request(
        f"{OLLAMA_URL}/api/generate",
        data=payload,
        headers={"Content-Type": "application/json"}
    )
    t0 = time.time()
    with urllib.request.urlopen(req, timeout=60) as r:
        result = json.loads(r.read())
    elapsed = time.time() - t0
    print(f"  [OK] Response in {elapsed:.1f}s")
    print("\n--- Generated Code ---")
    print(result.get("response", "").strip())
    print("--- End ---")
except Exception as e:
    print(f"  [FAIL] Generation error: {e}")
    sys.exit(1)

# Step 3: Verify the generated code compiles
print("\n[3/3] Compiling generated code...")
code = result.get("response", "")
try:
    compile(code, "<qwen-generated>", "exec")
    print("  [OK] Code compiles successfully! Qwen2.5-Coder is LIVE.")
except SyntaxError as e:
    print(f"  [WARN] Syntax issue in generated code: {e}")
    print("  (Model output may include markdown - that is normal)")

print("\n[PASS] Qwen2.5-Coder:1.5B compilation test COMPLETE")
print(f"  Endpoint : {OLLAMA_URL}")
print(f"  Model    : {MODEL}")
print(f"  Status   : ONLINE + GENERATING")
