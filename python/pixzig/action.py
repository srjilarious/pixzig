"""Action mapping: bind named actions/axes to physical inputs, then query
them by name instead of checking raw keyboard/mouse/gamepad state directly.
Create via `PixzigApp.create_action_map()`.

    actions = app.create_action_map()
    actions.bind_key("jump", Key.SPACE)
    actions.bind_gamepad_button("jump", GamepadButton.A)
    actions.bind_axis_buttons("move_x", Key.A, Key.D)

    # once per update tick:
    actions.update()
    if actions.pressed("jump"): ...
    dx = actions.axis("move_x")

Multiple bindings on the same action are OR'ed together; multiple bindings
on the same axis accumulate (sum). Action/axis names are arbitrary strings
assigned to internal slots on first use in a `bind_*` call -- there's a
fixed capacity (64 actions, 32 axes) shared with the underlying engine.
"""
from . import _native as _n


class ActionMap:
    def __init__(self, handle):
        self._handle = handle
        self._destroyed = False
        self._action_slots: dict[str, int] = {}
        self._axis_slots: dict[str, int] = {}

    def _check_alive(self) -> None:
        if self._destroyed:
            raise _n.PixzigError("action map already destroyed")

    def _slot_for_bind(self, slots: dict, name: str, max_slots: int, kind: str) -> int:
        slot = slots.get(name)
        if slot is not None:
            return slot
        if len(slots) >= max_slots:
            raise _n.PixzigError(f"too many {kind}s bound (max {max_slots})")
        slot = len(slots)
        slots[name] = slot
        return slot

    def _slot_for_query(self, slots: dict, name: str, kind: str) -> int:
        slot = slots.get(name)
        if slot is None:
            raise _n.PixzigError(f"unknown {kind} '{name}' -- bind it before querying")
        return slot

    # --- Binding -----------------------------------------------------------

    def bind_key(self, action: str, key: int) -> None:
        self._check_alive()
        slot = self._slot_for_bind(self._action_slots, action, 64, "action")
        _n.check(_n.pz_action_bind_key(self._handle, slot, key) == 0)

    def bind_mouse_button(self, action: str, button: int) -> None:
        self._check_alive()
        slot = self._slot_for_bind(self._action_slots, action, 64, "action")
        _n.check(_n.pz_action_bind_mouse_button(self._handle, slot, button) == 0)

    def bind_gamepad_button(self, action: str, button: int) -> None:
        self._check_alive()
        slot = self._slot_for_bind(self._action_slots, action, 64, "action")
        _n.check(_n.pz_action_bind_gamepad_button(self._handle, slot, button) == 0)

    def bind_axis_buttons(self, axis: str, negative_key: int, positive_key: int) -> None:
        self._check_alive()
        slot = self._slot_for_bind(self._axis_slots, axis, 32, "axis")
        _n.check(_n.pz_action_bind_axis_buttons(self._handle, slot, negative_key, positive_key) == 0)

    def bind_axis_gamepad(self, axis: str, gamepad_axis: int, deadzone: float = 0.18) -> None:
        self._check_alive()
        slot = self._slot_for_bind(self._axis_slots, axis, 32, "axis")
        _n.check(_n.pz_action_bind_axis_gamepad(self._handle, slot, gamepad_axis, float(deadzone)) == 0)

    def bind_axis_mouse(self, axis: str, mouse_axis: int, sensitivity: float = 1.0, clamp: float = 1.0) -> None:
        self._check_alive()
        slot = self._slot_for_bind(self._axis_slots, axis, 32, "axis")
        _n.check(
            _n.pz_action_bind_axis_mouse(self._handle, slot, mouse_axis, float(sensitivity), float(clamp)) == 0
        )

    # --- Per-tick update -----------------------------------------------------

    def update(self) -> None:
        self._check_alive()
        _n.pz_action_map_update(self._handle, 0.0)

    # --- Query -----------------------------------------------------------

    def up(self, action: str) -> bool:
        self._check_alive()
        slot = self._slot_for_query(self._action_slots, action, "action")
        return bool(_n.pz_action_up(self._handle, slot))

    def down(self, action: str) -> bool:
        self._check_alive()
        slot = self._slot_for_query(self._action_slots, action, "action")
        return bool(_n.pz_action_down(self._handle, slot))

    def pressed(self, action: str) -> bool:
        self._check_alive()
        slot = self._slot_for_query(self._action_slots, action, "action")
        return bool(_n.pz_action_pressed(self._handle, slot))

    def released(self, action: str) -> bool:
        self._check_alive()
        slot = self._slot_for_query(self._action_slots, action, "action")
        return bool(_n.pz_action_released(self._handle, slot))

    def axis(self, axis: str) -> float:
        self._check_alive()
        slot = self._slot_for_query(self._axis_slots, axis, "axis")
        return _n.pz_action_axis(self._handle, slot)

    def destroy(self) -> None:
        if not self._destroyed:
            _n.pz_action_map_destroy(self._handle)
            self._destroyed = True
