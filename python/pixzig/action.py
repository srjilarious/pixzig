"""Action maps: named actions and axes bound to keys, buttons and sticks.

Game code asks "is the player jumping?" instead of "is Space down?". One
action can have a key and a gamepad button at once, and players can rebind
them. Create a map with `App.create_action_map()`.

Several bindings on one action are OR'ed together; several on one axis add
up, so a keyboard and a stick can both drive `move_x`. Action and axis names
are any strings, assigned to the engine's slots the first time a `bind_*`
call names them. There are 64 action slots and 32 axis slots.

Example:
        actions = app.create_action_map()
        actions.bind_key("jump", Key.SPACE)
        actions.bind_gamepad_button("jump", GamepadButton.A)
        actions.bind_axis_buttons("move_x", Key.A, Key.D)

        # Once per update tick:
        actions.update()
        if actions.pressed("jump"):
            hero.jump()
        dx = actions.axis("move_x")
"""
from . import _native as _n


class ActionMap:
    """Named actions and axes bound to physical inputs.

    Create one with `App.create_action_map()`, bind it once, then call `update()`
    at the top of every `update` tick before querying it.
    """
    def __init__(self, handle):
        self._handle = handle
        self._destroyed = False
        self._action_slots: dict[str, int] = {}
        self._axis_slots: dict[str, int] = {}

    def _check_alive(self) -> None:
        if self._destroyed:
            raise _n.Error("action map already destroyed (or the app has shut down)")

    def _slot_for_bind(self, slots: dict, name: str, max_slots: int, kind: str) -> int:
        slot = slots.get(name)
        if slot is not None:
            return slot
        if len(slots) >= max_slots:
            raise _n.Error(f"too many {kind}s bound (max {max_slots})")
        slot = len(slots)
        slots[name] = slot
        return slot

    def _slot_for_query(self, slots: dict, name: str, kind: str) -> int:
        slot = slots.get(name)
        if slot is None:
            raise _n.Error(f"unknown {kind} '{name}' -- bind it before querying")
        return slot

    # --- Binding -----------------------------------------------------------

    def bind_key(self, action: str, key: int) -> None:
        """Binds a keyboard key to an action.

        Args:
            action: The action's name.
            key: A `Key`.

        Raises:
            pixzig.Error: All 64 action slots are taken, or the map was destroyed.
        """
        self._check_alive()
        slot = self._slot_for_bind(self._action_slots, action, 64, "action")
        _n.check(_n.pz_action_bind_key(self._handle, slot, key) == 0)

    def bind_mouse_button(self, action: str, button: int) -> None:
        """Binds a mouse button to an action.

        Args:
            action: The action's name.
            button: A `MouseButton`.

        Raises:
            pixzig.Error: All 64 action slots are taken, or the map was destroyed.
        """
        self._check_alive()
        slot = self._slot_for_bind(self._action_slots, action, 64, "action")
        _n.check(_n.pz_action_bind_mouse_button(self._handle, slot, button) == 0)

    def bind_gamepad_button(self, action: str, button: int) -> None:
        """Binds a gamepad button to an action. It reads gamepad slot 0.

        Args:
            action: The action's name.
            button: A `GamepadButton`.

        Raises:
            pixzig.Error: All 64 action slots are taken, or the map was destroyed.
        """
        self._check_alive()
        slot = self._slot_for_bind(self._action_slots, action, 64, "action")
        _n.check(_n.pz_action_bind_gamepad_button(self._handle, slot, button) == 0)

    def bind_axis_buttons(self, axis: str, negative_key: int, positive_key: int) -> None:
        """Binds a pair of keys to an axis, reading -1, 0 or 1.

        Args:
            axis: The axis's name.
            negative_key: The `Key` that pushes it toward -1.
            positive_key: The `Key` that pushes it toward 1.

        Raises:
            pixzig.Error: All 32 axis slots are taken, or the map was destroyed.
        """
        self._check_alive()
        slot = self._slot_for_bind(self._axis_slots, axis, 32, "axis")
        _n.check(_n.pz_action_bind_axis_buttons(self._handle, slot, negative_key, positive_key) == 0)

    def bind_axis_gamepad(self, axis: str, gamepad_axis: int, deadzone: float = 0.18) -> None:
        """Binds a gamepad stick or trigger axis to an axis. It reads gamepad slot 0.

        Args:
            axis: The axis's name.
            gamepad_axis: A `GamepadAxis`.
            deadzone: Readings closer to center than this count as 0. A stick's is
                measured on the whole stick, both axes together, so diagonals stay
                smooth; a trigger's on its own.

        Raises:
            pixzig.Error: All 32 axis slots are taken, or the map was destroyed.
        """
        self._check_alive()
        slot = self._slot_for_bind(self._axis_slots, axis, 32, "axis")
        _n.check(_n.pz_action_bind_axis_gamepad(self._handle, slot, gamepad_axis, float(deadzone)) == 0)

    def bind_axis_mouse(self, axis: str, mouse_axis: int, sensitivity: float = 1.0, clamp: float = 1.0) -> None:
        """Binds mouse movement to an axis, for mouse look.

        Args:
            axis: The axis's name.
            mouse_axis: A `MouseAxis`.
            sensitivity: Scales the tick's movement, in window coordinates.
            clamp: The largest value the axis reports, either way.

        Raises:
            pixzig.Error: All 32 axis slots are taken, or the map was destroyed.
        """
        self._check_alive()
        slot = self._slot_for_bind(self._axis_slots, axis, 32, "axis")
        _n.check(
            _n.pz_action_bind_axis_mouse(self._handle, slot, mouse_axis, float(sensitivity), float(clamp)) == 0
        )

    # --- Per-tick update -----------------------------------------------------

    def update(self) -> None:
        """Reads this tick's input into the map. Call it once per `update`, first."""
        self._check_alive()
        _n.pz_action_map_update(self._handle, 0.0)

    # --- Query -----------------------------------------------------------

    def up(self, action: str) -> bool:
        """Whether an action is not held.

        Args:
            action: A bound action's name.

        Returns:
            True when none of its bindings are held.

        Raises:
            pixzig.Error: Nothing has been bound to that name.
        """
        self._check_alive()
        slot = self._slot_for_query(self._action_slots, action, "action")
        return bool(_n.pz_action_up(self._handle, slot))

    def down(self, action: str) -> bool:
        """Whether an action is held.

        Args:
            action: A bound action's name.

        Returns:
            True while any of its bindings is held.

        Raises:
            pixzig.Error: Nothing has been bound to that name.
        """
        self._check_alive()
        slot = self._slot_for_query(self._action_slots, action, "action")
        return bool(_n.pz_action_down(self._handle, slot))

    def pressed(self, action: str) -> bool:
        """Whether an action was pressed this tick.

        Args:
            action: A bound action's name.

        Returns:
            True for exactly one tick, the one it went down on.

        Raises:
            pixzig.Error: Nothing has been bound to that name.
        """
        self._check_alive()
        slot = self._slot_for_query(self._action_slots, action, "action")
        return bool(_n.pz_action_pressed(self._handle, slot))

    def released(self, action: str) -> bool:
        """Whether an action was released this tick.

        Args:
            action: A bound action's name.

        Returns:
            True for exactly one tick, the one it went up on.

        Raises:
            pixzig.Error: Nothing has been bound to that name.
        """
        self._check_alive()
        slot = self._slot_for_query(self._action_slots, action, "action")
        return bool(_n.pz_action_released(self._handle, slot))

    def axis(self, axis: str) -> float:
        """Reads an axis.

        Args:
            axis: A bound axis's name.

        Returns:
            The sum of its bindings, from -1 to 1 for keys and sticks.

        Raises:
            pixzig.Error: Nothing has been bound to that name.
        """
        self._check_alive()
        slot = self._slot_for_query(self._axis_slots, axis, "axis")
        return _n.pz_action_axis(self._handle, slot)

    def destroy(self) -> None:
        """Frees the map now instead of when the app shuts down.

        Calling it twice does nothing. Using the map afterwards raises.
        """
        if not self._destroyed:
            _n.pz_action_map_destroy(self._handle)
            self._destroyed = True
