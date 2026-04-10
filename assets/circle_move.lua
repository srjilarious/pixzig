-- circle_move.lua
-- Moves the player entity in a 16-pixel square using the seq_* API.
--
-- Expected globals set by Zig before running this script:
--   player_entity  : integer  (flecs entity ID)
--   player_x       : number   (sprite left edge in game units)
--   player_y       : number   (sprite top edge in game units)

local step = 16
local ms   = 300

local h = seq_new()

seq_set_actor_state(h, player_entity, "right")
seq_move_to(h, player_entity, player_x + step, player_y, ms)

seq_set_actor_state(h, player_entity, "down")
seq_move_to(h, player_entity, player_x + step, player_y + step, ms)

seq_set_actor_state(h, player_entity, "left")
seq_move_to(h, player_entity, player_x, player_y + step, ms)

seq_set_actor_state(h, player_entity, "up")
seq_move_to(h, player_entity, player_x, player_y, ms)

seq_play(h)
