extends Control
## A stand-in for the map in tests: it only knows the ship (the team picker asks `map.ship()`).

var the_ship = null


func ship():
	return the_ship
