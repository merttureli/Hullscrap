extends RefCounted
## Minimal test base. Test files are tests/test_*.gd extending this; each test_* method uses
## check()/eq(), and tests/run_tests.gd collects the failures.

var failures: Array[String] = []


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures.append(msg)


func eq(got, want, msg: String) -> void:
	if got != want:
		failures.append("%s: expected %s, got %s" % [msg, str(want), str(got)])
