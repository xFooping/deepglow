extends Control
## Title screen: Continue / New Game / Quit. (Settings arrives in Phase 5.)

const GAMEPLAY_SCENE := "res://scenes/gameplay/Gameplay.tscn"
const SKILL_TREE_SCENE := "res://scenes/skilltree/SkillTree.tscn"

var _confirm: ConfirmationDialog


func _ready() -> void:
	var bg := TitleBackdrop.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	center.add_child(box)

	var title := Label.new()
	title.text = "DEEPGLOW"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 64)
	title.add_theme_color_override("font_color", Color(1.0, 0.75, 0.4))
	box.add_child(title)
	var tagline := Label.new()
	tagline.text = "a cozy descent"
	tagline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tagline.add_theme_color_override("font_color", Color(0.85, 0.78, 0.95))
	box.add_child(tagline)

	var has_save := SaveManager.has_save()
	var cont := _button("Continue", _on_continue)
	cont.disabled = not has_save
	box.add_child(cont)
	box.add_child(_button("New Game", _on_new_game))
	box.add_child(_button("Quit", _on_quit))
	if has_save:
		cont.grab_focus()

	_confirm = ConfirmationDialog.new()
	_confirm.dialog_text = "Start over? Your current save will be erased."
	_confirm.confirmed.connect(_start_new_game)
	add_child(_confirm)


func _button(text: String, handler: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(120, 0)
	b.pressed.connect(handler)
	return b


## Saves are written between days, so Continue lands on the skill tree.
func _on_continue() -> void:
	get_tree().change_scene_to_file(SKILL_TREE_SCENE)


func _on_new_game() -> void:
	if SaveManager.has_save():
		_confirm.popup_centered()
	else:
		_start_new_game()


func _start_new_game() -> void:
	SaveManager.delete_save()
	GameState.reset_to_new_game()
	Stats.recompute()
	get_tree().change_scene_to_file(GAMEPLAY_SCENE)


func _on_quit() -> void:
	get_tree().root.propagate_notification(NOTIFICATION_WM_CLOSE_REQUEST)
