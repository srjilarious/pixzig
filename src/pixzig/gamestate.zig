// zig fmt: off
const std = @import("std");
const PixzigEngine = @import("./pixzig.zig").PixzigEngine;
const comp = @import("comp.zig");

pub fn GameStateMgr(comptime StateKeysType: type, comptime States: []const type) type {
    // Generate the GameState Manager
    return struct {
        currState: StateKeysType,
        states: []*anyopaque,

        pub fn init(comptime states: []*anyopaque) @This() {
            // Contrain the state enum keys to be the same size as the provided states.
            const numStates = comp.numEnumFields(StateKeysType);
            _ = numStates;
            // if(numStates != states.len) {
            //     @compileLog(numStates);
            //     @compileLog(states.len);
            //     @compileLog(states[0]);
            //     @compileLog(states[1]);
            //     @compileError("Number of states in keys enum and provided list must match!");
            // }
            
            // const enumTypeInfo = @typeInfo(StateKeysType);

            return .{
                .currState = @enumFromInt(0),
                .states = states
            };
        }

        pub fn setCurrState(self: *@This(), state: StateKeysType) void {
            self.currState = state;
        }

        pub fn update(self: *@This(), eng: *PixzigEngine, deltaUs: f64) bool {
            const stateIdx = @intFromEnum(self.currState);
            inline for(0..States.len) |idx| {
                if(stateIdx == idx) {
                    const stateType = States[idx];
                    const statePtr: *stateType = @ptrCast(self.states[stateIdx]);
                    return statePtr.update(eng, deltaUs);
                }
            }
            return false;
        }

        pub fn render(self: *@This(), eng: *PixzigEngine) void {
            const stateIdx = @intFromEnum(self.currState);
            inline for(0..States.len) |idx| {
                if(stateIdx == idx) {
                    const stateType = States[idx];
                    const statePtr: *stateType = @ptrCast(self.states[stateIdx]);
                    return statePtr.render(eng);
                }
            }
        }
    };
}

