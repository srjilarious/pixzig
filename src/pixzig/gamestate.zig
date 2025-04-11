// zig fmt: off
const std = @import("std");
//const PixzigEngine = @import("./pixzig.zig").PixzigEngine;
const comp = @import("comp.zig");

pub fn GameStateMgr(comptime Engine: type, comptime StateKeysType: type, comptime States: []const type) type {


    // Contrain the state enum keys to be the same size as the provided states.
    const numStates = comp.numEnumFields(StateKeysType);
    if(numStates != States.len) {
        @compileError("Number of states in keys enum and provided list must match!");
    }

    // Generate the GameState Manager
    return struct {
        currStateIdx: usize,
        states: []*anyopaque,

        const Self = @This();

        pub fn init(states: []*anyopaque) @This() {
            
            // const enumTypeInfo = @typeInfo(StateKeysType);

            return .{
                .currStateIdx = 0,
                .states = states
            };
        }

        pub fn deinit(self: *Self) void {
            _ = self;
        }

        pub fn setCurrState(self: *Self, state: StateKeysType) void {
            const oldState = self.currStateIdx;
            self.currStateIdx = @intFromEnum(state);
           
            std.log.debug("oldState = {}, currState = {}", .{oldState, self.currStateIdx});

            // Check to deactivate the old state.
            inline for(0..States.len) |idx| {
                if(oldState == idx) {
                    const stateType = States[idx];
                    std.log.debug("Deactivating state: {}", .{idx});
                    if(@hasDecl(stateType, "deactivate")) {
                        const statePtr: *stateType = @alignCast(@ptrCast(self.states[oldState]));
                        statePtr.deactivate();
                    }
                }
            }

            // Check to activate the new state.
            inline for(0..States.len) |idx| {
                if(self.currStateIdx == idx) {
                    const stateType = States[idx];
                    std.log.debug("Activating state: {}", .{idx});
                    if(@hasDecl(stateType, "activate")) {
                        const statePtr: *stateType = @alignCast(@ptrCast(self.states[self.currStateIdx]));
                        statePtr.activate();
                    }
                }
            }
        }

        pub fn update(self: *Self, eng: *Engine, deltaUs: f64) bool {
            inline for(0..States.len) |idx| {
                if(self.currStateIdx == idx) {
                    const stateType = States[idx];
                    const statePtr: *stateType = @alignCast(@ptrCast(self.states[idx]));
                    return statePtr.update(eng, deltaUs);
                }
            }
            return false;
        }

        pub fn render(self: *Self, eng: *Engine) void {
            inline for(0..States.len) |idx| {
                if(self.currStateIdx == idx) {
                    const stateType = States[idx];
                    const statePtr: *stateType = @alignCast(@ptrCast(self.states[idx]));
                    return statePtr.render(eng);
                }
            }
        }
    };
}

