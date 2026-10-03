extends Node
## One music player for the whole game. Menu track, then the game track.
## The game file is about 5 seconds, so it loops until something else calls play_menu.

const MENU_PATH := "res://assets/audio/menu_piano.mp3"
const GAME_PATH := "res://assets/audio/game.wav"

var _player: AudioStreamPlayer
var _current_path := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_player = AudioStreamPlayer.new()
	_player.name = "MusicStream"
	_player.process_mode = Node.PROCESS_MODE_ALWAYS
	_player.finished.connect(_on_finished)
	add_child(_player)


func play_menu() -> void:
	_play(MENU_PATH)


func play_game() -> void:
	_play(GAME_PATH)


func _play(path: String) -> void:
	if _current_path == path and _player.playing:
		return
	var stream := load(path) as AudioStream
	if stream == null:
		push_warning("[Music] load failed: %s" % path)
		return
	stream = stream.duplicate()
	# Godot 4.3+: AudioStreamWAV 没有 loop 属性（用 loop_mode/loop_end），跳过
	if stream is AudioStreamMP3:
		stream.loop = true
	elif stream is AudioStreamOggVorbis:
		stream.loop = true
	_player.stop()
	_player.stream = stream
	_player.play()
	_current_path = path
	print("[Music] play ", path)


func _on_finished() -> void:
	# Import loop should already repeat. This is the backup if the stream still ends.
	if _current_path == "":
		return
	_player.play()
