extends SceneTree

const BenchmarkScript = preload("res://scripts/additional_experiments_benchmark.gd")

func _init() -> void:
    var request_path = "res://work/run_request.json"
    for arg in OS.get_cmdline_user_args():
        if arg.begins_with("--request="):
            request_path = arg.trim_prefix("--request=")
    var file = FileAccess.open(request_path, FileAccess.READ)
    if file == null:
        push_error("Cannot open request: %s" % request_path)
        quit(2); return
    var parsed = JSON.parse_string(file.get_as_text())
    if typeof(parsed) != TYPE_DICTIONARY:
        push_error("Invalid request JSON: %s" % request_path)
        quit(3); return
    var bench = BenchmarkScript.new()
    var result: Dictionary = bench.execute(parsed)
    if not bool(result.get("ok", false)):
        push_error(str(result.get("error", "additional experiments failed")))
        quit(4); return
    print(str(result.get("marker", "CIAS_ADDITIONAL_RUN_COMPLETE")))
    quit(0)
