extends "res://tests/base_test.gd"
## Small fixes found in the Beta 4 playthrough (docs/waves/playtest_2.md, the qa4 track).

const HelpPanel = preload("res://scripts/ui/help_panel.gd")
const Profile = preload("res://scripts/ui/profile.gd")


func test_how_to_play_names_the_ledger_key() -> void:
	var found := ""
	for col in HelpPanel.COLUMNS:
		for sec in col:
			for row in sec[1]:
				if str(row[0]) == "L":
					found = "%s: %s" % [sec[0], row[1]]
	check(found.contains("LEDGER") and found.contains("Ledger"), "the L key is on the F1 screen, under the Ledger: '%s'" % found)
	check(HelpPanel.all_text().contains("BOARDING"), "and the boarding keys are still there")


func test_the_beta_label_is_beta_4() -> void:
	eq(Profile.BETA, "Beta 4", "the main menu corner says Beta 4")
